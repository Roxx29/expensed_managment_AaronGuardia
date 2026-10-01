import 'package:intl/intl.dart';

import '../entities/entities.dart';

final _dateFormat = DateFormat('yyyy-MM-dd HH:mm', 'en_US');

/// Cells starting with these are run as formulas by spreadsheet apps.
final _formulaStart = RegExp('^[=+\\-@\t\r]');
final _needsQuotes = RegExp('[",\r\n]');

/// RFC 4180 CSV (CRLF line ends) of [transactions], one row each, in the
/// given order. Text cells are defused against CSV/formula injection.
String transactionsToCsv(
  List<FinanceTransaction> transactions, {
  required String Function(String? categoryId) categoryName,
  String Function(String? id)? paymentMethodName,
}) {
  final buffer = StringBuffer('date,type,amount,currency,description,category,payment_method,notes\r\n');
  for (final t in transactions) {
    buffer
      ..writeAll([
        _text(_dateFormat.format(t.occurredAt.toLocal())),
        _text(t.type.name),
        // Numeric, produced by us: never prefixed, so spreadsheets read a number.
        t.amount.toDecimalString(),
        _text(t.amount.currency.code),
        _text(t.description),
        _text(categoryName(t.categoryId)),
        _text(paymentMethodName?.call(t.paymentMethodId) ?? ''),
        _text(t.notes ?? ''),
      ], ',')
      ..write('\r\n');
  }
  return buffer.toString();
}

String _text(String value) {
  final safe = _formulaStart.hasMatch(value) ? "'$value" : value;
  return _needsQuotes.hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}
