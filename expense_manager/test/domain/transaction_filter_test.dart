import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/transaction_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;

  final txs = [
    FinanceTransaction(
      id: 'groceries',
      type: TransactionType.expense,
      amount: const Money(4500, usd),
      occurredAt: DateTime(2026, 9, 10),
      description: 'Weekly groceries',
      categoryId: 'cat_food',
    ),
    FinanceTransaction(
      id: 'salary',
      type: TransactionType.income,
      amount: const Money(300000, usd),
      occurredAt: DateTime(2026, 9, 1),
      source: 'ACME Corp',
      categoryId: 'cat_salary',
    ),
    FinanceTransaction(
      id: 'cinema',
      type: TransactionType.expense,
      amount: const Money(1200, usd),
      occurredAt: DateTime(2026, 8, 20),
      notes: 'With friends',
      categoryId: 'cat_entertainment',
    ),
  ];

  List<String> ids(TransactionFilter f) =>
      f.apply(txs, categoryNames: {'cat_food': 'Food'}).map((t) => t.id).toList();

  test('default: everything, newest first', () {
    expect(ids(const TransactionFilter()), ['groceries', 'salary', 'cinema']);
    expect(const TransactionFilter().isActive, isFalse);
  });

  test('search matches description, notes, source and category name (case-insensitive)', () {
    expect(ids(const TransactionFilter(query: 'GROCER')), ['groceries']);
    expect(ids(const TransactionFilter(query: 'friends')), ['cinema']);
    expect(ids(const TransactionFilter(query: 'acme')), ['salary']);
    expect(ids(const TransactionFilter(query: 'food')), ['groceries']);
    expect(ids(const TransactionFilter(query: 'nothing')), isEmpty);
  });

  test('type, category, date and amount filters combine', () {
    expect(ids(const TransactionFilter(types: {TransactionType.expense})), ['groceries', 'cinema']);
    expect(ids(const TransactionFilter(categoryId: 'cat_salary')), ['salary']);
    expect(
      ids(TransactionFilter(from: DateTime(2026, 9, 1), toExclusive: DateTime(2026, 9, 10))),
      ['salary'], // end is exclusive
    );
    expect(
      ids(const TransactionFilter(minAmount: Money(1200, usd), maxAmount: Money(4500, usd))),
      ['groceries', 'cinema'],
    );
  });

  test('amount filter in another currency matches nothing', () {
    expect(ids(const TransactionFilter(minAmount: Money(1, Currency.eur))), isEmpty);
  });

  test('sorts by amount and oldest', () {
    expect(ids(const TransactionFilter(sort: TransactionSort.highest)), ['salary', 'groceries', 'cinema']);
    expect(ids(const TransactionFilter(sort: TransactionSort.lowest)), ['cinema', 'groceries', 'salary']);
    expect(ids(const TransactionFilter(sort: TransactionSort.oldest)), ['cinema', 'salary', 'groceries']);
  });

  test('copyWith clear flags remove criteria', () {
    const f = TransactionFilter(categoryId: 'x', minAmount: Money(1, usd));
    expect(f.copyWith(clearCategory: true).categoryId, isNull);
    expect(f.copyWith(clearAmounts: true).minAmount, isNull);
    expect(f.copyWith(query: 'a').categoryId, 'x');
  });
}
