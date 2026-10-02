import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/dashboard.dart';
import '../../../domain/insights/insights.dart';
import '../../../shared/providers/providers.dart';
import '../../../app/routes.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/transaction_tile.dart';
import '../application/dashboard_providers.dart';
import 'insight_text.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Overview'))),
      body: snapshot.when(
        // Keep showing the previous snapshot while data changes recompute it.
        skipLoadingOnReload: true,
        data: (data) => _DashboardBody(data: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              message: context.tr('Could not load your data. Please restart the app.'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final primary = <Widget>[
      _BalanceCard(data: data),
      _BudgetCard(data: data),
      if (data.insights.isNotEmpty) _AlertsCard(insights: data.insights),
    ];
    final secondary = <Widget>[
      _TopCategoriesCard(data: data),
      _UpcomingCard(charges: data.upcomingCharges),
      const _RecentTransactionsCard(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= Breakpoints.expanded;
        const gap = SizedBox(height: 16, width: 16);
        Widget column(List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children) ...[child, gap],
              ],
            );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: column(primary)),
                        gap,
                        Expanded(child: column(secondary)),
                      ],
                    )
                  : column([...primary, ...secondary]),
            ),
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = FinanceColors.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Available money'),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                data.availableBalance.format(),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Metric(label: context.tr('Income this month'), value: data.summary.income, color: finance.income),
                _Metric(label: context.tr('Expenses this month'), value: data.summary.expenses, color: finance.expense),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final Money value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
        Text(value.format(), style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final global = data.budgets.global;
    return SectionCard(
      title: context.tr('Monthly budget'),
      child: global == null
          ? EmptyState(
              icon: Icons.savings_outlined,
              message: context.tr('No monthly budget yet. Set one in Budgets to track your spending.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BudgetProgressBar(progress: global),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(context.tr('Spent {spent} of {budgeted}', {'spent': global.spent.format(), 'budgeted': global.budgeted.format()})),
                    Text(
                      global.remaining.isNegative
                          ? context.tr('Over by {amount}', {'amount': (-global.remaining).format()})
                          : context.tr('{amount} left', {'amount': global.remaining.format()}),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard({required this.insights});

  final List<Insight> insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider);
    final finance = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: context.tr('Alerts & tips'),
      child: Column(
        children: [
          for (final insight in insights)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (insight.severity) {
                  InsightSeverity.critical => Icons.error_rounded,
                  InsightSeverity.warning => Icons.warning_amber_rounded,
                  InsightSeverity.info => Icons.lightbulb_outline_rounded,
                },
                color: switch (insight.severity) {
                  InsightSeverity.critical => finance.expense,
                  InsightSeverity.warning => finance.warning,
                  InsightSeverity.info => scheme.primary,
                },
              ),
              title: Text(insightMessage(context, insight, categories)),
            ),
        ],
      ),
    );
  }
}

class _TopCategoriesCard extends ConsumerWidget {
  const _TopCategoriesCard({required this.data});

  final DashboardSnapshot data;

  static const _maxItems = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider);
    final items = data.summary.expensesByCategory.take(_maxItems).toList();
    final total = data.summary.expenses;
    return SectionCard(
      title: context.tr('Top spending categories'),
      child: items.isEmpty
          ? EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              message: context.tr('No expenses this month yet.'),
            )
          : Column(
              children: [
                for (final item in items)
                  CategoryAmountRow(
                    category: categories[item.categoryId],
                    amount: item.amount,
                    share: item.amount.ratioOf(total),
                  ),
              ],
            ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.charges});

  final List<UpcomingCharge> charges;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.MMMd(context.lang);
    return SectionCard(
      title: context.tr('Upcoming payments'),
      child: charges.isEmpty
          ? EmptyState(
              icon: Icons.event_available_rounded,
              message: context.tr('No subscriptions or bills due in the next 30 days.'),
            )
          : Column(
              children: [
                for (final charge in charges)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      charge.item.kind == RecurringKind.subscription
                          ? Icons.autorenew_rounded
                          : Icons.receipt_long_rounded,
                    ),
                    title: Text(charge.item.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(dateFormat.format(charge.dueDate)),
                    trailing: Text(charge.item.amount.format()),
                  ),
              ],
            ),
    );
  }
}

class _RecentTransactionsCard extends ConsumerWidget {
  const _RecentTransactionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider).value ?? const [];
    final categories = ref.watch(categoryByIdProvider);
    return SectionCard(
      title: context.tr('Recent transactions'),
      trailing: recent.isEmpty
          ? null
          : TextButton(onPressed: () => context.go(Routes.transactions), child: Text(context.tr('See all'))),
      child: recent.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              message: context.tr('Your transactions will appear here.'),
            )
          : Column(
              children: [
                for (final tx in recent)
                  TransactionTile(
                    transaction: tx,
                    category: categories[tx.categoryId],
                    onTap: () => context.push(Routes.editTransaction(tx.id)),
                  ),
              ],
            ),
    );
  }
}
