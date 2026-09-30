import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/budget_calculator.dart';
import 'package:expense_manager/domain/finance/summary_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
const sept = YearMonth(2026, 9);

FinanceTransaction tx(
  TransactionType type,
  int minor, {
  String? category,
  DateTime? at,
  Currency currency = usd,
}) =>
    FinanceTransaction(
      id: 'id-$minor-${type.name}-$category',
      type: type,
      amount: Money(minor, currency),
      occurredAt: at ?? DateTime(2026, 9, 10),
      categoryId: category,
    );

void main() {
  group('BudgetCalculator.progress', () {
    test('matches the Food example: 250 budget, 180 spent', () {
      final p = BudgetCalculator.progress(
        budgeted: const Money(25000, usd),
        spent: const Money(18000, usd),
      );
      expect(p.remaining, const Money(7000, usd));
      expect(p.ratio, closeTo(0.72, 1e-9));
      expect(p.status, BudgetStatus.onTrack);
    });

    test('warns at 80% or more', () {
      final p = BudgetCalculator.progress(
        budgeted: const Money(10000, usd),
        spent: const Money(8000, usd),
      );
      expect(p.status, BudgetStatus.nearLimit);
    });

    test('over budget has negative remaining', () {
      final p = BudgetCalculator.progress(
        budgeted: const Money(10000, usd),
        spent: const Money(12000, usd),
      );
      expect(p.status, BudgetStatus.overBudget);
      expect(p.remaining, const Money(-2000, usd));
    });

    test('zero budget with spending is over budget', () {
      final p = BudgetCalculator.progress(
        budgeted: const Money.zero(usd),
        spent: const Money(1, usd),
      );
      expect(p.status, BudgetStatus.overBudget);
    });
  });

  group('BudgetCalculator.monthlyReport', () {
    const budgets = [
      Budget(id: 'g', amount: Money(100000, usd), startMonth: YearMonth(2026, 1)),
      Budget(
        id: 'food',
        categoryId: 'cat_food',
        amount: Money(25000, usd),
        startMonth: YearMonth(2026, 1),
      ),
      // Expired budget must be ignored.
      Budget(
        id: 'old',
        categoryId: 'cat_gas',
        amount: Money(5000, usd),
        startMonth: YearMonth(2025, 1),
        endMonth: YearMonth(2026, 8),
      ),
    ];

    final transactions = [
      tx(TransactionType.expense, 18000, category: 'cat_food'),
      tx(TransactionType.expense, 4000, category: 'cat_gas'),
      tx(TransactionType.income, 500000),
      tx(TransactionType.expense, 999, category: 'cat_food', at: DateTime(2026, 8, 31)),
    ];

    test('computes global and category progress for the month only', () {
      final report = BudgetCalculator.monthlyReport(
        budgets: budgets,
        transactions: transactions,
        month: sept,
        currency: usd,
      );
      expect(report.global!.spent, const Money(22000, usd));
      expect(report.byCategory.keys, ['cat_food']);
      expect(report.byCategory['cat_food']!.spent, const Money(18000, usd));
      expect(report.byCategory['cat_food']!.remaining, const Money(7000, usd));
    });

    test('global is null when no global budget applies', () {
      final report = BudgetCalculator.monthlyReport(
        budgets: budgets.where((b) => !b.isGlobal).toList(),
        transactions: transactions,
        month: sept,
        currency: usd,
      );
      expect(report.global, isNull);
    });
  });

  group('SummaryCalculator', () {
    final transactions = [
      tx(TransactionType.income, 300000),
      tx(TransactionType.expense, 5000, category: 'cat_food'),
      tx(TransactionType.expense, 2500, category: 'cat_food'),
      tx(TransactionType.expense, 9000, category: 'cat_home'),
      tx(TransactionType.expense, 100, category: null),
      tx(TransactionType.savings, 10000),
      tx(TransactionType.transfer, 7777),
      tx(TransactionType.expense, 123456, at: DateTime(2026, 10, 1)),
      tx(TransactionType.expense, 500, currency: Currency.eur),
    ];

    test('month totals ignore other months, transfers and other currencies', () {
      final s = SummaryCalculator.month(
        transactions: transactions,
        month: sept,
        currency: usd,
      );
      expect(s.income, const Money(300000, usd));
      expect(s.expenses, const Money(16600, usd));
      expect(s.savings, const Money(10000, usd));
      expect(s.net, const Money(273400, usd));
    });

    test('category breakdown is sorted by amount descending', () {
      final s = SummaryCalculator.month(
        transactions: transactions,
        month: sept,
        currency: usd,
      );
      expect(s.expensesByCategory.map((e) => e.categoryId).toList(),
          ['cat_home', 'cat_food', null]);
      expect(s.expensesByCategory[1].amount, const Money(7500, usd));
    });

    test('available balance = income - expenses - savings', () {
      final balance = SummaryCalculator.availableBalance(
        totalsByType: {
          TransactionType.income: const Money(100000, usd),
          TransactionType.expense: const Money(40000, usd),
          TransactionType.savings: const Money(10000, usd),
          TransactionType.transfer: const Money(99999, usd),
        },
        currency: usd,
      );
      expect(balance, const Money(50000, usd));
    });
  });
}
