import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/savings_calculator.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../application/savings_providers.dart';

class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(savingsProgressProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Savings goals'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _editGoal(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('New goal')),
      ),
      body: progress.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: EmptyState(icon: Icons.error_outline_rounded, message: context.tr('Could not load data.')),
        ),
        data: (goals) {
          // Goals may use different currencies; amounts are never converted.
          final totals = <Currency, Money>{};
          for (final p in goals) {
            totals[p.saved.currency] = (totals[p.saved.currency] ?? Money.zero(p.saved.currency)) + p.saved;
          }
          final totalText = totals.isEmpty
              ? Money.zero(currency).format()
              : totals.values.map((m) => m.format()).join(' · ');

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 32,
                        runSpacing: 12,
                        children: [
                          _Figure(label: context.tr('Total saved'), value: totalText),
                          _Figure(label: context.tr('Goals'), value: '${goals.length}'),
                          _Figure(
                            label: context.tr('Reached'),
                            value: '${goals.where((p) => p.isReached).length}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (goals.isEmpty)
                    EmptyState(
                      icon: Icons.flag_rounded,
                      message: context.tr(
                        'No goals yet. Create one, like a trip or an emergency fund, and add money to it. Money in a goal is set aside from your available balance.',
                      ),
                    ),
                  for (final p in goals) _GoalCard(progress: p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.progress});

  final SavingsProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = FinanceColors.of(context);
    final dateFormat = DateFormat.yMMMd(context.lang);
    final targetDate = p.goal.targetDate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.goal.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
                if (p.isReached)
                  Chip(
                    avatar: Icon(Icons.check_circle_rounded, color: finance.income),
                    label: Text(context.tr('Reached')),
                    visualDensity: VisualDensity.compact,
                  ),
                PopupMenuButton<_GoalMenu>(
                  tooltip: context.tr('More options'),
                  onSelected: (choice) => switch (choice) {
                    _GoalMenu.edit => _editGoal(context, ref, p.goal),
                    _GoalMenu.archive => _archive(context, ref, p.goal),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: _GoalMenu.edit, child: Text(context.tr('Edit'))),
                    PopupMenuItem(value: _GoalMenu.archive, child: Text(context.tr('Archive'))),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('{saved} of {target}', {'saved': p.saved.format(), 'target': p.target.format()}),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    label: context.tr('Goal progress'),
                    value: '${(p.ratio * 100).round()}%',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: p.ratio,
                        minHeight: 10,
                        color: p.isReached ? finance.income : scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!p.isReached) Text(context.tr('Remaining: {amount}', {'amount': p.remaining.format()})),
                  if (targetDate != null)
                    Text(
                      context.tr('Target date: {date}', {'date': dateFormat.format(targetDate)}),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (p.suggestedMonthly case final monthly?)
                    Text(
                      context.tr('Save {amount}/month to reach it', {'amount': monthly.format()}),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (p.isOverdue)
                    Text(
                      context.tr('The target date has passed'),
                      style: theme.textTheme.bodySmall?.copyWith(color: finance.warning),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _deposit(context, ref, p),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(context.tr('Add money')),
                      ),
                      OutlinedButton.icon(
                        onPressed: p.saved.isPositive ? () => _withdraw(context, ref, p) : null,
                        icon: const Icon(Icons.remove_rounded),
                        label: Text(context.tr('Withdraw')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GoalMenu { edit, archive }

/// Runs [action] and reports the outcome in a snackbar.
Future<void> _run(BuildContext context, Future<void> Function() action, String success) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.tr('Could not save. Please check the values.');
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } on Object {
    // Details are not shown: they could contain user data.
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

Future<void> _editGoal(BuildContext context, WidgetRef ref, SavingsGoal? goal) async {
  final Currency currency = goal == null ? ref.read(currencyProvider) : goal.target.currency;
  final result = await showDialog<_GoalInput>(
    context: context,
    builder: (_) => _GoalDialog(goal: goal, currency: currency),
  );
  if (result == null || !context.mounted) return;
  await _run(
    context,
    () => ref.read(savingsActionsProvider).saveGoal(
          id: goal?.id,
          name: result.name,
          target: result.target,
          targetDate: result.targetDate,
        ),
    goal == null ? context.tr('Goal created') : context.tr('Changes saved'),
  );
}

Future<void> _archive(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Archive "{name}"?', {'name': goal.name})),
      content: Text(context.tr('Money in this goal stays set aside. Withdraw it first if you want it back in your balance.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Archive'))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _run(context, () => ref.read(savingsActionsProvider).archive(goal.id), context.tr('Goal archived'));
}

Future<void> _deposit(BuildContext context, WidgetRef ref, SavingsProgress p) async {
  final amount = await showMoneyDialog(
    context,
    title: context.tr('Add money to {name}', {'name': p.goal.name}),
    currency: p.target.currency,
    message: p.isReached ? null : context.tr('Remaining: {amount}', {'amount': p.remaining.format()}),
  );
  if (amount == null || !context.mounted) return;
  await _run(
    context,
    () => ref.read(savingsActionsProvider).deposit(p.goal.id, amount),
    context.tr('{amount} added to {name}', {'amount': amount.format(), 'name': p.goal.name}),
  );
}

Future<void> _withdraw(BuildContext context, WidgetRef ref, SavingsProgress p) async {
  final amount = await showMoneyDialog(
    context,
    title: context.tr('Withdraw from {name}', {'name': p.goal.name}),
    currency: p.target.currency,
    message: context.tr('Available in this goal: {amount}', {'amount': p.saved.format()}),
  );
  if (amount == null || !context.mounted) return;
  if (amount > p.saved) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('You can withdraw up to {amount}.', {'amount': p.saved.format()})),
    ));
    return;
  }
  await _run(
    context,
    () => ref.read(savingsActionsProvider).withdraw(p.goal.id, amount),
    context.tr('{amount} withdrawn from {name}', {'amount': amount.format(), 'name': p.goal.name}),
  );
}

typedef _GoalInput = ({String name, Money target, DateTime? targetDate});

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.goal, required this.currency});

  final SavingsGoal? goal;
  final Currency currency;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(text: widget.goal?.target.toDecimalString() ?? '');
  late DateTime? _targetDate = widget.goal?.targetDate;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _targetDate;
    final date = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(today) ? current : today,
      firstDate: today,
      lastDate: DateTime(today.year + 50, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() => _targetDate = date);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final target = Money.tryParse(_target.text, widget.currency);
    if (target == null || !target.isPositive) return;
    Navigator.pop<_GoalInput>(context, (name: _name.text.trim(), target: target, targetDate: _targetDate));
  }

  @override
  Widget build(BuildContext context) {
    final date = _targetDate;
    return AlertDialog(
      title: Text(widget.goal == null ? context.tr('New goal') : context.tr('Edit goal')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: widget.goal == null,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: context.tr('Name'), hintText: context.tr('e.g. Trip to Japan')),
                validator: (text) => (text ?? '').trim().isEmpty ? context.tr('Enter a name') : null,
              ),
              const SizedBox(height: 8),
              MoneyFormField(controller: _target, currency: widget.currency, label: context.tr('Target amount')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text(date == null ? context.tr('No target date') : DateFormat.yMMMd(context.lang).format(date)),
                subtitle: Text(context.tr('Target date (optional)')),
                onTap: _pickDate,
                trailing: date == null
                    ? const Icon(Icons.edit_calendar_rounded)
                    : IconButton(
                        tooltip: context.tr('Remove date'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _targetDate = null),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSecondaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
