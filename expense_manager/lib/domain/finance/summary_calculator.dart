import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';

class CategoryAmount {
  const CategoryAmount(this.categoryId, this.amount);

  /// Null = uncategorized.
  final String? categoryId;
  final Money amount;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.income,
    required this.expenses,
    required this.savings,
    required this.expensesByCategory,
  });

  final YearMonth month;
  final Money income;
  final Money expenses;

  /// Money moved into savings goals this month.
  final Money savings;

  /// Sorted by amount, highest first.
  final List<CategoryAmount> expensesByCategory;

  /// What is left of this month's income.
  Money get net => income - expenses - savings;
}

abstract final class SummaryCalculator {
  /// Totals for [month]. Transfers are neutral; other currencies are ignored.
  static MonthSummary month({
    required List<FinanceTransaction> transactions,
    required YearMonth month,
    required Currency currency,
  }) {
    var income = Money.zero(currency);
    var expenses = Money.zero(currency);
    var savings = Money.zero(currency);
    final byCategory = <String?, Money>{};

    for (final t in transactions) {
      if (t.amount.currency != currency || !month.contains(t.occurredAt)) {
        continue;
      }
      switch (t.type) {
        case TransactionType.income:
          income += t.amount;
        case TransactionType.expense:
          expenses += t.amount;
          byCategory[t.categoryId] =
              (byCategory[t.categoryId] ?? Money.zero(currency)) + t.amount;
        case TransactionType.savings:
          savings += t.amount;
        case TransactionType.transfer:
          break;
      }
    }

    final breakdown = byCategory.entries
        .map((e) => CategoryAmount(e.key, e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return MonthSummary(
      month: month,
      income: income,
      expenses: expenses,
      savings: savings,
      expensesByCategory: breakdown,
    );
  }

  /// Available money = all income − all expenses − money set aside in savings.
  static Money availableBalance({
    required Map<TransactionType, Money> totalsByType,
    required Currency currency,
  }) {
    Money of(TransactionType type) =>
        totalsByType[type] ?? Money.zero(currency);
    return of(TransactionType.income) -
        of(TransactionType.expense) -
        of(TransactionType.savings);
  }
}
