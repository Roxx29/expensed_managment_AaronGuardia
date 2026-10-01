/// Minimal RFC 4180 CSV reader for bank statements (pure Dart).
library;

/// Largest accepted file (bytes) and number of rows.
const maxCsvBytes = 5 * 1024 * 1024;
const maxCsvRows = 20000;

/// Picks `,`, `;` or tab — whichever appears most in [headerLine] outside
/// quotes. Defaults to `,`.
String detectDelimiter(String headerLine) {
  final counts = {',': 0, ';': 0, '\t': 0};
  var inQuotes = false;
  for (final ch in headerLine.split('')) {
    if (ch == '"') inQuotes = !inQuotes;
    if (!inQuotes && counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
  }
  var best = ',';
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// Parses [text] into rows of fields. Handles quoted fields, escaped quotes
/// (`""`), delimiters and line breaks inside quotes, CRLF/LF/CR line endings
/// and a UTF-8 BOM. Blank lines are skipped. The delimiter is detected from
/// the first line unless given.
///
/// Throws [FormatException] when the text is too large, has too many rows or
/// ends inside a quoted field.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  if (text.length > maxCsvBytes) throw const FormatException('CSV file too large');
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final firstBreak = text.indexOf(RegExp('[\r\n]'));
  final sep = delimiter ?? detectDelimiter(firstBreak < 0 ? text : text.substring(0, firstBreak));

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endRow() {
    row.add(field.toString());
    field.clear();
    // Skip blank lines.
    if (row.length > 1 || row.first.isNotEmpty) {
      if (rows.length >= maxCsvRows) throw const FormatException('Too many rows');
      rows.add(row);
    }
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == sep) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (inQuotes) throw const FormatException('Unterminated quoted field');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
