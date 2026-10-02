import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/budget_calculator.dart';
import 'package:expense_manager/domain/finance/recurrence.dart';
import 'package:expense_manager/domain/notifications/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;
  final now = DateTime(2026, 10, 1, 12); // noon

  RecurringItem item(String id, {Frequency frequency = Frequency.monthly, DateTime? anchor, bool active = true}) =>
      RecurringItem(
        id: id,
        kind: RecurringKind.subscription,
        name: id,
        amount: const Money(1599, usd),
        rule: RecurrenceRule(frequency),
        anchorDate: anchor ?? DateTime(2026, 7, 15),
        isActive: active,
      );

  group('ReminderPlanner', () {
    test('day before at 9:00, within 30 days, no amounts', () {
      final plan = ReminderPlanner.plan(items: [item('netflix')], now: now, daysBefore: {1});
      expect(plan, hasLength(1));
      expect(plan.single.when, DateTime(2026, 10, 14, 9));
      expect(plan.single.id, ReminderPlanner.firstId);
      expect(plan.single.body, '{name} is due tomorrow');
      expect(plan.single.args['name'], 'netflix');
    });

    test('same day; skips times already past and inactive items', () {
      final plan = ReminderPlanner.plan(
        items: [item('today', anchor: DateTime(2026, 9, 1)), item('off', active: false), item('netflix')],
        now: now,
        daysBefore: {0},
      );
      // 'today' is due Oct 1 at 9:00, already past at noon.
      expect(plan.map((n) => n.when), [DateTime(2026, 10, 15, 9)]);
      expect(plan.single.body, '{name} is due today');
    });

    test('several reminders per payment, custom hour, week before', () {
      final plan = ReminderPlanner.plan(items: [item('netflix')], now: now, daysBefore: {7, 1}, hour: 20);
      expect(plan.map((n) => n.when), [DateTime(2026, 10, 8, 20), DateTime(2026, 10, 14, 20)]);
      expect(plan.first.body, '{name} is due in {days} days');
      expect(plan.first.args['days'], '7');
      // Nov 15's reminders (Nov 8, Nov 14) are past the 30-day horizon.
    });

    test('settings parsing keeps old values working', () {
      expect(ReminderPlanner.parseDays(null), {1});
      expect(ReminderPlanner.parseDays('day_before'), {1});
      expect(ReminderPlanner.parseDays('same_day'), {0});
      expect(ReminderPlanner.parseDays('7,1,99'), {7, 1});
      expect(ReminderPlanner.encodeDays({7, 0, 3}), '0,3,7');
      expect(ReminderPlanner.parseHour('20'), 20);
      expect(ReminderPlanner.parseHour('25'), ReminderPlanner.defaultHour);
    });

    test('sorted, capped and with deterministic ids in range', () {
      final items = [item('b'), item('daily', frequency: Frequency.daily, anchor: DateTime(2026, 1, 1))];
      final plan = ReminderPlanner.plan(items: items, now: now, daysBefore: {1});
      expect(plan, hasLength(ReminderPlanner.maxCount));
      expect(plan.map((n) => n.id), List.generate(ReminderPlanner.maxCount, (i) => ReminderPlanner.firstId + i));
      expect(plan.first.when, DateTime(2026, 10, 2, 9));
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].when.isBefore(plan[i - 1].when), isFalse);
      }
      final again = ReminderPlanner.plan(items: items.reversed.toList(), now: now, daysBefore: {1});
      expect(again.map((n) => '${n.id}${n.args}'), plan.map((n) => '${n.id}${n.args}'));
    });
  });

  group('BudgetAlertPlanner', () {
    const month = YearMonth(2026, 10);
    BudgetProgress p(int spent) => BudgetCalculator.progress(budgeted: const Money(10000, usd), spent: Money(spent, usd));

    test('alerts once per budget, month and status', () {
      final report = MonthlyBudgetReport(global: p(8500), byCategory: {'cat_food': p(12000), 'cat_gas': p(100)});
      final alerts = BudgetAlertPlanner.newAlerts(report: report, month: month, shown: {});
      expect(alerts.map((a) => a.key), ['202610:global:nearLimit', '202610:cat_food:overBudget']);
      expect(alerts.first.body, 'You\'re close to your monthly budget');
      expect(alerts.last.body, 'You\'re over your {name} budget');
      expect(alerts.every((a) => a.id >= 2000 && a.id < 3000), isTrue);
      expect(alerts.first.id, BudgetAlertPlanner.idFor('202610:global:nearLimit'));

      final again = BudgetAlertPlanner.newAlerts(report: report, month: month, shown: alerts.map((a) => a.key).toSet());
      expect(again, isEmpty);
    });

    test('prune keeps only the current month', () {
      expect(BudgetAlertPlanner.prune({'202609:global:nearLimit', '202610:cat_food:overBudget'}, month),
          {'202610:cat_food:overBudget'});
    });
  });
}
