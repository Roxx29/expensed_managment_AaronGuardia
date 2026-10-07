import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/wallets/wallet_stats.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
const oct = YearMonth(2026, 10);
var _n = 0;

FinanceTransaction tx(TransactionType type, int minor, {String? by, DateTime? at, String desc = '', Currency c = usd}) =>
    FinanceTransaction(
      id: 'id${_n++}',
      type: type,
      amount: Money(minor, c),
      occurredAt: at ?? DateTime(2026, 10, 5),
      description: desc,
      createdBy: by,
      walletId: 'w',
    );

void main() {
  final entries = [
    tx(TransactionType.expense, 1000, by: 'ana', desc: 'Rent'),
    tx(TransactionType.expense, 500, by: 'ana'),
    tx(TransactionType.income, 3000, by: 'leo', desc: 'Sales'),
    tx(TransactionType.expense, 2000, by: 'leo'),
    tx(TransactionType.expense, 9999, by: 'leo', at: DateTime(2026, 9, 30)), // other month
    tx(TransactionType.expense, 700, by: 'ana', c: Currency.values.firstWhere((x) => x != usd)), // other currency
  ];

  test('byMember: this month, this currency, most spending first', () {
    final rows = WalletStats.byMember(entries, oct, usd);
    expect(rows.map((r) => r.uid), ['leo', 'ana']);
    expect(rows.first.expenses, const Money(2000, usd));
    expect(rows.first.income, const Money(3000, usd));
    expect(rows.first.count, 2);
    expect(rows.last.expenses, const Money(1500, usd));
    expect(rows.last.count, 2);
  });

  test('balance: all-time income minus expenses in the currency', () {
    expect(WalletStats.balance(entries, usd), const Money(3000 - 1000 - 500 - 2000 - 9999, usd));
  });

  test('filter by type, member and text', () {
    expect(WalletStats.filter(entries, type: TransactionType.income).length, 1);
    expect(WalletStats.filter(entries, member: 'ana').length, 3);
    expect(WalletStats.filter(entries, query: ' rent ').single.description, 'Rent');
    expect(
      WalletStats.filter(entries, query: 'food', categoryName: (_) => 'Food').length,
      entries.length,
    );
    expect(WalletStats.filter(entries).length, entries.length);
  });

  test('firstMonth is the oldest entry or today', () {
    expect(WalletStats.firstMonth(entries, DateTime(2026, 10, 7)), const YearMonth(2026, 9));
    expect(WalletStats.firstMonth(const [], DateTime(2026, 10, 7)), oct);
  });
}
