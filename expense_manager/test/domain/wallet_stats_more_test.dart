import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/wallets/wallet_stats.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
const oct = YearMonth(2026, 10);
var _n = 0;

FinanceTransaction tx(TransactionType type, int minor, {String? by, String desc = '', String? notes}) =>
    FinanceTransaction(
      id: 'id${_n++}',
      type: type,
      amount: Money(minor, usd),
      occurredAt: DateTime(2026, 10, 5),
      description: desc,
      notes: notes,
      createdBy: by,
      walletId: 'w',
    );

void main() {
  group('WalletStats.byMember', () {
    test('ignores transfers and savings moves', () {
      final rows = WalletStats.byMember([
        tx(TransactionType.expense, 100, by: 'ana'),
        tx(TransactionType.transfer, 5000, by: 'ana'),
        tx(TransactionType.savings, 5000, by: 'ana'),
        tx(TransactionType.savingsWithdrawal, 5000, by: 'ana'),
        tx(TransactionType.transfer, 5000, by: 'leo'), // only non-counted entries
        tx(TransactionType.savings, 5000, by: 'leo'),
      ], oct, usd);

      expect(rows.map((r) => r.uid), ['ana']);
      expect(rows.single.expenses, const Money(100, usd));
      expect(rows.single.income, const Money.zero(usd));
      expect(rows.single.count, 1);
    });

    test('equal spending is sorted by income, highest first', () {
      final rows = WalletStats.byMember([
        tx(TransactionType.expense, 500, by: 'ana'),
        tx(TransactionType.income, 100, by: 'ana'),
        tx(TransactionType.expense, 500, by: 'leo'),
        tx(TransactionType.income, 900, by: 'leo'),
      ], oct, usd);

      expect(rows.map((r) => r.uid), ['leo', 'ana']);
    });
  });

  test('balance ignores transfers and savings moves', () {
    final entries = [
      tx(TransactionType.income, 1000),
      tx(TransactionType.expense, 300),
      tx(TransactionType.transfer, 5000),
      tx(TransactionType.savings, 5000),
      tx(TransactionType.savingsWithdrawal, 5000),
    ];

    expect(WalletStats.balance(entries, usd), const Money(700, usd));
  });

  group('WalletStats.filter', () {
    final entries = [
      tx(TransactionType.expense, 100, by: 'ana', desc: 'Dinner', notes: 'Birthday of Leo'),
      tx(TransactionType.expense, 200, by: 'leo', desc: 'Taxi'),
      tx(TransactionType.income, 300, desc: 'Refund'), // no author
    ];

    test('query matches notes case-insensitively', () {
      expect(WalletStats.filter(entries, query: 'BIRTHDAY').single.description, 'Dinner');
    });

    test('empty member means every author, including entries without one', () {
      expect(WalletStats.filter(entries, member: '').length, entries.length);
    });
  });
}
