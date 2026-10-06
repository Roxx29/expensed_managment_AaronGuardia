import 'package:intl/intl.dart';

import '../entities/entities.dart';

final _dateFormat = DateFormat('yyyy-MM-dd HH:mm', 'en_US');

/// Cells starting with these are run as formulas by spreadsheet apps.
// Also after leading spaces: some spreadsheet apps trim before evaluating.
final _formulaStart = RegExp(r'^\s*[=+\-@]|^[\t\r]');
final _needsQuotes = RegExp('[",\r\n]');

/// RFC 4180 CSV (CRLF line ends) of [transactions], one row each, in the
/// given order. Text cells are defused against CSV/formula injection.
String transactionsToCsv(
  List<FinanceTransaction> transactions, {
  required String Function(String? categoryId) categoryName,
  String Function(String? id)? paymentMethodName,
}) {
  final buffer = StringBuffer('date,type,amount,currency,description,category,payment_method,notes,project\r\n');
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
        _text(t.project ?? ''),
      ], ',')
      ..write('\r\n');
  }
  return buffer.toString();
}

enum ExportPeriod { thisMonth, lastMonth, thisYear, all }

/// Transactions for the accountant export, in the given order: inside
/// [period] (relative to [now]) and, when [project] is not null, of that
/// project ('' = personal only, i.e. without a project).
List<FinanceTransaction> selectForExport(
  List<FinanceTransaction> transactions,
  ExportPeriod period,
  String? project,
  DateTime now,
) {
  final (from, to) = switch (period) {
    ExportPeriod.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
    ExportPeriod.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
    ExportPeriod.thisYear => (DateTime(now.year), DateTime(now.year + 1)),
    ExportPeriod.all => (null, null),
  };
  return [
    for (final t in transactions)
      if ((from == null || !t.occurredAt.isBefore(from)) &&
          (to == null || t.occurredAt.isBefore(to)) &&
          (project == null || (t.project ?? '') == project))
        t,
  ];
}

String _text(String value) {
  final safe = _formulaStart.hasMatch(value) ? "'$value" : value;
  return _needsQuotes.hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}
