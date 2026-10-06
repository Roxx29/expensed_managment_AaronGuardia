/// Maps parsed bank-statement CSV rows to transactions (pure Dart).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../entities/entities.dart';

/// Date layouts accepted in statements. [pattern] is shown to the user.
enum StatementDateFormat {
  ymd('yyyy-MM-dd'),
  dmySlash('dd/MM/yyyy'),
  mdySlash('MM/dd/yyyy'),
  dmyDash('dd-MM-yyyy');

  const StatementDateFormat(this.pattern);

  final String pattern;

  static final _ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|[T\s])');
  static final _slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:$|\s)');
  static final _dash = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})(?:$|\s)');

  /// Parses the leading date of [text] (a trailing time is ignored).
  DateTime? parse(String text) {
    final (re, y, m, d) = switch (this) {
      StatementDateFormat.ymd => (_ymd, 1, 2, 3),
      StatementDateFormat.dmySlash => (_slash, 3, 2, 1),
      StatementDateFormat.mdySlash => (_slash, 3, 1, 2),
      StatementDateFormat.dmyDash => (_dash, 3, 2, 1),
    };
    final match = re.firstMatch(text.trim());
    if (match == null) return null;
    return validDate(int.parse(match[y]!), int.parse(match[m]!), int.parse(match[d]!));
  }

  /// The format that parses most of [samples]. Ties (e.g. `03/04/2026`)
  /// prefer day-first unless [preferMonthFirst] (US users).
  static StatementDateFormat detect(Iterable<String> samples, {bool preferMonthFirst = false}) {
    final order = preferMonthFirst
        ? const [ymd, mdySlash, dmySlash, dmyDash]
        : const [ymd, dmySlash, mdySlash, dmyDash];
    var best = order.first;
    var bestCount = -1;
    for (final f in order) {
      final count = samples.where((s) => f.parse(s) != null).length;
      if (count > bestCount) {
        best = f;
        bestCount = count;
      }
    }
    return best;
  }
}

/// A calendar date, or null if it does not exist (e.g. 31/02) or is
/// outside 1970–2100.
DateTime? validDate(int year, int month, int day) {
  if (year < 1970 || year > 2100 || month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

/// Lowercase without accents, for comparing names typed in other apps.
String foldText(String s) {
  const from = 'áéíóúüñàèìòùâêîôûäëïöç';
  const to = 'aeiouunaeiouaeiouaeioc';
  final out = StringBuffer();
  for (final ch in s.trim().toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// Column indexes (0-based) of a statement or another app's export. Either
/// [amount] (signed: negative = expense) or [debit]/[credit] must be set;
/// [amount] wins when both are. An optional [type] column ("Expense",
/// "Ingreso"…) decides the direction when its text is recognised, so apps
/// that export positive amounts work too. [category] holds category names.
class ColumnMapping {
  const ColumnMapping({this.date, this.description, this.amount, this.debit, this.credit, this.type, this.category});

  final int? date;
  final int? description;
  final int? amount;
  final int? debit;
  final int? credit;
  final int? type;
  final int? category;

  bool get isComplete => date != null && (amount != null || debit != null || credit != null);

  /// Guesses columns from header names (English and Spanish), including the
  /// exports of Monefy, Spendee, Wallet and Money Manager.
  factory ColumnMapping.guess(List<String> header) {
    int? date, description, amount, debit, credit, type, category, note;
    for (var i = 0; i < header.length; i++) {
      final h = foldText(header[i]);
      bool has(List<String> words) => words.any(h.contains);
      if (date == null && has(const ['fecha', 'date', 'period'])) {
        date = i;
      } else if (type == null &&
          (has(const ['type', 'tipo']) || (h.contains('income') && h.contains('expense'))) &&
          !has(const ['payment', 'pago', 'currency', 'moneda', 'cambio'])) {
        type = i;
      } else if (debit == null && has(const ['debito', 'cargo', 'debit', 'retiro', 'withdrawal'])) {
        debit = i;
      } else if (credit == null && has(const ['credito', 'abono', 'credit', 'deposito', 'deposit'])) {
        credit = i;
      } else if (amount == null && has(const ['monto', 'importe', 'amount'])) {
        amount = i;
      } else if (category == null && has(const ['categor'])) {
        category = i;
      } else if (description == null &&
          has(const ['descripcion', 'description', 'concepto', 'detalle', 'details', 'memo', 'payee'])) {
        description = i;
      } else if (note == null && has(const ['note', 'nota'])) {
        note = i;
      }
    }
    return ColumnMapping(
      date: date,
      description: description ?? note,
      amount: amount,
      debit: debit,
      credit: credit,
      type: type,
      category: category,
    );
  }
}

enum _RowKind { expense, income, transfer }

/// Reads a type cell ("Expense", "Exp.", "Gasto", "Income", "Transfer-Out"…).
/// Null when the text is not recognised (then the amount's sign decides).
_RowKind? _rowKind(String text) {
  final t = foldText(text);
  if (t.isEmpty) return null;
  if (t.contains('transf')) return _RowKind.transfer;
  bool starts(List<String> words) => words.any(t.startsWith);
  if (starts(const ['exp', 'gast', 'egres', 'debit', 'cargo', 'salida', 'out', 'withdraw', 'retiro', '-'])) {
    return _RowKind.expense;
  }
  if (starts(const ['inc', 'ingres', 'credit', 'abono', 'entrada', 'deposit', '+'])) return _RowKind.income;
  return null;
}

class ImportedTransaction {
  const ImportedTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    this.categoryName = '',
  });

  /// Deterministic, so importing the same file twice adds nothing.
  final String id;
  final DateTime date;
  final String description;

  /// Always positive; [type] carries the direction.
  final Money amount;

  /// [TransactionType.expense] or [TransactionType.income].
  final TransactionType type;

  /// Category name from the file ('' when none), see category_memory.dart.
  final String categoryName;

  FinanceTransaction toTransaction({String? categoryId}) => FinanceTransaction(
        id: id,
        type: type,
        amount: amount,
        occurredAt: date,
        description: description,
        categoryId: categoryId,
      );
}

class StatementImportResult {
  const StatementImportResult(this.transactions, this.skipped);

  final List<ImportedTransaction> transactions;

  /// Rows without a valid date or a non-zero amount, and transfers.
  final int skipped;
}

const _maxDescriptionLength = 200;
const _maxCategoryNameLength = 40;

String _cap(String s, int max) => s.length > max ? s.substring(0, max).trim() : s;

/// Maps data [rows] (header excluded) with [mapping] and [format].
StatementImportResult mapStatement(
  List<List<String>> rows,
  ColumnMapping mapping,
  StatementDateFormat format,
  Currency currency,
) {
  final result = <ImportedTransaction>[];
  final seen = <String, int>{};
  var skipped = 0;
  String cell(List<String> row, int? i) => i != null && i < row.length ? row[i].trim() : '';

  for (final row in rows) {
    final date = mapping.date == null ? null : format.parse(cell(row, mapping.date));
    var signed = _signedAmount(row, mapping, currency, cell);
    final kind = mapping.type == null ? null : _rowKind(cell(row, mapping.type));
    if (date == null || signed == null || signed.isZero || !signed.isWithinLimits || kind == _RowKind.transfer) {
      skipped++;
      continue;
    }
    if (kind != null) signed = kind == _RowKind.expense ? -signed.abs() : signed.abs();
    var description = cell(row, mapping.description).replaceAll(RegExp(r'\s+'), ' ');
    if (description.length > _maxDescriptionLength) {
      description = description.substring(0, _maxDescriptionLength).trim();
    }
    final key = '${date.year}-${date.month}-${date.day}|${signed.minor}|$description';
    final occurrence = seen[key] = (seen[key] ?? -1) + 1;
    final hash = sha256.convert(utf8.encode('$key|$occurrence')).toString();
    result.add(ImportedTransaction(
      id: 'imp_${hash.substring(0, 24)}',
      date: date,
      description: description,
      amount: signed.abs(),
      type: signed.isNegative ? TransactionType.expense : TransactionType.income,
      // Control/format characters (newlines, bidi marks) never reach a name.
      categoryName: _cap(
        cell(row, mapping.category).replaceAll(RegExp(r'[\p{Cc}\p{Cf}]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        _maxCategoryNameLength,
      ),
    ));
  }
  return StatementImportResult(result, skipped);
}

/// Negative = money out. Null when no usable amount.
Money? _signedAmount(
  List<String> row,
  ColumnMapping m,
  Currency currency,
  String Function(List<String>, int?) cell,
) {
  if (m.amount != null) return parseStatementAmount(cell(row, m.amount), currency);
  final debit = parseStatementAmount(cell(row, m.debit), currency);
  if (debit != null && !debit.isZero) return -debit.abs();
  final credit = parseStatementAmount(cell(row, m.credit), currency);
  if (credit != null && !credit.isZero) return credit.abs();
  return null;
}

/// Parses bank amounts like `-1,234.56`, `1.234,56 €`, `(12.00)`, `12.00-`
/// or `+5`. Null if invalid or empty.
Money? parseStatementAmount(String text, Currency currency) {
  var s = text.replaceAll(RegExp(r'[^0-9.,()+\-]'), '');
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  } else if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('-')) {
    negative = !negative;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final value = Money.tryParse(s, currency);
  if (value == null || value.isNegative) return null; // e.g. "--5"
  return negative ? -value : value;
}
