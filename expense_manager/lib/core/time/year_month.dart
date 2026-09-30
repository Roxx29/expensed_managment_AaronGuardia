/// A calendar month, e.g. 2026-09. Stored in the DB as `yyyymm` (202609).
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month)
      : assert(month >= 1 && month <= 12, 'month must be 1..12');

  factory YearMonth.fromDate(DateTime date) => YearMonth(date.year, date.month);

  factory YearMonth.now() => YearMonth.fromDate(DateTime.now());

  factory YearMonth.fromKey(int key) {
    final month = key % 100;
    if (month < 1 || month > 12) throw ArgumentError.value(key, 'key', 'invalid yyyymm');
    return YearMonth(key ~/ 100, month);
  }

  final int year;
  final int month;

  /// Compact integer key: 202609.
  int get key => year * 100 + month;

  /// First instant of the month (local time, inclusive).
  DateTime get start => DateTime(year, month);

  /// First instant of the next month (exclusive end).
  DateTime get endExclusive => DateTime(year, month + 1);

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  YearMonth get previous => addMonths(-1);
  YearMonth get next => addMonths(1);

  YearMonth addMonths(int delta) {
    final zeroBased = year * 12 + (month - 1) + delta;
    return YearMonth(zeroBased ~/ 12, zeroBased % 12 + 1);
  }

  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(endExclusive);

  @override
  int compareTo(YearMonth other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is YearMonth && other.key == key;

  @override
  int get hashCode => key;

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

/// Clock abstraction so time-dependent logic is testable.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

/// Strips the time component.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
