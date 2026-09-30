import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';
import '../insights/insights.dart';
import 'budget_calculator.dart';
import 'recurring_poster.dart';
import 'summary_calculator.dart';

class UpcomingCharge {
  const UpcomingCharge(this.item, this.dueDate);

  final RecurringItem item;
  final DateTime dueDate;
}

/// Everything the dashboard shows, computed in one place.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.month,
    required this.availableBalance,
    required this.summary,
    required this.budgets,
    required this.upcomingCharges,
    required this.subscriptionsMonthlyCost,
    required this.recurringMonthlyCost,
    required this.insights,
  });

  final YearMonth month;
  final Money availableBalance;
  final MonthSummary summary;
  final MonthlyBudgetReport budgets;
  final List<UpcomingCharge> upcomingCharges;
  final Money subscriptionsMonthlyCost;

  /// Subscriptions + bills.
  final Money recurringMonthlyCost;
  final List<Insight> insights;
}

abstract final class DashboardComposer {
  static const upcomingWindowDays = 30;
  static const historyMonths = 3;

  /// [transactions] should cover the current month plus [historyMonths]
  /// previous months (used for comparisons and insights).
  static DashboardSnapshot compose({
    required DateTime today,
    required Currency currency,
    required List<FinanceTransaction> transactions,
    required List<Budget> budgets,
    required List<RecurringItem> recurringItems,
    required Map<TransactionType, Money> totalsByType,
    required InsightsEngine insightsEngine,
  }) {
    final month = YearMonth.fromDate(today);
    final summary = SummaryCalculator.month(
      transactions: transactions,
      month: month,
      currency: currency,
    );
    final previous = [
      for (var i = 1; i <= historyMonths; i++)
        SummaryCalculator.month(
          transactions: transactions,
          month: month.addMonths(-i),
          currency: currency,
        ),
    ];
    final budgetReport = BudgetCalculator.monthlyReport(
      budgets: budgets,
      transactions: transactions,
      month: month,
      currency: currency,
    );

    final active = recurringItems
        .where((i) => i.isActive && i.amount.currency == currency)
        .toList();
    final subscriptionsMonthly =
        RecurringPoster.totals(active, currency, kind: RecurringKind.subscription).monthly;
    final recurringMonthly = RecurringPoster.totals(active, currency).monthly;

    // Starts tomorrow: charges due today are already recorded as expenses.
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final windowEnd = DateTime(today.year, today.month, today.day + upcomingWindowDays);
    final upcoming = <UpcomingCharge>[
      for (final item in active)
        if (item.nextDueDate(tomorrow) case final due? when !due.isAfter(windowEnd))
          UpcomingCharge(item, due),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final insights = insightsEngine.generate(InsightContext(
      currency: currency,
      currentMonth: summary,
      previousMonths: previous,
      budgets: budgetReport,
      subscriptionsMonthlyCost: subscriptionsMonthly,
    ));

    return DashboardSnapshot(
      month: month,
      availableBalance: SummaryCalculator.availableBalance(
        totalsByType: totalsByType,
        currency: currency,
      ),
      summary: summary,
      budgets: budgetReport,
      upcomingCharges: upcoming,
      subscriptionsMonthlyCost: subscriptionsMonthly,
      recurringMonthlyCost: recurringMonthly,
      insights: insights,
    );
  }
}
