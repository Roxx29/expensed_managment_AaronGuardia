import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';

/// What one member recorded in a shared wallet during a month.
class MemberTotals {
  const MemberTotals({required this.uid, required this.income, required this.expenses, required this.count});

  /// Null = entries without an author (imported or older ones).
  final String? uid;
  final Money income;
  final Money expenses;
  final int count;
}

/// Calculations for shared wallets (pure Dart, see wallet_stats_test.dart).
abstract final class WalletStats {
  /// Per member totals in [month], most spending first. Other currencies are
  /// left out (same rule as SummaryCalculator).
  static List<MemberTotals> byMember(List<FinanceTransaction> transactions, YearMonth month, Currency currency) {
    final income = <String?, Money>{};
    final expenses = <String?, Money>{};
    final counts = <String?, int>{};
    for (final t in transactions) {
      if (t.amount.currency != currency || !month.contains(t.occurredAt)) continue;
      final who = t.createdBy;
      switch (t.type) {
        case TransactionType.income:
          income[who] = (income[who] ?? Money.zero(currency)) + t.amount;
        case TransactionType.expense:
          expenses[who] = (expenses[who] ?? Money.zero(currency)) + t.amount;
        default:
          continue;
      }
      counts[who] = (counts[who] ?? 0) + 1;
    }
    return [
      for (final who in counts.keys)
        MemberTotals(
          uid: who,
          income: income[who] ?? Money.zero(currency),
          expenses: expenses[who] ?? Money.zero(currency),
          count: counts[who]!,
        ),
    ]..sort((a, b) {
        final byExpense = b.expenses.compareTo(a.expenses);
        return byExpense != 0 ? byExpense : b.income.compareTo(a.income);
      });
  }

  /// All-time income − expenses of a wallet in [currency].
  static Money balance(List<FinanceTransaction> transactions, Currency currency) {
    var total = Money.zero(currency);
    for (final t in transactions) {
      if (t.amount.currency != currency) continue;
      if (t.type == TransactionType.income) total += t.amount;
      if (t.type == TransactionType.expense) total -= t.amount;
    }
    return total;
  }

  /// History filter: [type] (null = all), author [member] ('' = all) and a
  /// case-insensitive [query] on the description, notes and [categoryName].
  static List<FinanceTransaction> filter(
    List<FinanceTransaction> transactions, {
    TransactionType? type,
    String member = '',
    String query = '',
    String Function(String? categoryId)? categoryName,
  }) {
    final q = query.trim().toLowerCase();
    return [
      for (final t in transactions)
        if ((type == null || t.type == type) &&
            (member.isEmpty || t.createdBy == member) &&
            (q.isEmpty ||
                t.description.toLowerCase().contains(q) ||
                (t.notes?.toLowerCase().contains(q) ?? false) ||
                (categoryName?.call(t.categoryId).toLowerCase().contains(q) ?? false)))
          t,
    ];
  }

  /// First month with entries (for the month picker), or [today]'s month.
  static YearMonth firstMonth(List<FinanceTransaction> transactions, DateTime today) {
    var first = YearMonth.fromDate(today);
    for (final t in transactions) {
      final m = YearMonth.fromDate(t.occurredAt);
      if (m.compareTo(first) < 0) first = m;
    }
    return first;
  }
}
