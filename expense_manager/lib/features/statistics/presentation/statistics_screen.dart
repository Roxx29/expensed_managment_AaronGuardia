import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/statistics_calculator.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/statistics_providers.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(statisticsProvider);
    final year = ref.watch(statisticsYearProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Statistics')),
        actions: [
          if (view.value case final v?)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButton<int>(
                value: year,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: [for (final y in v.years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (y) {
                  if (y != null) ref.read(statisticsYearProvider.notifier).select(y);
                },
              ),
            ),
        ],
      ),
      body: view.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: EmptyState(icon: Icons.error_outline_rounded, message: context.tr('Could not load statistics.')),
        ),
        data: (v) => _StatisticsBody(view: v),
      ),
    );
  }
}

class _StatisticsBody extends ConsumerWidget {
  const _StatisticsBody({required this.view});

  final StatisticsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = view.year;
    final month = ref.watch(statisticsMonthProvider);
    final categories = ref.watch(categoryByIdProvider);
    final monthName = DateFormat.MMMM(context.lang);
    final monthShort = DateFormat.MMMMd(context.lang);

    final primary = <Widget>[
      _SummaryTiles(stats: stats),
      SectionCard(
        title: context.tr('Monthly spending {year}', {'year': stats.year}),
        child: MoneyBarChart(
          values: stats.monthlyExpenses,
          labels: [for (var m = 1; m <= 12; m++) monthName.format(DateTime(2000, m)).substring(0, 1)],
          readoutLabels: [for (var m = 1; m <= 12; m++) monthName.format(DateTime(stats.year, m))],
          selectedIndex: month - 1,
          onSelected: (i) => ref.read(statisticsMonthProvider.notifier).select(i + 1),
        ),
      ),
      if (ref.watch(statisticsComparisonProvider) case final comparison?)
        _MonthComparisonCard(comparison: comparison, categories: categories),
    ];

    final highestCategory = stats.highestCategory;
    final selectedYearIndex = view.history.keys.toList().indexOf(stats.year);
    final secondary = <Widget>[
      SectionCard(
        title: context.tr('Highlights {year}', {'year': stats.year}),
        child: stats.highestDay == null
            ? EmptyState(icon: Icons.insights_outlined, message: context.tr('No expenses recorded this year.'))
            : Column(
                children: [
                  _Highlight(
                    icon: iconForKey(categories[highestCategory?.categoryId]?.iconKey ?? ''),
                    label: context.tr('Top category'),
                    value: '${categories[highestCategory?.categoryId]?.label(context) ?? context.tr('Uncategorized')} · '
                        '${highestCategory!.amount.format()}',
                  ),
                  _Highlight(
                    icon: Icons.today_rounded,
                    label: context.tr('Highest-spending day'),
                    value: '${monthShort.format(stats.highestDay!.date)} · ${stats.highestDay!.amount.format()}',
                  ),
                  _Highlight(
                    icon: Icons.calendar_month_rounded,
                    label: context.tr('Highest-spending month'),
                    value: '${monthName.format(DateTime(stats.year, stats.highestMonth!))} · '
                        '${stats.monthlyExpenses[stats.highestMonth! - 1].format()}',
                  ),
                ],
              ),
      ),
      SectionCard(
        title: context.tr('Spending by category {year}', {'year': stats.year}),
        child: stats.expensesByCategory.isEmpty
            ? EmptyState(icon: Icons.pie_chart_outline_rounded, message: context.tr('No expenses recorded this year.'))
            : Column(
                children: [
                  for (final c in stats.expensesByCategory)
                    CategoryAmountRow(
                      category: categories[c.categoryId],
                      amount: c.amount,
                      share: c.amount.ratioOf(stats.totalExpenses),
                      note: '${(c.amount.ratioOf(stats.totalExpenses) * 100).round()}%',
                    ),
                ],
              ),
      ),
      SectionCard(
        title: context.tr('Spending by year'),
        child: view.history.length < 2
            ? EmptyState(
                icon: Icons.history_rounded,
                message: context.tr('Your yearly history appears here once you have more than one year of data.'),
              )
            : MoneyBarChart(
                values: view.history.values.toList(),
                labels: [for (final y in view.history.keys) '$y'],
                selectedIndex: selectedYearIndex < 0 ? null : selectedYearIndex,
                onSelected: (i) =>
                    ref.read(statisticsYearProvider.notifier).select(view.history.keys.elementAt(i)),
                height: 140,
              ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= Breakpoints.expanded;
        const gap = SizedBox(height: 16, width: 16);
        Widget column(List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final c in children) ...[c, gap]],
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Expanded(child: column(primary)), gap, Expanded(child: column(secondary))],
                    )
                  : column([...primary, ...secondary]),
            ),
          ),
        );
      },
    );
  }
}

/// Headline numbers for the year.
class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.stats});

  final YearStatistics stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            tile(context.tr('Spent in {year}', {'year': stats.year}), stats.totalExpenses.format()),
            tile(context.tr('Monthly average'), stats.monthlyAverage.format()),
            tile(context.tr('Income in {year}', {'year': stats.year}), stats.totalIncome.format()),
          ],
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(value),
        subtitle: Text(label),
      );
}

class _MonthComparisonCard extends StatelessWidget {
  const _MonthComparisonCard({required this.comparison, required this.categories});

  final MonthComparison comparison;
  final Map<String, FinanceCategory> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = FinanceColors.of(context);
    final current = comparison.current;
    final monthName = DateFormat.yMMMM(context.lang).format(current.month.start);
    final previousName = DateFormat.MMMM(context.lang).format(comparison.previous.month.start);
    final change = comparison.expenseChangePercent;

    String categoryNote(String? categoryId, Money amount) {
      final before = comparison.previousFor(categoryId);
      if (!before.isPositive) return context.tr('new');
      final pct = divideRounded((amount - before).minor * 100, before.minor);
      return pct == 0 ? context.tr('same') : '${pct > 0 ? '▲' : '▼'} ${pct.abs()}%';
    }

    return SectionCard(
      title: monthName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.tr('Spent {amount}', {'amount': current.expenses.format()}),
                style: theme.textTheme.titleMedium,
              ),
              if (change != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Up = more spending = expense color; icon + text, never color alone.
                    Icon(
                      change > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 18,
                      color: change > 0 ? finance.expense : finance.income,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        change > 0
                            ? context.tr('{pct}% more than {month}', {'pct': change.abs(), 'month': previousName})
                            : context.tr('{pct}% less than {month}', {'pct': change.abs(), 'month': previousName}),
                      ),
                    ),
                  ],
                )
              else
                Text(context.tr('No expenses in {month} to compare', {'month': previousName}), style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('Income {income} · Left {left}', {'income': current.income.format(), 'left': current.net.format()}),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (current.expensesByCategory.isEmpty)
            EmptyState(icon: Icons.receipt_long_outlined, message: context.tr('No expenses this month.'))
          else
            for (final c in current.expensesByCategory)
              CategoryAmountRow(
                category: categories[c.categoryId],
                amount: c.amount,
                share: c.amount.ratioOf(current.expenses),
                note: categoryNote(c.categoryId, c.amount),
              ),
        ],
      ),
    );
  }
}
