import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../finance/budget_calculator.dart';
import '../finance/summary_calculator.dart';

enum InsightSeverity { critical, warning, info }

enum InsightType {
  budgetExceeded,
  budgetNearLimit,
  spendingIncreased,
  highSubscriptionCost,
  categoryAboveAverage,
}

/// A recommendation. Text is produced by the UI from [type] + [values],
/// so insights stay localizable and an AI engine can emit the same shape.
class Insight {
  const Insight({
    required this.type,
    required this.severity,
    this.values = const {},
  });

  final InsightType type;
  final InsightSeverity severity;
  final Map<String, Object?> values;
}

/// Everything a rule may look at. Built once per dashboard refresh.
class InsightContext {
  const InsightContext({
    required this.currency,
    required this.currentMonth,
    required this.previousMonths,
    required this.budgets,
    required this.subscriptionsMonthlyCost,
  });

  final Currency currency;
  final MonthSummary currentMonth;

  /// Most recent first.
  final List<MonthSummary> previousMonths;
  final MonthlyBudgetReport budgets;
  final Money subscriptionsMonthlyCost;
}

/// Replace with an AI-backed implementation later via a provider override.
abstract interface class InsightsEngine {
  List<Insight> generate(InsightContext context);
}

typedef InsightRule = Iterable<Insight> Function(InsightContext context);

class RuleBasedInsightsEngine implements InsightsEngine {
  const RuleBasedInsightsEngine(this.rules);

  factory RuleBasedInsightsEngine.withDefaultRules() =>
      const RuleBasedInsightsEngine([
        budgetRule,
        spendingIncreaseRule,
        subscriptionCostRule,
        categoryAboveAverageRule,
      ]);

  final List<InsightRule> rules;

  @override
  List<Insight> generate(InsightContext context) => [
        for (final rule in rules) ...rule(context),
      ]..sort((a, b) => a.severity.index.compareTo(b.severity.index));
}

// --- Default rules -----------------------------------------------------------

const _spendingIncreaseThresholdPercent = 20;
const _subscriptionShareOfIncomePercent = 10;
const _categoryAboveAveragePercent = 50;
const _averageWindowMonths = 3;

Iterable<Insight> budgetRule(InsightContext c) sync* {
  Insight? toInsight(String? categoryId, BudgetProgress p) =>
      switch (p.status) {
        BudgetStatus.overBudget => Insight(
            type: InsightType.budgetExceeded,
            severity: InsightSeverity.critical,
            values: {'categoryId': categoryId, 'over': -p.remaining},
          ),
        BudgetStatus.nearLimit => Insight(
            type: InsightType.budgetNearLimit,
            severity: InsightSeverity.warning,
            values: {'categoryId': categoryId, 'remaining': p.remaining},
          ),
        BudgetStatus.onTrack => null,
      };

  final global = c.budgets.global;
  if (global != null) {
    final insight = toInsight(null, global);
    if (insight != null) yield insight;
  }
  for (final entry in c.budgets.byCategory.entries) {
    final insight = toInsight(entry.key, entry.value);
    if (insight != null) yield insight;
  }
}

Iterable<Insight> spendingIncreaseRule(InsightContext c) sync* {
  if (c.previousMonths.isEmpty) return;
  final previous = c.previousMonths.first.expenses;
  if (!previous.isPositive) return;
  final current = c.currentMonth.expenses;
  final percent = divideRounded((current - previous).minor * 100, previous.minor);
  if (percent > _spendingIncreaseThresholdPercent) {
    yield Insight(
      type: InsightType.spendingIncreased,
      severity: InsightSeverity.warning,
      values: {'percent': percent},
    );
  }
}

Iterable<Insight> subscriptionCostRule(InsightContext c) sync* {
  final income = c.currentMonth.income;
  final subs = c.subscriptionsMonthlyCost;
  if (!income.isPositive || !subs.isPositive) return;
  if (subs.minor * 100 > income.minor * _subscriptionShareOfIncomePercent) {
    yield Insight(
      type: InsightType.highSubscriptionCost,
      severity: InsightSeverity.info,
      values: {'monthly': subs, 'percentOfIncome': divideRounded(subs.minor * 100, income.minor)},
    );
  }
}

Iterable<Insight> categoryAboveAverageRule(InsightContext c) sync* {
  final history = c.previousMonths.take(_averageWindowMonths).toList();
  if (history.length < _averageWindowMonths) return;

  for (final current in c.currentMonth.expensesByCategory) {
    final categoryId = current.categoryId;
    if (categoryId == null) continue;
    var total = 0;
    for (final month in history) {
      for (final item in month.expensesByCategory) {
        if (item.categoryId == categoryId) total += item.amount.minor;
      }
    }
    final average = divideRounded(total, history.length);
    if (average <= 0) continue;
    if (current.amount.minor * 100 > average * (100 + _categoryAboveAveragePercent)) {
      yield Insight(
        type: InsightType.categoryAboveAverage,
        severity: InsightSeverity.info,
        values: {
          'categoryId': categoryId,
          'average': Money(average, c.currency),
          'current': current.amount,
        },
      );
    }
  }
}
