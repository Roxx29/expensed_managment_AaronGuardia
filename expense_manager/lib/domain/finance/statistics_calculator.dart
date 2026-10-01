import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';
import 'summary_calculator.dart';

class DayAmount {
  const DayAmount(this.date, this.amount);

  final DateTime date;
  final Money amount;
}

class YearStatistics {
  const YearStatistics({
    required this.year,
    required this.monthlyExpenses,
    required this.monthlyIncome,
    required this.totalExpenses,
    required this.totalIncome,
    required this.monthlyAverage,
    required this.expensesByCategory,
    required this.highestDay,
    required this.highestMonth,
  });

  final int year;

  /// 12 entries, January first.
  final List<Money> monthlyExpenses;
  final List<Money> monthlyIncome;
  final Money totalExpenses;
  final Money totalIncome;

  /// Total expenses / months elapsed in [year] (12 for past years).
  final Money monthlyAverage;

  /// Highest first.
  final List<CategoryAmount> expensesByCategory;

  /// Null when there are no expenses.
  final DayAmount? highestDay;

  /// 1–12, null when there are no expenses.
  final int? highestMonth;

  CategoryAmount? get highestCategory =>
      expensesByCategory.isEmpty ? null : expensesByCategory.first;
}

/// Current month vs the previous one.
class MonthComparison {
  const MonthComparison({required this.current, required this.previous});

  final MonthSummary current;
  final MonthSummary previous;

  /// Change in expenses in percent; null when the previous month had none.
  int? get expenseChangePercent => previous.expenses.isPositive
      ? divideRounded((current.expenses - previous.expenses).minor * 100, previous.expenses.minor)
      : null;

  /// Previous-month expenses for [categoryId].
  Money previousFor(String? categoryId) => previous.expensesByCategory
      .where((c) => c.categoryId == categoryId)
      .fold(Money.zero(current.expenses.currency), (acc, c) => acc + c.amount);
}

abstract final class StatisticsCalculator {
  /// Expense/income statistics for [year]. Other currencies are ignored.
  static YearStatistics year({
    required List<FinanceTransaction> transactions,
    required int year,
    required Currency currency,
    required DateTime today,
  }) {
    final zero = Money.zero(currency);
    final expenses = List.filled(12, zero);
    final income = List.filled(12, zero);
    final byCategory = <String?, Money>{};
    final byDay = <DateTime, Money>{};

    for (final t in transactions) {
      if (t.occurredAt.year != year || t.amount.currency != currency) continue;
      final m = t.occurredAt.month - 1;
      switch (t.type) {
        case TransactionType.expense:
          expenses[m] += t.amount;
          byCategory[t.categoryId] = (byCategory[t.categoryId] ?? zero) + t.amount;
          final day = dateOnly(t.occurredAt);
          byDay[day] = (byDay[day] ?? zero) + t.amount;
        case TransactionType.income:
          income[m] += t.amount;
        case TransactionType.transfer || TransactionType.savings || TransactionType.savingsWithdrawal:
          break;
      }
    }

    final totalExpenses = Money.sum(expenses, currency);
    final monthsElapsed = year < today.year ? 12 : (year == today.year ? today.month : 0);

    DayAmount? highestDay;
    for (final e in byDay.entries) {
      if (highestDay == null || e.value > highestDay.amount) highestDay = DayAmount(e.key, e.value);
    }
    int? highestMonth;
    for (var i = 0; i < 12; i++) {
      if (expenses[i].isPositive && (highestMonth == null || expenses[i] > expenses[highestMonth - 1])) {
        highestMonth = i + 1;
      }
    }

    return YearStatistics(
      year: year,
      monthlyExpenses: List.unmodifiable(expenses),
      monthlyIncome: List.unmodifiable(income),
      totalExpenses: totalExpenses,
      totalIncome: Money.sum(income, currency),
      monthlyAverage: monthsElapsed == 0 ? zero : totalExpenses.timesRatio(1, monthsElapsed),
      expensesByCategory: byCategory.entries.map((e) => CategoryAmount(e.key, e.value)).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
      highestDay: highestDay,
      highestMonth: highestMonth,
    );
  }

  /// Expenses per year for every year with data, oldest first.
  static Map<int, Money> expensesByYear(List<FinanceTransaction> transactions, Currency currency) {
    final result = <int, Money>{};
    for (final t in transactions) {
      if (t.type != TransactionType.expense || t.amount.currency != currency) continue;
      final y = t.occurredAt.year;
      result[y] = (result[y] ?? Money.zero(currency)) + t.amount;
    }
    return Map.fromEntries(result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Years to offer in the selector: every year with data plus the current one, newest first.
  static List<int> availableYears(List<FinanceTransaction> transactions, DateTime today) =>
      ({today.year, for (final t in transactions) t.occurredAt.year}.toList()..sort())
          .reversed
          .toList();

  static MonthComparison compareWithPrevious({
    required List<FinanceTransaction> transactions,
    required YearMonth month,
    required Currency currency,
  }) =>
      MonthComparison(
        current: SummaryCalculator.month(transactions: transactions, month: month, currency: currency),
        previous: SummaryCalculator.month(transactions: transactions, month: month.previous, currency: currency),
      );
}
