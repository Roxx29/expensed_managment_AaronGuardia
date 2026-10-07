import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../../premium/application/premium_providers.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/budget_providers.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final report = ref.watch(budgetReportProvider);
    final monthNotifier = ref.read(budgetMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Budgets'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: context.tr('Previous month'),
                    onPressed: monthNotifier.previous,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM(context.lang).format(month.start),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Next month'),
                    onPressed: monthNotifier.next,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...report.when<List<Widget>>(
                skipLoadingOnReload: true,
                loading: () => const [Center(child: CircularProgressIndicator())],
                error: (_, _) => [
                  EmptyState(icon: Icons.error_outline_rounded, message: context.tr('Could not load budgets.')),
                ],
                data: (r) => [
                  _GlobalBudgetCard(report: r),
                  const SizedBox(height: 16),
                  _CategoryBudgetsCard(report: r),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('Changes apply from this month onwards. Earlier months keep their budgets.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Budget $250 · Spent $180 · Remaining $70" plus the progress bar.
class _BudgetFigures extends StatelessWidget {
  const _BudgetFigures({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final percent = p.ratio.isFinite ? '${(p.ratio * 100).round()}%' : '—';
    final remainingText = p.remaining.isNegative
        ? context.tr('Over by {amount}', {'amount': (-p.remaining).format()})
        : context.tr('Remaining {amount}', {'amount': p.remaining.format()});
    final statusColor = switch (p.status) {
      BudgetStatus.onTrack => null,
      BudgetStatus.nearLimit => FinanceColors.of(context).warning,
      BudgetStatus.overBudget => FinanceColors.of(context).expense,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetProgressBar(progress: p),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(context.tr('Budget {amount}', {'amount': p.budgeted.format()})),
            Text(context.tr('Spent {amount} ({percent})', {'amount': p.spent.format(), 'percent': percent})),
            Text(remainingText, style: TextStyle(fontWeight: FontWeight.w600, color: statusColor)),
          ],
        ),
      ],
    );
  }
}

class _GlobalBudgetCard extends ConsumerWidget {
  const _GlobalBudgetCard({required this.report});

  final MonthlyBudgetReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = report.global;
    final currency = ref.watch(currencyProvider);
    final actions = ref.read(budgetActionsProvider);

    Future<void> edit() async {
      final amount = await showMoneyDialog(
        context,
        title: context.tr('Monthly budget'),
        currency: currency,
        initial: global?.budgeted,
        message: context.tr('How much do you want to spend in total each month?'),
      );
      if (amount != null) await actions.setBudget(amount: amount);
    }

    return SectionCard(
      title: context.tr('Monthly budget'),
      trailing: global == null
          ? null
          : PopupMenuButton<String>(
              tooltip: context.tr('Options'),
              onSelected: (v) => v == 'edit' ? edit() : _removeWithUndo(context, actions, null, global.budgeted),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(context.tr('Change amount'))),
                PopupMenuItem(value: 'remove', child: Text(context.tr('Remove'))),
              ],
            ),
      child: global == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EmptyState(
                  icon: Icons.savings_outlined,
                  message: context.tr('Set a spending limit for the whole month.'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(onPressed: edit, child: Text(context.tr('Set monthly budget'))),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BudgetFigures(progress: global),
                if (report.unallocated case final Money unallocated) ...[
                  const Divider(height: 24),
                  Text(
                    unallocated.isNegative
                        ? context.tr('Category budgets exceed the monthly budget by {amount}.', {'amount': (-unallocated).format()})
                        : context.tr('Allocated to categories: {allocated} · Unallocated: {unallocated}', {
                            'allocated': (report.allocated ?? Money.zero(currency)).format(),
                            'unallocated': unallocated.format(),
                          }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
    );
  }
}

class _CategoryBudgetsCard extends ConsumerWidget {
  const _CategoryBudgetsCard({required this.report});

  final MonthlyBudgetReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider);
    final currency = ref.watch(currencyProvider);
    final actions = ref.read(budgetActionsProvider);
    final entries = report.byCategory.entries.toList()
      ..sort((a, b) => b.value.ratio.compareTo(a.value.ratio));

    Future<void> edit(FinanceCategory category, Money? current) async {
      final amount = await showMoneyDialog(
        context,
        title: context.tr('{name} budget', {'name': category.label(context)}),
        currency: currency,
        initial: current,
      );
      if (amount != null) await actions.setBudget(categoryId: category.id, amount: amount);
    }

    Future<void> add() async {
      if (!withinFreeLimit(context, ref, report.byCategory.length, FreeLimits.categoryBudgets)) return;
      final available = categories.values
          .where((c) => !c.archived && c.appliesTo(TransactionType.expense) && !report.byCategory.containsKey(c.id))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final picked = await showModalBottomSheet<FinanceCategory>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in available)
                ListTile(
                  leading: Icon(iconForKey(c.iconKey), color: Color(c.color)),
                  title: Text(c.label(context)),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      );
      if (picked != null && context.mounted) await edit(picked, null);
    }

    return SectionCard(
      title: context.tr('Category budgets'),
      trailing: TextButton.icon(onPressed: add, icon: const Icon(Icons.add_rounded), label: Text(context.tr('Add'))),
      child: entries.isEmpty
          ? EmptyState(
              icon: Icons.donut_small_outlined,
              message: context.tr('Allocate money to categories like Food or Gas to track them separately.'),
            )
          : Column(
              children: [
                for (final e in entries)
                  if (categories[e.key] case final category?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(iconForKey(category.iconKey), color: Color(category.color), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(category.label(context), style: Theme.of(context).textTheme.titleSmall),
                              ),
                              PopupMenuButton<String>(
                                tooltip: context.tr('Options'),
                                onSelected: (v) => v == 'edit'
                                    ? edit(category, e.value.budgeted)
                                    : _removeWithUndo(context, actions, category.id, e.value.budgeted),
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'edit', child: Text(context.tr('Change amount'))),
                                  PopupMenuItem(value: 'remove', child: Text(context.tr('Remove'))),
                                ],
                              ),
                            ],
                          ),
                          _BudgetFigures(progress: e.value),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Removes a budget and offers "Undo" (sets the same amount again).
Future<void> _removeWithUndo(BuildContext context, BudgetActions actions, String? categoryId, Money amount) async {
  final messenger = ScaffoldMessenger.of(context);
  final removed = context.tr('Budget removed');
  final undo = context.tr('Undo');
  await actions.removeBudget(categoryId: categoryId);
  messenger.showSnackBar(SnackBar(
    content: Text(removed),
    action: SnackBarAction(label: undo, onPressed: () => actions.setBudget(categoryId: categoryId, amount: amount)),
  ));
}
