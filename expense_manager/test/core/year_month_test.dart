import 'package:expense_manager/core/time/year_month.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('addMonths crosses year boundaries', () {
    expect(const YearMonth(2026, 1).addMonths(-1), const YearMonth(2025, 12));
    expect(const YearMonth(2026, 12).next, const YearMonth(2027, 1));
    expect(const YearMonth(2026, 3).addMonths(-15), const YearMonth(2024, 12));
  });

  test('key round-trips', () {
    expect(const YearMonth(2026, 9).key, 202609);
    expect(YearMonth.fromKey(202609), const YearMonth(2026, 9));
  });

  test('contains is start-inclusive and end-exclusive', () {
    const sept = YearMonth(2026, 9);
    expect(sept.contains(DateTime(2026, 9, 1)), isTrue);
    expect(sept.contains(DateTime(2026, 9, 30, 23, 59)), isTrue);
    expect(sept.contains(DateTime(2026, 10, 1)), isFalse);
  });

  test('daysInMonth handles leap years', () {
    expect(const YearMonth(2028, 2).daysInMonth, 29);
    expect(const YearMonth(2026, 2).daysInMonth, 28);
  });
}
