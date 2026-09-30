import 'package:intl/intl.dart';

import 'currency.dart';

/// Immutable monetary amount stored as an integer number of minor units
/// (e.g. cents). Never use `double` for money arithmetic.
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  const Money.zero(this.currency) : minor = 0;

  /// Creates a value from whole units, e.g. `Money.fromMajor(12, usd)` → $12.00.
  factory Money.fromMajor(int major, Currency currency) =>
      Money(major * currency.minorPerMajor, currency);

  final int minor;
  final Currency currency;

  /// Largest accepted amount (100 billion major units). Keeps SQLite SUM()
  /// and all arithmetic far from 64-bit overflow.
  static const int maxMinor = 10000000000000;
  static const int _maxWholeDigits = 12;

  /// True when the absolute amount is within [maxMinor].
  bool get isWithinLimits => minor.abs() <= maxMinor;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  Money abs() => Money(minor.abs(), currency);

  Money timesInt(int factor) => Money(minor * factor, currency);

  /// Multiplies by the rational number [numerator]/[denominator] using
  /// integer math, rounding half away from zero.
  Money timesRatio(int numerator, int denominator) =>
      Money(divideRounded(minor * numerator, denominator), currency);

  /// Fraction of [total] this amount represents (0.5 = 50 %).
  /// Returns 0 when [total] is zero. Result is for display/thresholds only.
  double ratioOf(Money total) {
    _assertSameCurrency(total);
    if (total.minor == 0) return 0;
    return minor / total.minor;
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  static Money sum(Iterable<Money> values, Currency currency) =>
      values.fold(Money.zero(currency), (acc, m) => acc + m);

  /// Formats for display, e.g. `$1,234.50`. Uses the device locale by default.
  String format({String? locale, bool showSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: locale,
      name: currency.code,
      symbol: showSymbol ? currency.symbol : '',
      decimalDigits: currency.decimalDigits,
    );
    // Conversion to double is for display only; values up to 2^53 are exact.
    return formatter.format(minor / currency.minorPerMajor).trim();
  }

  /// Plain decimal representation without grouping, e.g. `1234.50`.
  /// Useful for text fields and CSV export.
  String toDecimalString() {
    final factor = currency.minorPerMajor;
    final sign = minor < 0 ? '-' : '';
    final absMinor = minor.abs();
    final whole = absMinor ~/ factor;
    if (currency.decimalDigits == 0) return '$sign$whole';
    final fraction =
        (absMinor % factor).toString().padLeft(currency.decimalDigits, '0');
    return '$sign$whole.$fraction';
  }

  /// Parses user input such as `12`, `12.5`, `1,234.56` or `1.234,56`
  /// into minor units without floating point. Returns null if invalid.
  static Money? tryParse(String input, Currency currency) {
    var text = input.trim().replaceAll(RegExp(r'[\s ]'), '');
    text = text.replaceAll(currency.symbol, '');
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }
    if (!RegExp(r'^[0-9.,]+$').hasMatch(text)) return null;

    // The last separator is decimal if followed by 1..decimalDigits digits.
    final lastSep = text.lastIndexOf(RegExp('[.,]'));
    String wholePart = text;
    String fractionPart = '';
    if (lastSep >= 0) {
      final after = text.substring(lastSep + 1);
      final looksDecimal = after.isNotEmpty &&
          after.length <= currency.decimalDigits &&
          // "1,234" with 3 digits after is grouping, not decimals.
          !(after.length == 3 && currency.decimalDigits < 3);
      if (looksDecimal) {
        wholePart = text.substring(0, lastSep);
        fractionPart = after;
      } else if (after.isEmpty) {
        wholePart = text.substring(0, lastSep); // "12." while typing
      }
    }
    // Grouping separators must split exact thousands ("1,234,567").
    if (wholePart.contains(RegExp('[.,]')) &&
        !RegExp(r'^[1-9]\d{0,2}([.,]\d{3})*$').hasMatch(wholePart)) {
      return null;
    }
    wholePart = wholePart.replaceAll(RegExp('[.,]'), '');
    if (wholePart.isEmpty) wholePart = '0';
    if (wholePart.length > _maxWholeDigits) return null;

    final whole = int.tryParse(wholePart);
    if (whole == null) return null;
    final fraction = fractionPart.isEmpty
        ? 0
        : int.parse(fractionPart.padRight(currency.decimalDigits, '0'));

    final minor = whole * currency.minorPerMajor + fraction;
    if (minor > maxMinor) return null;
    return Money(negative ? -minor : minor, currency);
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Currency mismatch: ${currency.code} vs ${other.currency.code}. '
        'Conversion is not supported.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '${currency.code} ${toDecimalString()}';
}

/// Integer division rounding half away from zero.
int divideRounded(int numerator, int denominator) {
  if (denominator == 0) throw ArgumentError('Division by zero');
  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs();
  final d = denominator.abs();
  final q = (n + d ~/ 2) ~/ d;
  return negative ? -q : q;
}
