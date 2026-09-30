import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../application/budget_providers.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final report = ref.watch(budgetReportProvider);
    final monthNotifier = ref.read(budgetMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
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
                    tooltip: 'Previous month',
                    onPressed: monthNotifier.previous,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM().format(month.start),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: monthNotifier.next,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...report.when<List<Widget>>(
                skipLoadingOnReload: true,
                loading: () => const [Center(child: CircularProgressIndicator())],
                error: (_, _) => const [
                  EmptyState(icon: Icons.error_outline_rounded, message: 'Could not load budgets.'),
                ],
                data: (r) => [
                  _GlobalBudgetCard(report: r),
                  const SizedBox(height: 16),
                  _CategoryBudgetsCard(report: r),
                  const SizedBox(height: 12),
                  Text(
                    'Changes apply from this month onwards. Earlier months keep their budgets.',
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
        ? 'Over by ${(-p.remaining).format()}'
        : 'Remaining ${p.remaining.format()}';
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
            Text('Budget ${p.budgeted.format()}'),
            Text('Spent ${p.spent.format()} ($percent)'),
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
        title: 'Monthly budget',
        currency: currency,
        initial: global?.budgeted,
        message: 'How much do you want to spend in total each month?',
      );
      if (amount != null) await actions.setBudget(amount: amount);
    }

    return SectionCard(
      title: 'Monthly budget',
      trailing: global == null
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (v) => v == 'edit' ? edit() : actions.removeBudget(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Change amount')),
                PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
      child: global == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EmptyState(
                  icon: Icons.savings_outlined,
                  message: 'Set a spending limit for the whole month.',
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(onPressed: edit, child: const Text('Set monthly budget')),
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
                        ? 'Category budgets exceed the monthly budget by ${(-unallocated).format()}.'
                        : 'Allocated to categories: ${(report.allocated ?? Money.zero(currency)).format()} · '
                            'Unallocated: ${unallocated.format()}',
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
        title: '${category.name} budget',
        currency: currency,
        initial: current,
      );
      if (amount != null) await actions.setBudget(categoryId: category.id, amount: amount);
    }

    Future<void> add() async {
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
                  title: Text(c.name),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      );
      if (picked != null && context.mounted) await edit(picked, null);
    }

    return SectionCard(
      title: 'Category budgets',
      trailing: TextButton.icon(onPressed: add, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
      child: entries.isEmpty
          ? const EmptyState(
              icon: Icons.donut_small_outlined,
              message: 'Allocate money to categories like Food or Gas to track them separately.',
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
                                child: Text(category.name, style: Theme.of(context).textTheme.titleSmall),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Options',
                                onSelected: (v) => v == 'edit'
                                    ? edit(category, e.value.budgeted)
                                    : actions.removeBudget(categoryId: category.id),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Change amount')),
                                  PopupMenuItem(value: 'remove', child: Text('Remove')),
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
