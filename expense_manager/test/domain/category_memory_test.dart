import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/import/category_memory.dart';
import 'package:expense_manager/domain/import/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usd = Currency.usd;

  FinanceTransaction tx(String id, String description, String? categoryId, DateTime at) => FinanceTransaction(
        id: id,
        type: TransactionType.expense,
        amount: const Money(100, usd),
        occurredAt: at,
        description: description,
        categoryId: categoryId,
      );

  ImportedTransaction imported(String description, {String category = ''}) => ImportedTransaction(
        id: 'imp_$description',
        date: DateTime(2026, 9, 1),
        description: description,
        amount: const Money(100, usd),
        type: TransactionType.expense,
        categoryName: category,
      );

  test('merchantKey ignores case, accents, digits and punctuation', () {
    expect(merchantKey('UBER *TRIP 4421 Panamá'), 'uber trip panama');
    expect(merchantKey('Uber Trip  9981 PANAMA'), 'uber trip panama');
    expect(merchantKey('12345 ***'), '');
  });

  test('learnCategories keeps the most recent category per merchant', () {
    final memory = learnCategories([
      tx('a', 'Super 99 #12', 'cat_food', DateTime(2026, 8, 1)),
      tx('b', 'SUPER 99 #40', 'cat_shopping', DateTime(2026, 9, 1)),
      tx('c', 'Super 99', null, DateTime(2026, 9, 5)),
    ]);
    expect(memory['super'], 'cat_shopping');
  });

  test('assignCategories: file names, then memory, then new categories', () {
    final result = assignCategories(
      [
        imported('Lunch', category: 'Comida'),
        imported('Super 99 #77'),
        imported('Gym', category: 'Fitness'),
        imported('Gym 2', category: 'fitness'),
        imported('Unknown shop'),
      ],
      idByName: {'food': 'cat_food', 'comida': 'cat_food'},
      memory: {'super': 'cat_shopping'},
      newCategoryColor: 0xFF000000,
    );
    expect(result.transactions.map((t) => t.categoryId).take(2), ['cat_food', 'cat_shopping']);
    expect(result.newCategories, hasLength(1));
    final fitness = result.newCategories.single;
    expect(fitness.name, 'Fitness');
    expect(fitness.id, startsWith('cat_imp_'));
    expect(result.transactions[2].categoryId, fitness.id);
    expect(result.transactions[3].categoryId, fitness.id);
    expect(result.transactions[4].categoryId, isNull);
  });

  test('caps how many categories one import creates', () {
    final result = assignCategories(
      [for (var i = 0; i <= maxNewCategories; i++) imported('Shop $i', category: 'Cat $i')],
      idByName: const {},
      memory: const {},
      newCategoryColor: 0,
    );
    expect(result.newCategories, hasLength(maxNewCategories));
    expect(result.transactions.last.categoryId, isNull);
  });

  test('new category ids are stable across imports', () {
    String id() => assignCategories([imported('x', category: 'Mascotas')],
            idByName: const {}, memory: const {}, newCategoryColor: 0)
        .newCategories
        .single
        .id;
    expect(id(), id());
  });
}
