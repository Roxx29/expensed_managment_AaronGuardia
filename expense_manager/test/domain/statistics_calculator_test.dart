import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/statistics_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;
  final today = DateTime(2026, 9, 30);

  var n = 0;
  FinanceTransaction tx(TransactionType type, int minor, DateTime at, {String? category, Currency c = usd}) =>
      FinanceTransaction(id: '${n++}', type: type, amount: Money(minor, c), occurredAt: at, categoryId: category);

  final txs = [
    tx(TransactionType.expense, 10000, DateTime(2026, 1, 5, 10), category: 'food'),
    tx(TransactionType.expense, 5000, DateTime(2026, 1, 5, 18), category: 'gas'),
    tx(TransactionType.expense, 30000, DateTime(2026, 9, 2), category: 'home'),
    tx(TransactionType.expense, 2000, DateTime(2026, 9, 3), category: 'food'),
    tx(TransactionType.income, 300000, DateTime(2026, 9, 1)),
    tx(TransactionType.transfer, 99999, DateTime(2026, 9, 1)),
    tx(TransactionType.expense, 7000, DateTime(2025, 12, 31), category: 'food'),
    tx(TransactionType.expense, 100, DateTime(2026, 3, 1), c: Currency.eur),
  ];

  group('year', () {
    final s = StatisticsCalculator.year(transactions: txs, year: 2026, currency: usd, today: today);

    test('monthly series has 12 months and ignores other years/currencies/transfers', () {
      expect(s.monthlyExpenses, hasLength(12));
      expect(s.monthlyExpenses[0], const Money(15000, usd));
      expect(s.monthlyExpenses[8], const Money(32000, usd));
      expect(s.monthlyExpenses[2], const Money.zero(usd));
      expect(s.monthlyIncome[8], const Money(300000, usd));
    });

    test('annual total and monthly average over elapsed months', () {
      expect(s.totalExpenses, const Money(47000, usd));
      expect(s.totalIncome, const Money(300000, usd));
      // 47000 / 9 months (Jan–Sep) = 5222.2 → 5222
      expect(s.monthlyAverage, const Money(5222, usd));
    });

    test('highest category, day and month', () {
      expect(s.highestCategory!.categoryId, 'home');
      expect(s.expensesByCategory.map((c) => c.categoryId), ['home', 'food', 'gas']);
      expect(s.highestDay!.date, DateTime(2026, 9, 2));
      expect(s.highestMonth, 9);
    });

    test('past year averages over 12 months; future year has no average', () {
      final past = StatisticsCalculator.year(transactions: txs, year: 2025, currency: usd, today: today);
      expect(past.monthlyAverage, const Money(583, usd)); // 7000 / 12
      final future = StatisticsCalculator.year(transactions: txs, year: 2027, currency: usd, today: today);
      expect(future.monthlyAverage, const Money.zero(usd));
      expect(future.highestDay, isNull);
      expect(future.highestMonth, isNull);
    });
  });

  test('expensesByYear is sorted oldest first', () {
    final byYear = StatisticsCalculator.expensesByYear(txs, usd);
    expect(byYear.keys, [2025, 2026]);
    expect(byYear[2025], const Money(7000, usd));
  });

  test('availableYears includes the current year, newest first', () {
    expect(StatisticsCalculator.availableYears(txs, today), [2026, 2025]);
    expect(StatisticsCalculator.availableYears(const [], today), [2026]);
  });

  test('month comparison', () {
    final c = StatisticsCalculator.compareWithPrevious(
      transactions: [
        ...txs,
        tx(TransactionType.expense, 16000, DateTime(2026, 8, 10), category: 'food'),
      ],
      month: const YearMonth(2026, 9),
      currency: usd,
    );
    expect(c.expenseChangePercent, 100); // 32000 vs 16000
    expect(c.previousFor('food'), const Money(16000, usd));
    expect(c.previousFor('home'), const Money.zero(usd));

    final noHistory = StatisticsCalculator.compareWithPrevious(
      transactions: txs,
      month: const YearMonth(2026, 1),
      currency: usd,
    );
    expect(noHistory.expenseChangePercent, isNotNull); // Dec 2025 had 7000
    final none = StatisticsCalculator.compareWithPrevious(
      transactions: txs,
      month: const YearMonth(2026, 3),
      currency: usd,
    );
    expect(none.expenseChangePercent, isNull);
  });
}
