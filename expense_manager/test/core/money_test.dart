import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;

  group('Money arithmetic', () {
    test('adds and subtracts minor units exactly', () {
      const a = Money(1010, usd); // 10.10
      const b = Money(2020, usd); // 20.20
      expect((a + b).minor, 3030);
      expect((b - a).minor, 1010);
    });

    test('avoids floating point drift (0.1 + 0.2)', () {
      final result = const Money(10, usd) + const Money(20, usd);
      expect(result, const Money(30, usd));
      expect(result.toDecimalString(), '0.30');
    });

    test('throws on currency mismatch', () {
      expect(
        () => const Money(100, usd) + const Money(100, Currency.eur),
        throwsArgumentError,
      );
    });

    test('timesRatio rounds half away from zero', () {
      expect(const Money(100, usd).timesRatio(1, 3).minor, 33);
      expect(const Money(1, usd).timesRatio(1, 2).minor, 1);
      expect(const Money(-1, usd).timesRatio(1, 2).minor, -1);
    });

    test('ratioOf returns 0 for a zero total', () {
      expect(const Money(50, usd).ratioOf(const Money.zero(usd)), 0);
      expect(const Money(50, usd).ratioOf(const Money(200, usd)), 0.25);
    });

    test('sum of empty iterable is zero', () {
      expect(Money.sum(const [], usd), const Money.zero(usd));
    });

    test('fromMajor multiplies by minor factor', () {
      expect(Money.fromMajor(12, usd).minor, 1200);
    });
  });

  group('Money.tryParse', () {
    final cases = <String, int?>{
      '12': 1200,
      '12.5': 1250,
      '12.50': 1250,
      '.5': 50,
      '1,234.56': 123456,
      '1.234,56': 123456,
      '1,234': 123400,
      r'$ 7.05': 705,
      '-3.10': -310,
      '12.345': 1234500, // 3 digits after separator → grouping
      '': null,
      'abc': null,
      '12a': null,
      '12.': 1200,
      '12.34.56': null, // malformed grouping
      '0.001': null, // too many decimals, not a valid grouping
      '1,23,456': null,
      '9999999999999': null, // above Money.maxMinor
    };
    cases.forEach((input, expected) {
      test('"$input" → $expected', () {
        expect(Money.tryParse(input, usd)?.minor, expected);
      });
    });

    test('handles B/. symbol for PAB', () {
      expect(Money.tryParse('B/. 10.25', Currency.pab)?.minor, 1025);
    });
  });

  group('formatting', () {
    test('toDecimalString pads cents', () {
      expect(const Money(5, usd).toDecimalString(), '0.05');
      expect(const Money(-12345, usd).toDecimalString(), '-123.45');
    });

    test('format uses currency symbol', () {
      expect(const Money(123456, usd).format(locale: 'en_US'), r'$1,234.56');
    });
  });

  group('divideRounded', () {
    test('rejects division by zero', () {
      expect(() => divideRounded(1, 0), throwsArgumentError);
    });
  });
}
