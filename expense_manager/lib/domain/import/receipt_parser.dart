/// Extracts total, date and merchant from OCR'd receipt text (pure Dart).
library;

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import 'statement_import.dart' show validDate;

class ReceiptData {
  const ReceiptData({this.total, this.date, this.merchant});

  final Money? total;
  final DateTime? date;
  final String? merchant;

  bool get isEmpty => total == null && date == null && merchant == null;
}

// Amounts must have 2 decimals ("25.50", "1.234,56"); dates like
// "01.09.2026" are rejected by the look-arounds.
final _money = RegExp(r'(?<![\d.,])(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}(?![.,]?\d)');

/// Keyword groups, strongest first. Matched on upper-cased, accent-free text.
final _totalKeywords = [
  RegExp(r'GRAND TOTAL|TOTAL A PAGAR|TOTAL DUE|AMOUNT DUE|BALANCE DUE|IMPORTE TOTAL|TOTAL GENERAL'),
  RegExp(r'\bTOTAL\b'),
  RegExp(r'\bIMPORTE\b|\bAMOUNT\b'),
];
final _subtotal = RegExp(r'SUB\s*-?\s*TOTAL');

const _months = {
  'JAN': 1, 'ENE': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'ABR': 4, 'MAY': 5, 'JUN': 6,
  'JUL': 7, 'AUG': 8, 'AGO': 8, 'SEP': 9, 'SET': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12, 'DIC': 12,
};
final _numericDate = RegExp(r'(?<!\d)(\d{1,4})[/.\-](\d{1,2})[/.\-](\d{2,4})(?!\d)');
final _dayMonthName = RegExp(r'(?<!\d)(\d{1,2})[\s\-/]+([A-Z]{3})[A-Z]*\.?[\s\-/,]+(\d{4})(?!\d)');
final _monthNameDay = RegExp(r'\b([A-Z]{3})[A-Z]*\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)');

final _merchantNoise = RegExp(
  r'TICKET|FACTURA|RECIBO|RECEIPT|INVOICE|WELCOME|BIENVENID|GRACIAS|THANK|\bRFC\b|\bNIF\b|\bCIF\b|\bRUC\b|\bTEL|PHONE|WWW|HTTP|@',
);

/// Parses recognized [lines] (top to bottom). Dates after [now] are ignored;
/// ambiguous `03/04/2026` is day-first unless [preferMonthFirst].
ReceiptData parseReceipt(
  List<String> lines,
  Currency currency, {
  required DateTime now,
  bool preferMonthFirst = false,
}) {
  final clean = [for (final l in lines) l.trim()]..removeWhere((l) => l.isEmpty);
  final upper = [for (final l in clean) _fold(l.toUpperCase())];
  return ReceiptData(
    total: _total(upper, currency),
    date: _date(upper, now, preferMonthFirst),
    merchant: _merchant(clean, upper),
  );
}

List<Money> _amounts(String line, Currency currency) => [
      for (final m in _money.allMatches(line)) ?Money.tryParse(m[0]!, currency),
    ].where((m) => m.isPositive && m.isWithinLimits).toList();

Money? _largest(Iterable<Money> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a >= b ? a : b);

// ponytail: keyword + largest-number heuristic; when OCR splits the label and
// the amount into far-apart blocks we fall back to the largest number, which
// can be the cash tendered. Use block bounding boxes if that proves common.
Money? _total(List<String> upper, Currency currency) {
  for (final keyword in _totalKeywords) {
    final found = <Money>[];
    for (var i = 0; i < upper.length; i++) {
      if (!keyword.hasMatch(upper[i]) || _subtotal.hasMatch(upper[i])) continue;
      var amounts = _amounts(upper[i], currency);
      // Label and amount often come out on separate lines (allow "EUR", "USD").
      if (amounts.isEmpty && i + 1 < upper.length && RegExp('[A-Z]').allMatches(upper[i + 1]).length <= 3) {
        amounts = _amounts(upper[i + 1], currency);
      }
      if (amounts.isNotEmpty) found.add(amounts.last);
    }
    final best = _largest(found);
    if (best != null) return best;
  }
  return _largest(upper.expand((l) => _amounts(l, currency)));
}

DateTime? _date(List<String> upper, DateTime now, bool preferMonthFirst) {
  final latest = DateTime(now.year, now.month, now.day);
  for (final line in upper) {
    final candidates = <DateTime?>[];
    for (final m in _numericDate.allMatches(line)) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      var c = int.parse(m[3]!);
      if (m[1]!.length == 4) {
        candidates.add(validDate(a, b, c)); // yyyy-MM-dd
        continue;
      }
      if (m[1]!.length > 2) continue;
      if (m[3]!.length == 2) c += 2000;
      if (m[3]!.length == 3) continue;
      final dayFirst = validDate(c, b, a);
      final monthFirst = validDate(c, a, b);
      candidates.addAll(preferMonthFirst ? [monthFirst, dayFirst] : [dayFirst, monthFirst]);
    }
    for (final m in _dayMonthName.allMatches(line)) {
      final month = _months[m[2]];
      if (month != null) candidates.add(validDate(int.parse(m[3]!), month, int.parse(m[1]!)));
    }
    for (final m in _monthNameDay.allMatches(line)) {
      final month = _months[m[1]];
      if (month != null) candidates.add(validDate(int.parse(m[3]!), month, int.parse(m[2]!)));
    }
    for (final d in candidates) {
      if (d != null && !d.isAfter(latest) && d.year >= 2000) return d;
    }
  }
  return null;
}

String? _merchant(List<String> clean, List<String> upper) {
  for (var i = 0; i < clean.length && i < 6; i++) {
    final line = upper[i];
    final letters = RegExp('[A-Z]').allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    if (letters < 3 || digits > letters || _merchantNoise.hasMatch(line)) continue;
    if (_money.hasMatch(line) || _numericDate.hasMatch(line)) continue;
    final name = clean[i].replaceAll(RegExp(r'\s+'), ' ');
    return name.length > 60 ? name.substring(0, 60).trim() : name;
  }
  return null;
}

/// Removes Spanish accents so keywords match `IMPORTE`/`DÉBITO` alike.
String _fold(String s) {
  const from = 'ÁÉÍÓÚÜÑ';
  const to = 'AEIOUUN';
  final out = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}
