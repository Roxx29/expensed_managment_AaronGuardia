import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';

enum BudgetStatus { onTrack, nearLimit, overBudget }

class BudgetProgress {
  const BudgetProgress({
    required this.budgeted,
    required this.spent,
    required this.remaining,
    required this.ratio,
    required this.status,
  });

  final Money budgeted;
  final Money spent;

  /// Negative when over budget.
  final Money remaining;

  /// spent / budgeted (1.0 = 100 %). May exceed 1.
  final double ratio;
  final BudgetStatus status;
}

class MonthlyBudgetReport {
  const MonthlyBudgetReport({required this.global, required this.byCategory});

  /// Null when no global budget applies to the month.
  final BudgetProgress? global;

  /// Keyed by category id.
  final Map<String, BudgetProgress> byCategory;

  /// Money allocated to category budgets; null when there are none.
  Money? get allocated => byCategory.isEmpty
      ? null
      : byCategory.values.map((p) => p.budgeted).reduce((a, b) => a + b);

  /// Global budget not yet allocated to categories (negative = over-allocated).
  Money? get unallocated {
    final g = global;
    if (g == null) return null;
    return g.budgeted - (allocated ?? Money.zero(g.budgeted.currency));
  }

  bool get hasAlerts =>
      (global != null && global!.status != BudgetStatus.onTrack) ||
      byCategory.values.any((p) => p.status != BudgetStatus.onTrack);
}

abstract final class BudgetCalculator {
  /// Share of a budget at which the user is warned.
  static const double warningThreshold = 0.8;

  static BudgetProgress progress({
    required Money budgeted,
    required Money spent,
  }) {
    final ratio = budgeted.isZero
        ? (spent.isPositive ? double.infinity : 0.0)
        : spent.ratioOf(budgeted);
    final BudgetStatus status;
    if (spent > budgeted) {
      status = BudgetStatus.overBudget;
    } else if (ratio >= warningThreshold && !budgeted.isZero) {
      status = BudgetStatus.nearLimit;
    } else {
      status = BudgetStatus.onTrack;
    }
    return BudgetProgress(
      budgeted: budgeted,
      spent: spent,
      remaining: budgeted - spent,
      ratio: ratio,
      status: status,
    );
  }

  /// Progress of every budget that applies to [month]. Only expenses in
  /// [currency] count (no conversion in the MVP).
  static MonthlyBudgetReport monthlyReport({
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    required YearMonth month,
    required Currency currency,
  }) {
    var totalSpent = Money.zero(currency);
    final spentByCategory = <String, Money>{};
    for (final t in transactions) {
      if (t.type != TransactionType.expense ||
          t.amount.currency != currency ||
          !month.contains(t.occurredAt)) {
        continue;
      }
      totalSpent += t.amount;
      final categoryId = t.categoryId;
      if (categoryId != null) {
        spentByCategory[categoryId] =
            (spentByCategory[categoryId] ?? Money.zero(currency)) + t.amount;
      }
    }

    BudgetProgress? global;
    final byCategory = <String, BudgetProgress>{};
    for (final b in budgets) {
      if (!b.appliesTo(month) || b.amount.currency != currency) continue;
      final categoryId = b.categoryId;
      if (categoryId == null) {
        global = progress(budgeted: b.amount, spent: totalSpent);
      } else {
        byCategory[categoryId] = progress(
          budgeted: b.amount,
          spent: spentByCategory[categoryId] ?? Money.zero(currency),
        );
      }
    }
    return MonthlyBudgetReport(global: global, byCategory: byCategory);
  }
}
