import 'package:expense_manager/domain/import/csv_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses quotes, escaped quotes, separators and line breaks inside quotes', () {
    const text = 'Date,Description,Amount\r\n'
        '2026-09-01,"Coffee, large",-3.50\r\n'
        '2026-09-02,"He said ""hi""",10\r\n'
        '2026-09-03,"Line one\nline two",-1\r\n';
    expect(parseCsv(text), [
      ['Date', 'Description', 'Amount'],
      ['2026-09-01', 'Coffee, large', '-3.50'],
      ['2026-09-02', 'He said "hi"', '10'],
      ['2026-09-03', 'Line one\nline two', '-1'],
    ]);
  });

  test('detects semicolon and tab delimiters, strips BOM and skips blank lines', () {
    expect(parseCsv('﻿Fecha;Concepto;Importe\n\n01/09/2026;Pan;-1,25\n'), [
      ['Fecha', 'Concepto', 'Importe'],
      ['01/09/2026', 'Pan', '-1,25'],
    ]);
    expect(parseCsv('a\tb\n1\t2'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
    expect(detectDelimiter('"a;b",c,d'), ',');
  });

  test('keeps empty fields and handles a lone CR line ending', () {
    expect(parseCsv('a,,c\r1,2,'), [
      ['a', '', 'c'],
      ['1', '2', ''],
    ]);
  });

  test('rejects malformed or oversized input', () {
    expect(() => parseCsv('a,"b\n1,2'), throwsFormatException);
    expect(() => parseCsv('a\n' * (maxCsvRows + 1)), throwsFormatException);
    expect(() => parseCsv('a' * (maxCsvBytes + 1)), throwsFormatException);
    expect(parseCsv('a\n' * maxCsvRows), hasLength(maxCsvRows));
  });
}
