import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/savings_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
final today = DateTime(2026, 10, 15, 9, 30);

var _n = 0;
FinanceTransaction tx(TransactionType type, int minor, {String? goal = 'g1', Currency currency = usd}) =>
    FinanceTransaction(
      id: 'tx${_n++}',
      type: type,
      amount: Money(minor, currency),
      occurredAt: DateTime(2026, 10, 1),
      savingsGoalId: goal,
    );

SavingsGoal goal({int target = 100000, DateTime? date, String id = 'g1'}) =>
    SavingsGoal(id: id, name: 'Trip', target: Money(target, usd), targetDate: date);

SavingsProgress one(SavingsGoal g, List<FinanceTransaction> txs) =>
    SavingsCalculator.progress([g], txs, today: today).single;

void main() {
  test('saved = deposits − withdrawals of that goal, same currency only', () {
    final p = one(goal(), [
      tx(TransactionType.savings, 30000),
      tx(TransactionType.savings, 20000),
      tx(TransactionType.savingsWithdrawal, 5000),
      tx(TransactionType.savings, 99999, goal: 'other'),
      tx(TransactionType.savings, 99999, currency: Currency.eur),
      tx(TransactionType.expense, 99999),
    ]);
    expect(p.saved, const Money(45000, usd));
    expect(p.remaining, const Money(55000, usd));
    expect(p.ratio, closeTo(0.45, 1e-9));
    expect(p.isReached, isFalse);
    expect(p.suggestedMonthly, isNull); // no target date
  });

  test('no transactions → zero saved', () {
    final p = one(goal(), const []);
    expect(p.saved, const Money(0, usd));
    expect(p.ratio, 0);
  });

  test('reached goal: remaining zero, ratio capped, no suggestion', () {
    final p = one(goal(date: DateTime(2027, 1, 1)), [tx(TransactionType.savings, 120000)]);
    expect(p.isReached, isTrue);
    expect(p.remaining, const Money(0, usd));
    expect(p.ratio, 1.0);
    expect(p.suggestedMonthly, isNull);
    expect(p.isOverdue, isFalse);
  });

  test('suggested monthly counts deposits on today\'s day up to the date, rounded up', () {
    // Oct 15 → Jan 15: Oct, Nov, Dec, Jan = 4 deposits.
    expect(one(goal(date: DateTime(2027, 1, 15)), const []).suggestedMonthly, const Money(25000, usd));
    // Oct 15 → Jan 14: 3 deposits; 100000 / 3 rounds up to 33334.
    expect(one(goal(date: DateTime(2027, 1, 14)), const []).suggestedMonthly, const Money(33334, usd));
    // Due later this month → everything now.
    expect(one(goal(date: DateTime(2026, 10, 20)), const []).suggestedMonthly, const Money(100000, usd));
    // Due today (time of day ignored).
    expect(one(goal(date: DateTime(2026, 10, 15)), const []).suggestedMonthly, const Money(100000, usd));
  });

  test('suggestion uses the remaining amount', () {
    final p = one(goal(date: DateTime(2027, 1, 15)), [tx(TransactionType.savings, 60000)]);
    expect(p.suggestedMonthly, const Money(10000, usd));
  });

  test('past target date → overdue, no suggestion', () {
    final p = one(goal(date: DateTime(2026, 10, 14)), const []);
    expect(p.isOverdue, isTrue);
    expect(p.suggestedMonthly, isNull);
  });

  test('one result per goal, in goal order', () {
    final result = SavingsCalculator.progress(
      [goal(id: 'a'), goal(id: 'b')],
      [tx(TransactionType.savings, 100, goal: 'b')],
      today: today,
    );
    expect(result.map((p) => p.goal.id), ['a', 'b']);
    expect(result.map((p) => p.saved.minor), [0, 100]);
  });

  test('a deposit already withdrawn cannot be deleted (goal would go negative)', () {
    final deposit = tx(TransactionType.savings, 30000);
    final all = [deposit, tx(TransactionType.savings, 10000), tx(TransactionType.savingsWithdrawal, 25000)];
    expect(SavingsCalculator.canDelete(deposit, all), isFalse); // 15000 - 30000 < 0
    expect(SavingsCalculator.canDelete(all[1], all), isTrue); // 15000 - 10000 >= 0
    expect(SavingsCalculator.canDelete(all[2], all), isTrue); // withdrawals can always go
    expect(SavingsCalculator.canDelete(tx(TransactionType.expense, 5000), all), isTrue);
  });
}
