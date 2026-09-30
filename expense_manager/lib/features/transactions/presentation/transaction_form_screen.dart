import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../application/transaction_providers.dart';

/// Create (no [transactionId]) or edit an expense/income.
class TransactionFormScreen extends ConsumerWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.initialType = TransactionType.expense,
  });

  final String? transactionId;
  final TransactionType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    if (id == null) return _TransactionForm(initial: null, initialType: initialType);

    return ref.watch(transactionByIdProvider(id)).when(
          data: (tx) => tx == null
              ? const _MessageScaffold('This transaction no longer exists.')
              : _TransactionForm(initial: tx, initialType: tx.type),
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const _MessageScaffold('Could not load this transaction.'),
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
  const _TransactionForm({required this.initial, required this.initialType});

  final FinanceTransaction? initial;
  final TransactionType initialType;

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
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.initial;
    _amount = TextEditingController(text: tx?.amount.toDecimalString() ?? '');
    _description = TextEditingController(text: tx?.description ?? '');
    _source = TextEditingController(text: tx?.source ?? '');
    _notes = TextEditingController(text: tx?.notes ?? '');
    _type = widget.initialType;
    _occurredAt = tx?.occurredAt ?? DateTime.now();
    _categoryId = tx?.categoryId;
    _paymentMethodId = tx?.paymentMethodId;
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
    final categories = (ref.watch(categoriesProvider).value ?? const <FinanceCategory>[])
        .where((c) => c.appliesTo(_type))
        .toList();
    // Keep an archived category visible when editing an old transaction.
    final current = ref.watch(categoryByIdProvider)[_categoryId];
    if (current != null && !categories.any((c) => c.id == current.id)) categories.add(current);
    final selectedCategory = categories.any((c) => c.id == _categoryId) ? _categoryId : null;
    final methods = [...?ref.watch(paymentMethodsProvider).value];
    // Keep an archived payment method visible when editing an old record.
    final currentMethod = ref.watch(paymentMethodByIdProvider)[_paymentMethodId];
    if (currentMethod != null && !methods.any((m) => m.id == currentMethod.id)) methods.add(currentMethod);
    final isIncome = _type == TransactionType.income;
    // Only expense/income are created here; transfers/savings come with Phase 5.
    final editableType = _type == TransactionType.expense || isIncome;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete',
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
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text('Expense'),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text('Income'),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      final current = ref.read(categoryByIdProvider)[_categoryId];
                      if (current != null && !current.appliesTo(_type)) _categoryId = null;
                    }),
                  ),
                if (widget.initial?.recurringItemId case final recurringId?)
                  _RecurringOrigin(recurringItemId: recurringId),
                const SizedBox(height: 16),
                MoneyFormField(
                  controller: _amount,
                  currency: currency,
                  autofocus: !_isEditing,
                  large: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: isIncome ? 'Description (optional)' : 'Description',
                    hintText: isIncome ? 'e.g. September salary' : 'e.g. Groceries',
                  ),
                ),
                if (isIncome) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _source,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Source (optional)', hintText: 'e.g. Employer'),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: ValueKey('category-$_type-${categories.length}'),
                  initialValue: selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(iconForKey(c.iconKey), size: 20, color: Color(c.color)),
                            const SizedBox(width: 12),
                            Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  key: ValueKey('methods-${methods.length}'),
                  initialValue: methods.any((m) => m.id == _paymentMethodId) ? _paymentMethodId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not specified')),
                    for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (id) => setState(() => _paymentMethodId = id),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(DateFormat.yMMMEd().add_jm().format(_occurredAt)),
                  subtitle: const Text('Date & time'),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: _pickDateTime,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notes,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(currency),
                  icon: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isEditing ? 'Save changes' : 'Save'),
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
      categoryId: _categoryId,
      paymentMethodId: _paymentMethodId,
      recurringItemId: widget.initial?.recurringItemId,
      savingsGoalId: widget.initial?.savingsGoalId,
      source: isIncome ? _optional(_source) : null,
      notes: _optional(_notes),
    );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(transactionActionsProvider).save(tx);
      if (!mounted) return;
      context.pop();
      messenger.showSnackBar(SnackBar(content: Text(_isEditing ? 'Changes saved' : 'Transaction added')));
    } on Object {
      // Details are not shown: they could contain user data.
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('Could not save. Please check the values.')));
    }
  }

  Future<void> _delete() async {
    final tx = widget.initial!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final actions = ref.read(transactionActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    await actions.delete(tx.id);
    if (!mounted) return;
    context.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Transaction deleted'),
      action: SnackBarAction(label: 'Undo', onPressed: () => actions.restore(tx)),
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
        ? 'Recorded automatically from a recurring charge'
        : item.kind == RecurringKind.subscription
            ? 'Subscription: ${item.name}'
            : 'Recurring expense: ${item.name}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: EmptyState(icon: Icons.autorenew_rounded, message: label),
    );
  }
}
