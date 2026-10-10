import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../../../shared/widgets/motion.dart';
import '../../import/presentation/receipt_scanner.dart';
import '../../settings/application/settings_providers.dart' show SettingKeys;
import '../../wallets/application/wallet_cloud.dart' show currentUid;
import '../../premium/application/usage_ping.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallet_widgets.dart' show walletIcon;
import '../application/transaction_providers.dart';

/// Values to prefill a new transaction with (e.g. from a scanned receipt).
class TransactionDraft {
  const TransactionDraft({this.amount, this.description, this.occurredAt});

  final Money? amount;
  final String? description;
  final DateTime? occurredAt;
}

/// Create (no [transactionId]) or edit an expense/income.
class TransactionFormScreen extends ConsumerWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.initialType = TransactionType.expense,
    this.draft,
    this.walletId,
  });

  final String? transactionId;
  final TransactionType initialType;
  final TransactionDraft? draft;

  /// New entry in this shared wallet (null = the user's own money).
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    if (id == null) return _TransactionForm(initial: null, initialType: initialType, draft: draft, walletId: walletId);

    return ref.watch(transactionByIdProvider(id)).when(
          data: (tx) => tx == null
              ? _MessageScaffold(context.tr('This transaction no longer exists.'))
              : _TransactionForm(initial: tx, initialType: tx.type),
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => _MessageScaffold(context.tr('Could not load this transaction.')),
        );
  }
}

class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(child: EmptyState(icon: Icons.info_outline_rounded, message: message)),
      );
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({required this.initial, required this.initialType, this.draft, this.walletId});

  final FinanceTransaction? initial;
  final TransactionType initialType;
  final TransactionDraft? draft;
  final String? walletId;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _source;
  late final TextEditingController _notes;
  late TransactionType _type;
  late DateTime _occurredAt;
  String? _categoryId;
  String? _paymentMethodId;
  String _project = '';
  String? _walletId;
  // False until a wallet is known: then a new entry follows the main wallet.
  bool _walletChosen = false;
  bool _saving = false;
  // Category of the previous new entry: the next one starts with it.
  String? _lastExpense;
  String? _lastIncome;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.initial;
    final draft = widget.draft;
    _amount = TextEditingController(text: (tx?.amount ?? draft?.amount)?.toDecimalString() ?? '');
    _description = TextEditingController(text: tx?.description ?? draft?.description ?? '');
    _source = TextEditingController(text: tx?.source ?? '');
    _notes = TextEditingController(text: tx?.notes ?? '');
    _type = widget.initialType;
    _occurredAt = tx?.occurredAt ?? draft?.occurredAt ?? DateTime.now();
    _categoryId = tx?.categoryId;
    _paymentMethodId = tx?.paymentMethodId;
    _project = tx?.project ?? '';
    // New entries go to the wallet they were opened from ('' = Personal),
    // else to the main wallet (resolved in build, it may still be loading).
    final opened = widget.walletId;
    if (tx != null || opened != null) {
      _walletId = tx != null ? tx.walletId : (opened!.isEmpty ? null : opened);
      _walletChosen = true;
    }
    if (tx == null) _loadLastCategories();
  }

  Future<void> _loadLastCategories() async {
    final repo = ref.read(settingsRepositoryProvider);
    final expense = await repo.read(SettingKeys.lastExpenseCategory);
    final income = await repo.read(SettingKeys.lastIncomeCategory);
    if (!mounted) return;
    setState(() {
      _lastExpense = expense;
      _lastIncome = income;
      _categoryId ??= _type == TransactionType.income ? income : expense;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _source.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Currency currency = widget.initial?.amount.currency ?? ref.watch(currencyProvider);
    if (!_walletChosen) _walletId = ref.watch(mainWalletIdProvider);
    final categories = (ref.watch(categoriesProvider).value ?? const <FinanceCategory>[])
        .where((c) => c.appliesTo(_type))
        .toList();
    // Keep an archived category visible when editing an old transaction.
    final current = ref.watch(categoryByIdProvider)[_categoryId];
    if (current != null && !categories.any((c) => c.id == current.id)) categories.add(current);
    final methods = [...?ref.watch(paymentMethodsProvider).value];
    // Keep an archived payment method visible when editing an old record.
    final currentMethod = ref.watch(paymentMethodByIdProvider)[_paymentMethodId];
    if (currentMethod != null && !methods.any((m) => m.id == currentMethod.id)) methods.add(currentMethod);
    final isIncome = _type == TransactionType.income;
    // Only expense/income are created here; savings moves are made from the
    // savings goals screen, so their amount and links stay consistent.
    final editableType = _type == TransactionType.expense || isIncome;
    final isSavingsMove = _type == TransactionType.savings || _type == TransactionType.savingsWithdrawal;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? context.tr('Edit transaction') : context.tr('New transaction')),
        actions: [
          if (!_isEditing) ScanReceiptButton(walletId: _walletId ?? ''),
          if (_isEditing)
            IconButton(
              tooltip: context.tr('Delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.medium),
            // Not a lazy ListView: every field must stay built for validate().
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editableType)
                  SegmentedButton<TransactionType>(
                    segments: [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text(context.tr('Expense')),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text(context.tr('Income')),
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      final current = ref.read(categoryByIdProvider)[_categoryId];
                      if (current != null && !current.appliesTo(_type)) _categoryId = null;
                      if (!_isEditing) _categoryId ??= _type == TransactionType.income ? _lastIncome : _lastExpense;
                    }),
                  ),
                if (!_isEditing && editableType) _walletPicker(),
                if (widget.initial?.recurringItemId case final recurringId?)
                  _RecurringOrigin(recurringItemId: recurringId),
                const SizedBox(height: 16),
                MoneyFormField(
                  controller: _amount,
                  currency: currency,
                  autofocus: !_isEditing,
                  large: true,
                  enabled: !isSavingsMove,
                  // Confirm key on the keyboard saves: Expense button + amount + confirm.
                  onSubmitted: (_) {
                    if (!_saving) _save(currency);
                  },
                ),
                if (!isSavingsMove) ...[
                  const SizedBox(height: 16),
                  Text(context.tr('Category'), style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  // One tap per category instead of a dropdown; tap again to clear.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in categories)
                        ChoiceChip(
                          avatar: Icon(iconForKey(c.iconKey), size: 20, color: Color(c.color)),
                          label: Text(c.label(context)),
                          selected: c.id == _categoryId,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (on) => setState(() => _categoryId = on ? c.id : null),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: isIncome ? context.tr('Description (optional)') : context.tr('Description'),
                    hintText: isIncome ? context.tr('e.g. September salary') : context.tr('e.g. Groceries'),
                  ),
                ),
                if (isIncome) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _source,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: context.tr('Source (optional)'), hintText: context.tr('e.g. Employer')),
                  ),
                ],
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    // Rarely needed: payment method, date, project, notes.
                    initiallyExpanded: _isEditing || widget.draft != null,
                    maintainState: true,
                    title: Text(context.tr('More details')),
                    children: [
                      if (!isSavingsMove) ...[
                        DropdownButtonFormField<String?>(
                          key: ValueKey('methods-${methods.length}'),
                          initialValue: methods.any((m) => m.id == _paymentMethodId) ? _paymentMethodId : null,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: context.tr('Payment method')),
                          items: [
                            DropdownMenuItem(value: null, child: Text(context.tr('Not specified'))),
                            for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.label(context))),
                          ],
                          onChanged: (id) => setState(() => _paymentMethodId = id),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: Text(DateFormat.yMMMEd(context.lang).add_jm().format(_occurredAt)),
                        subtitle: Text(context.tr('Date & time')),
                        trailing: const Icon(Icons.edit_calendar_rounded),
                        onTap: _pickDateTime,
                      ),
                      const SizedBox(height: 8),
                      Autocomplete<String>(
                        initialValue: TextEditingValue(text: _project),
                        optionsBuilder: (value) {
                          final q = value.text.trim().toLowerCase();
                          return ref
                              .read(projectsProvider)
                              .where((p) => p.toLowerCase().contains(q) && p != value.text);
                        },
                        onSelected: (p) => _project = p,
                        fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          maxLength: 60,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: context.tr('Project or client (optional)'),
                            helperText: context.tr('Leave it empty for personal spending.'),
                            prefixIcon: const Icon(Icons.work_outline_rounded),
                          ),
                          onChanged: (v) => _project = v,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notes,
                        maxLength: 1000,
                        minLines: 2,
                        maxLines: 5,
                        decoration: InputDecoration(labelText: context.tr('Notes (optional)')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(currency),
                  icon: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isEditing ? context.tr('Save changes') : context.tr('Save')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Personal or one of the shared wallets (only when there are wallets).
  Widget _walletPicker() {
    final wallets = ref.watch(walletsProvider).value ?? const <Wallet>[];
    if (wallets.isEmpty) return const SizedBox.shrink();
    Widget chip(String? id, IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            selected: _walletId == id,
            onSelected: (_) => setState(() {
              _walletId = id;
              _walletChosen = true;
            }),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(null, Icons.person_rounded, context.tr('Personal')),
            for (final w in wallets) chip(w.id, walletIcon(w.kind), w.name),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_occurredAt);
    setState(() => _occurredAt = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  String? _optional(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save(Currency currency) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(_amount.text, currency);
    if (amount == null || !amount.isPositive) return;
    final isIncome = _type == TransactionType.income;
    final tx = FinanceTransaction(
      id: widget.initial?.id ?? newId(),
      type: _type,
      amount: amount,
      occurredAt: _occurredAt,
      description: _description.text.trim(),
      categoryId: ref.read(categoryByIdProvider)[_categoryId]?.appliesTo(_type) == true ? _categoryId : null,
      paymentMethodId: _paymentMethodId,
      recurringItemId: widget.initial?.recurringItemId,
      savingsGoalId: widget.initial?.savingsGoalId,
      source: isIncome ? _optional(_source) : null,
      notes: _optional(_notes),
      project: _project.trim().isEmpty ? null : _project.trim(),
      walletId: _walletId,
      createdBy: widget.initial?.createdBy ?? (_walletId == null ? null : currentUid),
    );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final savedText = _isEditing ? context.tr('Changes saved') : context.tr('Transaction added');
    final failedText = context.tr('Could not save. Please check the values.');
    final burstText = isIncome
        ? context.tr('Income saved: {amount}', {'amount': amount.format()})
        : context.tr('Expense saved: {amount}', {'amount': amount.format()});
    final overlay = Overlay.of(context, rootOverlay: true);
    final finance = FinanceColors.of(context);
    try {
      await ref.read(transactionActionsProvider).save(tx);
      if (!mounted) return;
      if (!_isEditing) {
        final used = tx.categoryId;
        if (used != null) {
          ref
              .read(settingsRepositoryProvider)
              .write(isIncome ? SettingKeys.lastIncomeCategory : SettingKeys.lastExpenseCategory, used)
              .ignore();
        }
        ref.read(usageTrackerProvider).track(
              _walletId != null ? 'wallet_entry' : (isIncome ? 'income_added' : 'expense_added'),
            );
      }
      context.pop();
      if (_isEditing) {
        messenger.showSnackBar(SnackBar(content: Text(savedText)));
      } else {
        showSuccessBurst(
          overlay,
          message: burstText,
          icon: isIncome ? Icons.south_west_rounded : Icons.check_rounded,
          color: isIncome ? finance.income : Brand.mint,
        );
      }
    } on Object {
      // Details are not shown: they could contain user data.
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
    }
  }

  Future<void> _delete() async {
    final tx = widget.initial!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete transaction?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Delete'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final actions = ref.read(transactionActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final blocked = context.tr('This deposit was already partly withdrawn. Delete the withdrawals first.');
    try {
      await actions.delete(tx.id);
    } on SavingsGoalWouldBeNegative {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    if (!mounted) return;
    context.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(context.tr('Transaction deleted')),
      action: SnackBarAction(label: context.tr('Undo'), onPressed: () => actions.restore(tx)),
    ));
  }
}

/// Shows which subscription / recurring expense generated this transaction.
class _RecurringOrigin extends ConsumerWidget {
  const _RecurringOrigin({required this.recurringItemId});

  final String recurringItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recurringItemsProvider).value ?? const <RecurringItem>[];
    final matches = items.where((i) => i.id == recurringItemId);
    final item = matches.isEmpty ? null : matches.first;
    final label = item == null
        ? context.tr('Recorded automatically from a recurring charge')
        : item.kind == RecurringKind.subscription
            ? context.tr('Subscription: {name}', {'name': item.name})
            : context.tr('Recurring expense: {name}', {'name': item.name});
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: EmptyState(icon: Icons.autorenew_rounded, message: label),
    );
  }
}
