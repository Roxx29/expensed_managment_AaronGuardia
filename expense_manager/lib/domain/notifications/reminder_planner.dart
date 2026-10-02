import '../../core/time/year_month.dart';
import '../entities/entities.dart';
import '../finance/budget_calculator.dart';

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
  static const defaultHour = 9;

  /// Reminder choices, in days before the due date (0 = same day).
  static const dayOptions = [7, 3, 1, 0];

  /// Stored as e.g. `7,1`. Old values `day_before` / `same_day` still work.
  static Set<int> parseDays(String? value) {
    if (value == 'same_day') return {0};
    final days = (value ?? '').split(',').map(int.tryParse).whereType<int>().where(dayOptions.contains).toSet();
    return days.isEmpty ? {1} : days;
  }

  static String encodeDays(Set<int> days) => (days.toList()..sort()).join(',');

  /// Hour of day (0–23) the reminders fire; [defaultHour] when unset/invalid.
  static int parseHour(String? value) {
    final h = int.tryParse(value ?? '');
    return h != null && h >= 0 && h <= 23 ? h : defaultHour;
  }

  static List<PlannedNotification> plan({
    required List<RecurringItem> items,
    required DateTime now,
    required Set<int> daysBefore,
    int hour = defaultHour,
  }) {
    final until = now.add(horizon);
    final today = dateOnly(now);
    final maxDays = daysBefore.fold(0, (a, b) => a > b ? a : b);
    final found = <(DateTime, int, RecurringItem)>[];
    for (final item in items) {
      if (!item.isActive) continue;
      final dues = item.rule.occurrencesBetween(
        item.anchorDate,
        from: today,
        // A due date past the horizon can still have an earlier reminder inside it.
        toExclusive: DateTime(today.year, today.month, today.day + horizon.inDays + maxDays + 1),
        endDate: item.endDate,
      );
      for (final due in dues) {
        for (final days in daysBefore) {
          final when = DateTime(due.year, due.month, due.day - days, hour);
          if (when.isAfter(now) && !when.isAfter(until)) found.add((when, days, item));
        }
      }
    }
    found.sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$3.id.compareTo(b.$3.id);
    });
    return [
      for (var i = 0; i < found.length && i < maxCount; i++)
        PlannedNotification(
          id: firstId + i,
          title: 'Upcoming payment',
          body: switch (found[i].$2) {
            0 => '{name} is due today',
            1 => '{name} is due tomorrow',
            _ => '{name} is due in {days} days',
          },
          args: {'name': found[i].$3.name, 'days': '${found[i].$2}'},
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
