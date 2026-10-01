import '../../core/time/year_month.dart';
import '../entities/entities.dart';
import '../finance/budget_calculator.dart';

enum ReminderTiming { dayBefore, sameDay }

/// A notification to show, with English text keys (translated by the caller)
/// and `{placeholder}` args. Never contains amounts (privacy).
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    this.args = const {},
    required this.when,
  });

  final int id;
  final String title;
  final String body;
  final Map<String, String> args;
  final DateTime when;
}

/// Plans payment reminders for recurring items. Pure: same inputs → same
/// notifications and ids, so the caller can cancel everything in
/// [firstId]..[lastId] and reschedule.
abstract final class ReminderPlanner {
  static const firstId = 1000;
  static const lastId = 1999;
  static const maxCount = 20;
  static const horizon = Duration(days: 30);
  static const hour = 9;

  static List<PlannedNotification> plan({
    required List<RecurringItem> items,
    required DateTime now,
    required ReminderTiming timing,
  }) {
    final dayBefore = timing == ReminderTiming.dayBefore;
    final until = now.add(horizon);
    final today = dateOnly(now);
    final found = <(DateTime, RecurringItem)>[];
    for (final item in items) {
      if (!item.isActive) continue;
      final dues = item.rule.occurrencesBetween(
        item.anchorDate,
        from: today,
        // +2 days: a due date just past the horizon can still have its
        // day-before reminder inside it.
        toExclusive: DateTime(today.year, today.month, today.day + horizon.inDays + 2),
        endDate: item.endDate,
      );
      for (final due in dues) {
        final when = DateTime(due.year, due.month, due.day - (dayBefore ? 1 : 0), hour);
        if (when.isAfter(now) && !when.isAfter(until)) found.add((when, item));
      }
    }
    found.sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$2.id.compareTo(b.$2.id);
    });
    return [
      for (var i = 0; i < found.length && i < maxCount; i++)
        PlannedNotification(
          id: firstId + i,
          title: 'Upcoming payment',
          body: dayBefore ? '{name} is due tomorrow' : '{name} is due today',
          args: {'name': found[i].$2.name},
          when: found[i].$1,
        ),
    ];
  }
}

/// A budget that crossed into nearLimit/overBudget this month.
class BudgetAlert {
  const BudgetAlert({required this.key, required this.id, required this.categoryId, required this.status});

  /// `yyyymm:<categoryId|global>:<status>` — remembered so it is shown once.
  final String key;
  final int id;

  /// Null for the global monthly budget.
  final String? categoryId;
  final BudgetStatus status;

  String get title => 'Budget alert';

  /// English key; `{name}` = category name for category budgets.
  String get body => switch ((categoryId == null, status)) {
        (true, BudgetStatus.overBudget) => 'You\'re over your monthly budget',
        (true, _) => 'You\'re close to your monthly budget',
        (false, BudgetStatus.overBudget) => 'You\'re over your {name} budget',
        (false, _) => 'You\'re close to your {name} budget',
      };
}

abstract final class BudgetAlertPlanner {
  static const firstId = 2000;

  /// Alerts in [report] (for [month]) not yet in [shown].
  static List<BudgetAlert> newAlerts({
    required MonthlyBudgetReport report,
    required YearMonth month,
    required Set<String> shown,
  }) {
    final entries = <(String?, BudgetProgress)>[
      if (report.global case final g?) (null, g),
      for (final e in report.byCategory.entries) (e.key, e.value),
    ];
    return [
      for (final (categoryId, progress) in entries)
        if (progress.status != BudgetStatus.onTrack)
          if ('${month.key}:${categoryId ?? 'global'}:${progress.status.name}' case final key
              when !shown.contains(key))
            BudgetAlert(key: key, id: idFor(key), categoryId: categoryId, status: progress.status),
    ];
  }

  /// Keeps only [month]'s keys so the stored set does not grow forever.
  static Set<String> prune(Set<String> shown, YearMonth month) =>
      shown.where((k) => k.startsWith('${month.key}:')).toSet();

  /// Stable across runs (unlike String.hashCode): 2000..2999.
  static int idFor(String key) =>
      firstId + key.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff) % 1000;
}
