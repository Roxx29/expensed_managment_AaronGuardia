import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/enums.dart';

/// Scheduling + cost math for recurring expenses and subscriptions.
/// All dates are treated as calendar dates (time component ignored).
class RecurrenceRule {
  const RecurrenceRule(this.frequency, {this.interval = 1})
      : assert(interval > 0, 'interval must be positive');

  final Frequency frequency;

  /// Every [interval] units (2 + weekly = every two weeks).
  final int interval;

  bool get isCustom => interval != 1;

  /// Occurrences of this rule per year expressed as `perYear / interval`.
  /// Weekly uses 52 weeks and daily 365 days (documented approximation).
  int get _unitsPerYear => switch (frequency) {
        Frequency.daily => 365,
        Frequency.weekly => 52,
        Frequency.monthly => 12,
        Frequency.yearly => 1,
      };

  /// Estimated cost per month, rounded to minor units.
  Money monthlyCost(Money amount) =>
      amount.timesRatio(_unitsPerYear, 12 * interval);

  /// Estimated cost per year, rounded to minor units.
  Money yearlyCost(Money amount) => amount.timesRatio(_unitsPerYear, interval);

  /// The [index]-th occurrence (0 = anchor). Monthly/yearly keep the anchor's
  /// day-of-month, clamped to the length of shorter months.
  DateTime occurrenceAt(DateTime anchor, int index) {
    final a = dateOnly(anchor);
    final steps = index * interval;
    switch (frequency) {
      case Frequency.daily:
        return DateTime(a.year, a.month, a.day + steps);
      case Frequency.weekly:
        return DateTime(a.year, a.month, a.day + steps * 7);
      case Frequency.monthly:
        return _addMonthsClamped(a, steps);
      case Frequency.yearly:
        return _addMonthsClamped(a, steps * 12);
    }
  }

  /// First occurrence on or after [onOrAfter]; null if it would fall after
  /// [endDate] (inclusive).
  DateTime? nextOccurrence(
    DateTime anchor, {
    required DateTime onOrAfter,
    DateTime? endDate,
  }) {
    final target = dateOnly(onOrAfter);
    var index = _estimateIndex(dateOnly(anchor), target);
    // The estimate may undershoot by a step or two because of clamping.
    while (occurrenceAt(anchor, index).isBefore(target)) {
      index++;
    }
    final next = occurrenceAt(anchor, index);
    if (endDate != null && next.isAfter(dateOnly(endDate))) return null;
    return next;
  }

  /// All occurrences in `[from, toExclusive)`.
  List<DateTime> occurrencesBetween(
    DateTime anchor, {
    required DateTime from,
    required DateTime toExclusive,
    DateTime? endDate,
  }) {
    final result = <DateTime>[];
    var current = nextOccurrence(anchor, onOrAfter: from, endDate: endDate);
    while (current != null && current.isBefore(toExclusive)) {
      result.add(current);
      current = nextOccurrence(
        anchor,
        // Calendar arithmetic, not +24h, so DST changes cannot stall the loop.
        onOrAfter: DateTime(current.year, current.month, current.day + 1),
        endDate: endDate,
      );
    }
    return result;
  }

  int _estimateIndex(DateTime anchor, DateTime target) {
    if (!target.isAfter(anchor)) return 0;
    final int estimate;
    switch (frequency) {
      case Frequency.daily:
        estimate = _daysBetween(anchor, target) ~/ interval;
      case Frequency.weekly:
        estimate = _daysBetween(anchor, target) ~/ (7 * interval);
      case Frequency.monthly:
        estimate = _monthsBetween(anchor, target) ~/ interval;
      case Frequency.yearly:
        estimate = _monthsBetween(anchor, target) ~/ (12 * interval);
    }
    return estimate > 0 ? estimate - 1 : 0;
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  static int _monthsBetween(DateTime a, DateTime b) =>
      (b.year - a.year) * 12 + (b.month - a.month);

  static DateTime _addMonthsClamped(DateTime date, int months) {
    final ym = YearMonth.fromDate(date).addMonths(months);
    final day = date.day <= ym.daysInMonth ? date.day : ym.daysInMonth;
    return DateTime(ym.year, ym.month, day);
  }
}
