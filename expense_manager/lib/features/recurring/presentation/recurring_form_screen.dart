import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/time/year_month.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/recurrence.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../application/recurring_providers.dart';

/// Create (no [itemId]) or edit a subscription / recurring expense.
class RecurringFormScreen extends ConsumerWidget {
  const RecurringFormScreen({super.key, this.itemId, this.kind = RecurringKind.bill});

  final String? itemId;
  final RecurringKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = itemId;
    if (id == null) return _RecurringForm(initial: null, kind: kind);
    return ref.watch(recurringItemsProvider).when(
          data: (items) {
            final matches = items.where((i) => i.id == id);
            final item = matches.isEmpty ? null : matches.first;
            return item == null
                ? Scaffold(
                    appBar: AppBar(),
                    body: Center(
                      child: EmptyState(icon: Icons.info_outline_rounded, message: context.tr('This item no longer exists.')),
                    ),
                  )
                : _RecurringForm(initial: item, kind: item.kind);
          },
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('Could not load.')))),
        );
  }
}

class _RecurringForm extends ConsumerStatefulWidget {
  const _RecurringForm({required this.initial, required this.kind});

  final RecurringItem? initial;
  final RecurringKind kind;

  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  static const _maxInterval = 366;

  final _formKey = GlobalKey<FormState>();
  late final RecurringItem? _initial = widget.initial;
  late final _name = TextEditingController(text: _initial?.name ?? '');
  late final _amount = TextEditingController(text: _initial?.amount.toDecimalString() ?? '');
  late final _interval = TextEditingController(text: '${_initial?.rule.interval ?? 1}');
  late final _notes = TextEditingController(text: _initial?.notes ?? '');
  late Frequency _frequency = _initial?.rule.frequency ?? Frequency.monthly;
  late DateTime _anchorDate = _initial?.anchorDate ?? dateOnly(DateTime.now());
  late DateTime? _endDate = _initial?.endDate;
  late String? _categoryId = _initial?.categoryId ??
      (widget.kind == RecurringKind.subscription ? 'cat_subscriptions' : null);
  late String? _paymentMethodId = _initial?.paymentMethodId;
  late bool _isActive = _initial?.isActive ?? true;
  bool _saving = false;

  bool get _isSubscription => widget.kind == RecurringKind.subscription;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _interval.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Currency currency = _initial?.amount.currency ?? ref.watch(currencyProvider);
    final byId = ref.watch(categoryByIdProvider);
    final categories = (ref.watch(categoriesProvider).value ?? const <FinanceCategory>[])
        .where((c) => c.appliesTo(TransactionType.expense))
        .toList();
    final current = byId[_categoryId];
    if (current != null && !categories.any((c) => c.id == current.id)) categories.add(current);
    final methods = [...?ref.watch(paymentMethodsProvider).value];
    // Keep an archived payment method visible when editing an old record.
    final currentMethod = ref.watch(paymentMethodByIdProvider)[_paymentMethodId];
    if (currentMethod != null && !methods.any((m) => m.id == currentMethod.id)) methods.add(currentMethod);
    final dateFormat = DateFormat.yMMMd(context.lang);
    final String title;
    if (_isSubscription) {
      title = _initial == null ? context.tr('New subscription') : context.tr('Edit subscription');
    } else {
      title = _initial == null ? context.tr('New recurring expense') : context.tr('Edit recurring expense');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_initial != null)
            IconButton(tooltip: context.tr('Delete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
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
                TextFormField(
                  controller: _name,
                  autofocus: _initial == null,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('Name'),
                    hintText: _isSubscription ? context.tr('e.g. Netflix') : context.tr('e.g. Rent'),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? context.tr('Enter a name') : null,
                ),
                const SizedBox(height: 8),
                MoneyFormField(controller: _amount, currency: currency),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: TextFormField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: context.tr('Every')),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > _maxInterval ? '1–$_maxInterval' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<Frequency>(
                        initialValue: _frequency,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: context.tr('Frequency')),
                        items: [
                          DropdownMenuItem(value: Frequency.daily, child: Text(context.tr('Day(s)'))),
                          DropdownMenuItem(value: Frequency.weekly, child: Text(context.tr('Week(s)'))),
                          DropdownMenuItem(value: Frequency.monthly, child: Text(context.tr('Month(s)'))),
                          DropdownMenuItem(value: Frequency.yearly, child: Text(context.tr('Year(s)'))),
                        ],
                        onChanged: (f) => setState(() => _frequency = f ?? _frequency),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(dateFormat.format(_anchorDate)),
                  subtitle: Text(
                    _initial == null
                        ? context.tr('First charge — past dates are recorded as expenses (up to one year)')
                        : context.tr('Billing date'),
                  ),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final picked = await _pickDate(_anchorDate);
                    if (picked != null && mounted) setState(() => _anchorDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy_rounded),
                  title: Text(_endDate == null ? context.tr('No end date') : dateFormat.format(_endDate!)),
                  subtitle: Text(context.tr('Ends (optional)')),
                  trailing: _endDate == null
                      ? const Icon(Icons.edit_calendar_rounded)
                      : IconButton(
                          tooltip: context.tr('Remove end date'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _endDate = null),
                        ),
                  onTap: () async {
                    final picked = await _pickDate(_endDate ?? _anchorDate);
                    if (picked != null && mounted) setState(() => _endDate = picked);
                  },
                ),
                if (_endDate != null && _endDate!.isBefore(_anchorDate))
                  Text(
                    context.tr('The end date must be after the first charge.'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: ValueKey('category-${categories.length}'),
                  initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('Category')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(context.tr('Uncategorized'))),
                    for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.label(context))),
                  ],
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Active')),
                  subtitle: Text(context.tr('Paused items are not charged')),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notes,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: context.tr('Notes (optional)')),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(currency),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(context.tr('Save')),
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

  Future<DateTime?> _pickDate(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
  }

  Future<void> _save(Currency currency) async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate != null && _endDate!.isBefore(_anchorDate)) return;
    final amount = Money.tryParse(_amount.text, currency);
    final interval = int.tryParse(_interval.text);
    if (amount == null || !amount.isPositive || interval == null || interval < 1) return;
    final notes = _notes.text.trim();
    final item = RecurringItem(
      id: _initial?.id ?? newId(),
      kind: widget.kind,
      name: _name.text.trim(),
      amount: amount,
      rule: RecurrenceRule(_frequency, interval: interval),
      anchorDate: _anchorDate,
      endDate: _endDate,
      postedFrom: _initial?.postedFrom,
      categoryId: _categoryId,
      paymentMethodId: _paymentMethodId,
      isActive: _isActive,
      notes: notes.isEmpty ? null : notes,
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.tr('Could not save. Please check the values.');
    try {
      await ref.read(recurringActionsProvider).save(item);
      if (mounted) context.pop();
    } on Object {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(errorText)));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete?')),
        content: Text(context.tr('Future charges stop. Expenses already recorded are kept.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Delete'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(recurringActionsProvider).delete(_initial!.id);
    if (mounted) context.pop();
  }
}
