import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/dashboard.dart';
import 'package:expense_manager/domain/finance/recurrence.dart';
import 'package:expense_manager/domain/insights/insights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;
  final today = DateTime(2026, 9, 30);

  RecurringItem item(String id, RecurringKind kind, int minor, DateTime anchor, {bool active = true}) =>
      RecurringItem(
        id: id,
        kind: kind,
        name: id,
        amount: Money(minor, usd),
        rule: const RecurrenceRule(Frequency.monthly),
        anchorDate: anchor,
        isActive: active,
      );

  DashboardSnapshot build({List<RecurringItem> items = const [], List<FinanceTransaction> txs = const []}) =>
      DashboardComposer.compose(
        today: today,
        currency: usd,
        transactions: txs,
        budgets: const [],
        recurringItems: items,
        totalsByType: const {},
        insightsEngine: RuleBasedInsightsEngine.withDefaultRules(),
      );

  test('empty data produces an empty but valid snapshot', () {
    final s = build();
    expect(s.availableBalance, const Money.zero(usd));
    expect(s.month, const YearMonth(2026, 9));
    expect(s.upcomingCharges, isEmpty);
    expect(s.insights, isEmpty);
    expect(s.budgets.global, isNull);
  });

  test('upcoming charges: active items due within 30 days, soonest first', () {
    final s = build(items: [
      item('netflix', RecurringKind.subscription, 1599, DateTime(2026, 1, 15)),
      item('rent', RecurringKind.bill, 80000, DateTime(2026, 1, 1)),
      item('paused', RecurringKind.subscription, 999, DateTime(2026, 1, 2), active: false),
    ]);
    expect(s.upcomingCharges.map((c) => c.item.id), ['rent', 'netflix']);
    expect(s.upcomingCharges.first.dueDate, DateTime(2026, 10, 1));
  });

  test('subscription monthly total counts only active subscriptions', () {
    final s = build(items: [
      item('a', RecurringKind.subscription, 1000, DateTime(2026, 1, 1)),
      item('b', RecurringKind.subscription, 500, DateTime(2026, 1, 1), active: false),
      item('rent', RecurringKind.bill, 80000, DateTime(2026, 1, 1)),
    ]);
    expect(s.subscriptionsMonthlyCost, const Money(1000, usd));
    expect(s.recurringMonthlyCost, const Money(81000, usd));
  });
}
