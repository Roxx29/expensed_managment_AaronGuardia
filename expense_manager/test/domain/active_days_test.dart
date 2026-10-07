import 'package:expense_manager/domain/usage/active_days.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dayKey is yyyymmdd', () {
    expect(dayKey(DateTime(2026, 10, 7, 23, 59)), 20261007);
    expect(dayKey(DateTime(2026, 1, 2)), 20260102);
  });

  test('adds today once, sorted, keeps the newest days', () {
    expect(addActiveDay([20261005, 20261007], DateTime(2026, 10, 7)), [20261005, 20261007]);
    expect(addActiveDay([20261007, 20261001], DateTime(2026, 10, 8)), [20261001, 20261007, 20261008]);
    expect(addActiveDay([1, 2, 3], DateTime(2026, 10, 8), keep: 2), [3, 20261008]);
  });

  test('parse ignores garbage', () {
    expect(parseActiveDays(null), isEmpty);
    expect(parseActiveDays('20261006, x,20261007'), [20261006, 20261007]);
  });
}
