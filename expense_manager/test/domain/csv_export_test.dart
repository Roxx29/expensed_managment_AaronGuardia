import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/export/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceTransaction tx({String description = '', String? notes, String? categoryId}) => FinanceTransaction(
        id: 'a',
        type: TransactionType.expense,
        amount: const Money(123450, Currency.usd),
        occurredAt: DateTime(2026, 9, 5, 8, 7),
        description: description,
        categoryId: categoryId,
        paymentMethodId: 'pm',
        notes: notes,
      );

  List<String> lines(List<FinanceTransaction> list) => transactionsToCsv(
        list,
        categoryName: (id) => id == null ? '' : 'Food',
        paymentMethodName: (id) => 'Cash',
      ).split('\r\n');

  test('header and a plain row', () {
    expect(lines([tx(description: 'Lunch', categoryId: 'c')]), [
      'date,type,amount,currency,description,category,payment_method,notes',
      '2026-09-05 08:07,expense,1234.50,USD,Lunch,Food,Cash,',
      '',
    ]);
  });

  test('RFC 4180 quoting', () {
    final row = lines([tx(description: 'Pizza, "large"', notes: 'line1\nline2')]).sublist(1).join('\r\n');
    expect(row, '2026-09-05 08:07,expense,1234.50,USD,"Pizza, ""large""",,Cash,"line1\nline2"\r\n');
  });

  test('formula injection is defused in text cells', () {
    for (final evil in ['=HYPERLINK("x")', '+1', '-2', '@SUM(A1)', '\tx', '\rx']) {
      final cell = lines([tx(description: evil)])[1].split(',')[4];
      expect(cell, anyOf(startsWith("'"), startsWith('"\'')), reason: evil);
    }
    expect(lines([tx(description: '=1+1')])[1], contains(",'=1+1,"));
  });

  test('payment method column is empty without a resolver', () {
    final csv = transactionsToCsv([tx()], categoryName: (_) => '');
    expect(csv.split('\r\n')[1], '2026-09-05 08:07,expense,1234.50,USD,,,,');
  });
}
