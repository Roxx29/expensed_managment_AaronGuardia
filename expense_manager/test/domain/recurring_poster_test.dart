import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/budget_calculator.dart';
import 'package:expense_manager/domain/finance/recurrence.dart';
import 'package:expense_manager/domain/finance/recurring_poster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;
  final today = DateTime(2026, 9, 30);

  RecurringItem item(
    String id, {
    Frequency frequency = Frequency.monthly,
    DateTime? anchor,
    DateTime? end,
    bool active = true,
    RecurringKind kind = RecurringKind.subscription,
    int minor = 1599,
  }) =>
      RecurringItem(
        id: id,
        kind: kind,
        name: id,
        amount: Money(minor, usd),
        rule: RecurrenceRule(frequency),
        anchorDate: anchor ?? DateTime(2026, 7, 15),
        endDate: end,
        isActive: active,
        categoryId: 'cat_subscriptions',
      );

  group('dueTransactions', () {
    test('posts every occurrence from anchor through today, with deterministic ids', () {
      final txs = RecurringPoster.dueTransactions(items: [item('netflix')], today: today);
      expect(txs.map((t) => t.id), ['netflix_20260715', 'netflix_20260815', 'netflix_20260915']);
      expect(txs.first.type, TransactionType.expense);
      expect(txs.first.recurringItemId, 'netflix');
      expect(txs.first.categoryId, 'cat_subscriptions');
      expect(txs.first.description, 'netflix');
    });

    test('includes a charge due today, excludes future ones', () {
      final txs = RecurringPoster.dueTransactions(items: [item('rent', anchor: DateTime(2026, 9, 30))], today: today);
      expect(txs.single.occurredAt, DateTime(2026, 9, 30));
      expect(RecurringPoster.dueTransactions(items: [item('x', anchor: DateTime(2026, 10, 1))], today: today), isEmpty);
    });

    test('skips paused items and respects end dates', () {
      expect(RecurringPoster.dueTransactions(items: [item('p', active: false)], today: today), isEmpty);
      final ended = RecurringPoster.dueTransactions(
        items: [item('e', end: DateTime(2026, 8, 20))],
        today: today,
      );
      expect(ended.map((t) => t.id), ['e_20260715', 'e_20260815']);
    });

    test('back-fill is limited to the last year', () {
      final txs = RecurringPoster.dueTransactions(
        items: [item('daily', frequency: Frequency.daily, anchor: DateTime(2020, 1, 1))],
        today: today,
      );
      expect(txs.length, RecurringPoster.maxBackfillDays + 1);
    });

    test('postedFrom skips earlier occurrences (paused period / old schedule)', () {
      final resumed = item('n').copyWith(postedFrom: DateTime(2026, 9, 20));
      expect(RecurringPoster.dueTransactions(items: [resumed], today: today), isEmpty);
      final resumedEarlier = item('n').copyWith(postedFrom: DateTime(2026, 9, 1));
      expect(RecurringPoster.dueTransactions(items: [resumedEarlier], today: today).map((t) => t.id),
          ['n_20260915']);
    });

    test('withPostingStart: set on resume or schedule change, not on other edits', () {
      final paused = item('n', active: false);
      final active = item('n');
      expect(RecurringPoster.withPostingStart(paused, active, today).postedFrom, DateTime(2026, 9, 30));
      expect(RecurringPoster.withPostingStart(null, active, today).postedFrom, isNull);
      expect(RecurringPoster.withPostingStart(active, item('n', minor: 999), today).postedFrom, isNull);
      expect(
        RecurringPoster.withPostingStart(active, item('n', anchor: DateTime(2026, 7, 16)), today).postedFrom,
        DateTime(2026, 9, 30),
      );
    });

    test('running twice produces the same ids (idempotent)', () {
      final a = RecurringPoster.dueTransactions(items: [item('n')], today: today).map((t) => t.id);
      final b = RecurringPoster.dueTransactions(items: [item('n')], today: today).map((t) => t.id);
      expect(a, b);
    });
  });

  test('totals: monthly/yearly of active items, filtered by kind', () {
    final items = [
      item('a', minor: 1000),
      item('b', minor: 12000, frequency: Frequency.yearly),
      item('paused', minor: 5000, active: false),
      item('rent', minor: 80000, kind: RecurringKind.bill),
    ];
    final subs = RecurringPoster.totals(items, usd, kind: RecurringKind.subscription);
    expect(subs.monthly, const Money(2000, usd));
    expect(subs.yearly, const Money(24000, usd));
    expect(subs.count, 2);
    expect(RecurringPoster.totals(items, usd).count, 3);
  });

  test('budget allocation: allocated and unallocated', () {
    final report = MonthlyBudgetReport(
      global: BudgetCalculator.progress(budgeted: const Money(100000, usd), spent: const Money.zero(usd)),
      byCategory: {
        'food': BudgetCalculator.progress(budgeted: const Money(25000, usd), spent: const Money.zero(usd)),
        'gas': BudgetCalculator.progress(budgeted: const Money(10000, usd), spent: const Money.zero(usd)),
      },
    );
    expect(report.allocated, const Money(35000, usd));
    expect(report.unallocated, const Money(65000, usd));
    expect(const MonthlyBudgetReport(global: null, byCategory: {}).allocated, isNull);
  });
}
