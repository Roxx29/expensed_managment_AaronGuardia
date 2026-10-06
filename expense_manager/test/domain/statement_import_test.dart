import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/import/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;

  group('ColumnMapping.guess', () {
    test('Spanish signed amount', () {
      final m = ColumnMapping.guess(['Fecha', 'Concepto', 'Importe', 'Saldo']);
      expect([m.date, m.description, m.amount, m.debit, m.credit], [0, 1, 2, null, null]);
      expect(m.isComplete, isTrue);
    });

    test('Spanish debit/credit with accents', () {
      final m = ColumnMapping.guess(['Fecha operación', 'Descripción', 'Débito', 'Crédito', 'Saldo']);
      expect([m.date, m.description, m.amount, m.debit, m.credit], [0, 1, null, 2, 3]);
    });

    test('English debit amount / credit amount', () {
      final m = ColumnMapping.guess(['Posting Date', 'Details', 'Debit Amount', 'Credit Amount']);
      expect([m.date, m.description, m.amount, m.debit, m.credit], [0, 1, null, 2, 3]);
    });

    test('incomplete without date or amount', () {
      expect(ColumnMapping.guess(['Name', 'Notes']).isComplete, isFalse);
    });
  });

  group('StatementDateFormat', () {
    test('parses each format and rejects impossible dates', () {
      expect(StatementDateFormat.ymd.parse('2026-09-30 10:15'), DateTime(2026, 9, 30));
      expect(StatementDateFormat.dmySlash.parse('30/09/2026'), DateTime(2026, 9, 30));
      expect(StatementDateFormat.mdySlash.parse('9/30/2026'), DateTime(2026, 9, 30));
      expect(StatementDateFormat.dmyDash.parse('30-09-2026'), DateTime(2026, 9, 30));
      expect(StatementDateFormat.dmySlash.parse('31/02/2026'), isNull);
      expect(StatementDateFormat.ymd.parse('hello'), isNull);
    });

    test('detects the format; ambiguous prefers day-first unless US', () {
      expect(StatementDateFormat.detect(['2026-09-01']), StatementDateFormat.ymd);
      expect(StatementDateFormat.detect(['03/09/2026', '13/09/2026']), StatementDateFormat.dmySlash);
      expect(StatementDateFormat.detect(['09/03/2026', '09/13/2026']), StatementDateFormat.mdySlash);
      expect(StatementDateFormat.detect(['03/04/2026']), StatementDateFormat.dmySlash);
      expect(StatementDateFormat.detect(['03/04/2026'], preferMonthFirst: true), StatementDateFormat.mdySlash);
      expect(StatementDateFormat.detect(['13-09-2026']), StatementDateFormat.dmyDash);
    });
  });

  test('parseStatementAmount handles bank notations', () {
    int? minor(String s) => parseStatementAmount(s, usd)?.minor;
    expect(minor('-1,234.56'), -123456);
    expect(minor('1.234,56 €'), 123456);
    expect(minor(r'$ 45.20'), 4520);
    expect(minor('(12.00)'), -1200);
    expect(minor('12.00-'), -1200);
    expect(minor('+5'), 500);
    expect(minor(''), isNull);
    expect(minor('abc'), isNull);
    expect(minor('--5'), isNull);
  });

  group('mapStatement', () {
    const signed = ColumnMapping(date: 0, description: 1, amount: 2);
    final rows = [
      ['2026-09-01', 'Coffee  shop', '-3.50'],
      ['2026-09-02', 'Salary', '1,500.00'],
      ['not a date', 'X', '-1'],
      ['2026-09-03', 'Zero', '0'],
      ['2026-09-04', 'No amount', ''],
      ['2026-09-05', 'Short row'],
      ['2026-09-01', 'Coffee shop', '-3.50'], // same as row 1: a real second purchase
    ];

    test('maps rows, sets type by sign and counts skipped', () {
      final r = mapStatement(rows, signed, StatementDateFormat.ymd, usd);
      expect(r.skipped, 4);
      expect(r.transactions, hasLength(3));
      final coffee = r.transactions.first;
      expect(coffee.description, 'Coffee shop');
      expect(coffee.amount, const Money(350, usd));
      expect(coffee.type, TransactionType.expense);
      expect(coffee.date, DateTime(2026, 9, 1));
      expect(r.transactions[1].type, TransactionType.income);
      expect(r.transactions[1].amount, const Money(150000, usd));
    });

    test('IDs are deterministic and duplicates within a file stay distinct', () {
      final a = mapStatement(rows, signed, StatementDateFormat.ymd, usd).transactions.map((t) => t.id).toList();
      final b = mapStatement(rows, signed, StatementDateFormat.ymd, usd).transactions.map((t) => t.id).toList();
      expect(a, b);
      expect(a.toSet(), hasLength(3));
      expect(a.first, matches(RegExp(r'^imp_[0-9a-f]{24}$')));
    });

    test('debit/credit columns', () {
      const mapping = ColumnMapping(date: 0, description: 1, debit: 2, credit: 3);
      final r = mapStatement([
        ['30/09/2026', 'Supermercado', '1.234,56', ''],
        ['30/09/2026', 'Nómina', '', '2.000,00'],
        ['30/09/2026', 'Nada', '', ''],
      ], mapping, StatementDateFormat.dmySlash, Currency.eur);
      expect(r.skipped, 1);
      expect(r.transactions[0].type, TransactionType.expense);
      expect(r.transactions[0].amount, const Money(123456, Currency.eur));
      expect(r.transactions[1].type, TransactionType.income);
      expect(r.transactions[1].amount, const Money(200000, Currency.eur));
      expect(r.transactions[1].toTransaction().categoryId, isNull);
    });

    test('truncates long descriptions to 200 characters', () {
      final r = mapStatement([
        ['2026-09-01', 'x' * 500, '-1'],
      ], signed, StatementDateFormat.ymd, usd);
      expect(r.transactions.single.description, hasLength(200));
    });
  });

  group('other expense apps', () {
    test('guesses Monefy, Spendee, Wallet and Money Manager headers', () {
      final monefy = ColumnMapping.guess(
          ['date', 'account', 'category', 'amount', 'currency', 'converted amount', 'currency', 'description']);
      expect([monefy.date, monefy.category, monefy.amount, monefy.description, monefy.type], [0, 2, 3, 7, null]);

      final spendee = ColumnMapping.guess(
          ['Date', 'Wallet', 'Type', 'Category name', 'Amount', 'Currency', 'Note', 'Labels', 'Author']);
      expect([spendee.date, spendee.type, spendee.category, spendee.amount, spendee.description], [0, 2, 3, 4, 6]);

      final wallet = ColumnMapping.guess(['account', 'category', 'currency', 'amount', 'ref_currency_amount', 'type',
          'payment_type', 'payment_type_local', 'note', 'date', 'labels', 'custom_category']);
      expect([wallet.date, wallet.type, wallet.category, wallet.amount, wallet.description], [9, 5, 1, 3, 8]);

      final moneyManager = ColumnMapping.guess(
          ['Period', 'Accounts', 'Category', 'Subcategory', 'Note', 'Amount', 'Income/Expense', 'Description']);
      expect([moneyManager.date, moneyManager.category, moneyManager.amount, moneyManager.type], [0, 2, 5, 6]);
      expect(moneyManager.description, 7);
    });

    test('a Type column sets the direction of positive amounts and skips transfers', () {
      const mapping = ColumnMapping(date: 0, description: 1, amount: 2, type: 3, category: 4);
      final r = mapStatement([
        ['2026-09-01', 'Lunch', '12.00', 'Exp.', 'Food'],
        ['2026-09-02', 'Pay', '900', 'Income', 'Salary'],
        ['2026-09-03', 'Bus', '-2', 'Gasto', ''],
        ['2026-09-04', 'Savings', '50', 'Transfer-Out', ''],
        ['2026-09-05', 'Odd', '-7', '???', ''],
      ], mapping, StatementDateFormat.ymd, usd);
      expect(r.skipped, 1);
      expect(r.transactions.map((t) => t.type), [
        TransactionType.expense,
        TransactionType.income,
        TransactionType.expense,
        TransactionType.expense, // unknown type text: the sign decides
      ]);
      expect(r.transactions.every((t) => t.amount.isPositive), isTrue);
      expect(r.transactions.map((t) => t.categoryName), ['Food', 'Salary', '', '']);
    });
  });
}
