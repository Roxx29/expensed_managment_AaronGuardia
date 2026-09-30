import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/enums.dart';
import 'package:expense_manager/domain/finance/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;

  group('RecurrenceRule.occurrenceAt', () {
    test('monthly clamps to end of shorter months and restores anchor day', () {
      const rule = RecurrenceRule(Frequency.monthly);
      final anchor = DateTime(2026, 1, 31);
      expect(rule.occurrenceAt(anchor, 1), DateTime(2026, 2, 28));
      expect(rule.occurrenceAt(anchor, 2), DateTime(2026, 3, 31));
      expect(rule.occurrenceAt(anchor, 3), DateTime(2026, 4, 30));
    });

    test('yearly handles Feb 29 anchor', () {
      const rule = RecurrenceRule(Frequency.yearly);
      expect(rule.occurrenceAt(DateTime(2024, 2, 29), 1), DateTime(2025, 2, 28));
      expect(rule.occurrenceAt(DateTime(2024, 2, 29), 4), DateTime(2028, 2, 29));
    });

    test('custom interval: every 2 weeks', () {
      const rule = RecurrenceRule(Frequency.weekly, interval: 2);
      expect(rule.occurrenceAt(DateTime(2026, 9, 1), 1), DateTime(2026, 9, 15));
    });
  });

  group('RecurrenceRule.nextOccurrence', () {
    test('returns anchor when it is on/after the reference date', () {
      const rule = RecurrenceRule(Frequency.monthly);
      expect(
        rule.nextOccurrence(DateTime(2026, 10, 5), onOrAfter: DateTime(2026, 9, 30)),
        DateTime(2026, 10, 5),
      );
    });

    test('skips past occurrences', () {
      const rule = RecurrenceRule(Frequency.monthly);
      expect(
        rule.nextOccurrence(DateTime(2026, 1, 15), onOrAfter: DateTime(2026, 9, 30)),
        DateTime(2026, 10, 15),
      );
    });

    test('same day counts as next', () {
      const rule = RecurrenceRule(Frequency.daily, interval: 3);
      expect(
        rule.nextOccurrence(DateTime(2026, 9, 1), onOrAfter: DateTime(2026, 9, 10)),
        DateTime(2026, 9, 10),
      );
    });

    test('returns null after end date', () {
      const rule = RecurrenceRule(Frequency.monthly);
      expect(
        rule.nextOccurrence(
          DateTime(2026, 1, 15),
          onOrAfter: DateTime(2026, 9, 30),
          endDate: DateTime(2026, 9, 1),
        ),
        isNull,
      );
    });
  });

  test('occurrencesBetween lists weekly dates in range', () {
    const rule = RecurrenceRule(Frequency.weekly);
    final dates = rule.occurrencesBetween(
      DateTime(2026, 9, 1),
      from: DateTime(2026, 9, 10),
      toExclusive: DateTime(2026, 9, 30),
    );
    expect(dates, [
      DateTime(2026, 9, 15),
      DateTime(2026, 9, 22),
      DateTime(2026, 9, 29),
    ]);
  });

  group('cost estimation', () {
    test('monthly item', () {
      const rule = RecurrenceRule(Frequency.monthly);
      const amount = Money(1599, usd);
      expect(rule.monthlyCost(amount).minor, 1599);
      expect(rule.yearlyCost(amount).minor, 19188);
    });

    test('yearly item spreads across 12 months', () {
      const rule = RecurrenceRule(Frequency.yearly);
      expect(rule.monthlyCost(const Money(12000, usd)).minor, 1000);
    });

    test('weekly item uses 52 weeks per year', () {
      const rule = RecurrenceRule(Frequency.weekly);
      expect(rule.yearlyCost(const Money(1000, usd)).minor, 52000);
      expect(rule.monthlyCost(const Money(1000, usd)).minor, 4333);
    });

    test('every 3 months', () {
      const rule = RecurrenceRule(Frequency.monthly, interval: 3);
      expect(rule.yearlyCost(const Money(3000, usd)).minor, 12000);
      expect(rule.monthlyCost(const Money(3000, usd)).minor, 1000);
    });
  });

  test('interval must be positive', () {
    expect(() => RecurrenceRule(Frequency.daily, interval: 0), throwsA(isA<AssertionError>()));
  });
}
