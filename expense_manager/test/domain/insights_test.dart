import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/finance/budget_calculator.dart';
import 'package:expense_manager/domain/finance/summary_calculator.dart';
import 'package:expense_manager/domain/insights/insights.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
Money m(int minor) => Money(minor, usd);

MonthSummary summary(
  YearMonth month, {
  int income = 0,
  int expenses = 0,
  List<CategoryAmount> categories = const [],
}) =>
    MonthSummary(
      month: month,
      income: m(income),
      expenses: m(expenses),
      savings: m(0),
      expensesByCategory: categories,
    );

InsightContext context({
  MonthSummary? current,
  List<MonthSummary> previous = const [],
  MonthlyBudgetReport budgets =
      const MonthlyBudgetReport(global: null, byCategory: {}),
  int subscriptionsMonthly = 0,
}) =>
    InsightContext(
      currency: usd,
      currentMonth: current ?? summary(const YearMonth(2026, 9)),
      previousMonths: previous,
      budgets: budgets,
      subscriptionsMonthlyCost: m(subscriptionsMonthly),
    );

void main() {
  final engine = RuleBasedInsightsEngine.withDefaultRules();

  test('no data → no insights', () {
    expect(engine.generate(context()), isEmpty);
  });

  test('spending increased more than 20% vs last month', () {
    final insights = engine.generate(context(
      current: summary(const YearMonth(2026, 9), expenses: 13000),
      previous: [summary(const YearMonth(2026, 8), expenses: 10000)],
    ));
    final insight = insights.singleWhere((i) => i.type == InsightType.spendingIncreased);
    expect(insight.values['percent'], 30);
  });

  test('budget near limit and over budget', () {
    final report = MonthlyBudgetReport(
      global: BudgetCalculator.progress(budgeted: m(10000), spent: m(9000)),
      byCategory: {
        'cat_food': BudgetCalculator.progress(budgeted: m(100), spent: m(200)),
      },
    );
    final types = engine.generate(context(budgets: report)).map((i) => i.type);
    expect(types, containsAll([InsightType.budgetNearLimit, InsightType.budgetExceeded]));
  });

  test('subscriptions above 10% of income', () {
    final insights = engine.generate(context(
      current: summary(const YearMonth(2026, 9), income: 100000),
      subscriptionsMonthly: 15000,
    ));
    expect(insights.map((i) => i.type), contains(InsightType.highSubscriptionCost));
  });

  test('category above its 3-month average by 50%+', () {
    final insights = engine.generate(context(
      current: summary(const YearMonth(2026, 9),
          expenses: 30000, categories: [CategoryAmount('cat_food', m(30000))]),
      previous: [
        for (var i = 1; i <= 3; i++)
          summary(const YearMonth(2026, 9).addMonths(-i),
              expenses: 10000, categories: [CategoryAmount('cat_food', m(10000))]),
      ],
    ));
    final insight = insights.singleWhere((i) => i.type == InsightType.categoryAboveAverage);
    expect(insight.values['categoryId'], 'cat_food');
  });

  test('insights are sorted by severity (critical first)', () {
    final report = MonthlyBudgetReport(
      global: BudgetCalculator.progress(budgeted: m(10000), spent: m(9000)),
      byCategory: {
        'x': BudgetCalculator.progress(budgeted: m(100), spent: m(200)),
      },
    );
    final insights = engine.generate(context(budgets: report));
    expect(insights.first.severity, InsightSeverity.critical);
  });
}
