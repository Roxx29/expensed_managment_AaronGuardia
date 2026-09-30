import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';

/// Turns due occurrences of recurring expenses/subscriptions into expense
/// transactions. IDs are deterministic (`<itemId>_<yyyymmdd>`), so posting is
/// idempotent and a generated transaction the user deleted is never re-created
/// (the repository inserts only missing IDs, soft-deleted rows included).
abstract final class RecurringPoster {
  // ponytail: only the last year is back-filled, so an old anchor date can't
  // create thousands of rows. Raise if users need longer history.
  static const maxBackfillDays = 366;

  /// Returns [updated] with `postedFrom` set to [today] when it resumes a
  /// paused item or changes its schedule, so the paused period and the old
  /// schedule's dates are not charged (their IDs would differ). New items keep
  /// `postedFrom == null`: their past charges from the first date are posted.
  static RecurringItem withPostingStart(RecurringItem? previous, RecurringItem updated, DateTime today) {
    if (previous == null) return updated;
    final resumed = !previous.isActive && updated.isActive;
    final rescheduled = previous.anchorDate != updated.anchorDate ||
        previous.rule.frequency != updated.rule.frequency ||
        previous.rule.interval != updated.rule.interval;
    return resumed || rescheduled ? updated.copyWith(postedFrom: dateOnly(today)) : updated;
  }

  static String occurrenceId(String itemId, DateTime date) =>
      '${itemId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static List<FinanceTransaction> dueTransactions({
    required List<RecurringItem> items,
    required DateTime today,
  }) {
    final end = DateTime(today.year, today.month, today.day + 1); // include today
    final earliest = DateTime(today.year, today.month, today.day - maxBackfillDays);
    DateTime latest(List<DateTime?> dates) =>
        dates.whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
    return [
      for (final item in items)
        if (item.isActive)
          for (final date in item.rule.occurrencesBetween(
            item.anchorDate,
            from: latest([item.anchorDate, earliest, item.postedFrom]),
            toExclusive: end,
            endDate: item.endDate,
          ))
            FinanceTransaction(
              id: occurrenceId(item.id, date),
              type: TransactionType.expense,
              amount: item.amount,
              occurredAt: date,
              description: item.name,
              categoryId: item.categoryId,
              paymentMethodId: item.paymentMethodId,
              recurringItemId: item.id,
            ),
    ];
  }

  /// Monthly and yearly cost of the active items of [kind] (all kinds if null).
  static ({Money monthly, Money yearly, int count}) totals(
    List<RecurringItem> items,
    Currency currency, {
    RecurringKind? kind,
  }) {
    final active = items
        .where((i) => i.isActive && i.amount.currency == currency && (kind == null || i.kind == kind))
        .toList();
    return (
      monthly: Money.sum(active.map((i) => i.monthlyCost), currency),
      yearly: Money.sum(active.map((i) => i.yearlyCost), currency),
      count: active.length,
    );
  }
}

