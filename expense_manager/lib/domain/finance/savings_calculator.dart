import '../../core/money/money.dart';
import '../entities/entities.dart';

class SavingsProgress {
  const SavingsProgress({
    required this.goal,
    required this.saved,
    this.suggestedMonthly,
    this.isOverdue = false,
  });

  final SavingsGoal goal;

  /// Deposits − withdrawals for this goal, in the goal's currency.
  final Money saved;

  /// Monthly amount that reaches the target by its date; null when there is
  /// no target date, the goal is reached, or the date has passed.
  final Money? suggestedMonthly;

  /// Target date is before today and the goal is not reached.
  final bool isOverdue;

  Money get target => goal.target;

  /// Never negative.
  Money get remaining => saved >= target ? Money.zero(target.currency) : target - saved;

  /// saved / target, clamped to 0..1 (for progress bars).
  double get ratio => saved.ratioOf(target).clamp(0.0, 1.0).toDouble();

  bool get isReached => saved >= target;
}

abstract final class SavingsCalculator {
  /// False when deleting [tx] would leave its goal below zero: a deposit whose
  /// money was already withdrawn must be kept until the withdrawals go first.
  static bool canDelete(FinanceTransaction tx, List<FinanceTransaction> all) {
    final id = tx.savingsGoalId;
    if (id == null || tx.type != TransactionType.savings) return true;
    var saved = 0;
    for (final t in all) {
      if (t.savingsGoalId != id || t.amount.currency != tx.amount.currency) continue;
      saved += switch (t.type) {
        TransactionType.savings => t.amount.minor,
        TransactionType.savingsWithdrawal => -t.amount.minor,
        TransactionType.expense || TransactionType.income || TransactionType.transfer => 0,
      };
    }
    return saved - tx.amount.minor >= 0;
  }

  /// Progress for every goal in [goals]. Transactions in another currency than
  /// the goal are ignored (no currency conversion).
  static List<SavingsProgress> progress(
    List<SavingsGoal> goals,
    List<FinanceTransaction> transactions, {
    required DateTime today,
  }) {
    final currencyById = {for (final g in goals) g.id: g.target.currency};
    final savedMinor = <String, int>{};
    for (final t in transactions) {
      final id = t.savingsGoalId;
      if (id == null) continue;
      final sign = switch (t.type) {
        TransactionType.savings => 1,
        TransactionType.savingsWithdrawal => -1,
        TransactionType.expense || TransactionType.income || TransactionType.transfer => 0,
      };
      if (sign == 0) continue;
      if (currencyById[id] != t.amount.currency) continue;
      savedMinor[id] = (savedMinor[id] ?? 0) + sign * t.amount.minor;
    }

    return [
      for (final goal in goals) _progress(goal, Money(savedMinor[goal.id] ?? 0, goal.target.currency), today),
    ];
  }

  static SavingsProgress _progress(SavingsGoal goal, Money saved, DateTime today) {
    final targetDate = goal.targetDate;
    if (targetDate == null || saved >= goal.target) return SavingsProgress(goal: goal, saved: saved);
    final day = DateTime(today.year, today.month, today.day);
    final due = DateTime(targetDate.year, targetDate.month, targetDate.day);
    if (due.isBefore(day)) return SavingsProgress(goal: goal, saved: saved, isOverdue: true);

    // Monthly deposits on today's day-of-month up to the target date, inclusive.
    final months = (due.year - day.year) * 12 + due.month - day.month + (due.day >= day.day ? 1 : 0);
    final remaining = (goal.target - saved).minor;
    final perMonth = (remaining + months - 1) ~/ months; // round up so the target is reached
    return SavingsProgress(goal: goal, saved: saved, suggestedMonthly: Money(perMonth, goal.target.currency));
  }
}
