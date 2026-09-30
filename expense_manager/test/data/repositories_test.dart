// Integration tests against a real in-memory SQLite database.
// Requires a native sqlite3 library on the host running `flutter test`
// (bundled on macOS/Linux; see README for Windows). Skip with `-x db`.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/data/database/default_data.dart';
import 'package:expense_manager/data/repositories/planning_repositories_impl.dart';
import 'package:expense_manager/data/repositories/catalog_repositories_impl.dart';
import 'package:expense_manager/data/repositories/profile_settings_repositories_impl.dart';
import 'package:expense_manager/data/repositories/transaction_repository_impl.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  const usd = Currency.usd;

  setUp(() => db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)));
  tearDown(() => db.close());

  test('first launch seeds default categories, payment methods and profile', () async {
    final categories = await DriftCategoryRepository(db).watchAll().first;
    expect(categories.map((c) => c.id), containsAll(['cat_food', 'cat_subscriptions', 'cat_other']));
    expect(categories.length, defaultCategories.length);

    final methods = await DriftPaymentMethodRepository(db).watchAll().first;
    expect(methods.length, defaultPaymentMethods.length);

    final profile = await DriftProfileRepository(db).watch().first;
    expect(profile.currency, Currency.usd);
  });

  group('DriftTransactionRepository', () {
    late DriftTransactionRepository repo;
    setUp(() => repo = DriftTransactionRepository(db));

    FinanceTransaction expense(String id, int minor, DateTime at) => FinanceTransaction(
          id: id,
          type: TransactionType.expense,
          amount: Money(minor, usd),
          occurredAt: at,
          categoryId: 'cat_food',
          paymentMethodId: 'pm_cash',
        );

    test('saves, updates and reads within a date range', () async {
      await repo.save(expense('a', 1000, DateTime(2026, 9, 5)));
      await repo.save(expense('b', 2000, DateTime(2026, 10, 1)));
      await repo.save(expense('a', 1500, DateTime(2026, 9, 5))); // update

      const sept = YearMonth(2026, 9);
      final list = await repo.watchBetween(sept.start, sept.endExclusive).first;
      expect(list.single.amount, const Money(1500, usd));
      expect(list.single.categoryId, 'cat_food');
    });

    test('soft delete hides the transaction', () async {
      await repo.save(expense('a', 1000, DateTime(2026, 9, 5)));
      await repo.delete('a');
      expect(await repo.watchRecent().first, isEmpty);
    });

    test('getById, watchAll and restore after delete (undo)', () async {
      final tx = expense('a', 1000, DateTime(2026, 9, 5));
      await repo.save(tx);
      expect((await repo.getById('a'))?.amount, const Money(1000, usd));

      await repo.delete('a');
      expect(await repo.getById('a'), isNull);
      expect(await repo.watchAll().first, isEmpty);

      await repo.save(tx); // undo
      expect((await repo.watchAll().first).single.id, 'a');
    });

    test('insertMissing is idempotent and never resurrects deleted rows', () async {
      final generated = expense('sub_20260915', 1599, DateTime(2026, 9, 15));
      await repo.insertMissing([generated]);
      await repo.insertMissing([generated]);
      expect(await repo.watchAll().first, hasLength(1));

      await repo.delete('sub_20260915');
      await repo.insertMissing([generated]);
      expect(await repo.watchAll().first, isEmpty);
    });

    test('totals by type drive the available balance', () async {
      await repo.save(expense('a', 1000, DateTime(2026, 9, 5)));
      await repo.save(FinanceTransaction(
        id: 'i',
        type: TransactionType.income,
        amount: const Money(5000, usd),
        occurredAt: DateTime(2026, 9, 1),
      ));
      final totals = await repo.watchTotalsByType(usd).first;
      expect(totals[TransactionType.expense], const Money(1000, usd));
      expect(totals[TransactionType.income], const Money(5000, usd));
    });

    test('rejects non-positive amounts', () async {
      expect(() => repo.save(expense('x', 0, DateTime(2026, 9, 5))), throwsArgumentError);
    });

    test('rejects unknown category (foreign key)', () async {
      final bad = FinanceTransaction(
        id: 'x',
        type: TransactionType.expense,
        amount: const Money(100, usd),
        occurredAt: DateTime(2026, 9, 5),
        categoryId: 'does_not_exist',
      );
      expect(() => repo.save(bad), throwsA(anything));
    });
  });

  group('DriftBudgetRepository', () {
    test('changing a budget keeps the old amount for past months', () async {
      final repo = DriftBudgetRepository(db);
      await repo.setBudget(categoryId: 'cat_food', amount: const Money(25000, usd), fromMonth: const YearMonth(2026, 7));
      await repo.setBudget(categoryId: 'cat_food', amount: const Money(30000, usd), fromMonth: const YearMonth(2026, 9));

      final august = await repo.watchForMonth(const YearMonth(2026, 8)).first;
      final september = await repo.watchForMonth(const YearMonth(2026, 9)).first;
      expect(august.single.amount, const Money(25000, usd));
      expect(september.single.amount, const Money(30000, usd));
    });

    test('setting twice in the same month replaces the amount', () async {
      final repo = DriftBudgetRepository(db);
      const month = YearMonth(2026, 9);
      await repo.setBudget(categoryId: null, amount: const Money(100000, usd), fromMonth: month);
      await repo.setBudget(categoryId: null, amount: const Money(120000, usd), fromMonth: month);
      final budgets = await repo.watchForMonth(month).first;
      expect(budgets.single.amount, const Money(120000, usd));
      expect(budgets.single.isGlobal, isTrue);
    });

    test('setting an earlier budget replaces later ones (no overlapping periods)', () async {
      final repo = DriftBudgetRepository(db);
      await repo.setBudget(categoryId: 'cat_food', amount: const Money(40000, usd), fromMonth: const YearMonth(2026, 11));
      await repo.setBudget(categoryId: 'cat_food', amount: const Money(30000, usd), fromMonth: const YearMonth(2026, 9));
      final december = await repo.watchForMonth(const YearMonth(2026, 12)).first;
      expect(december.single.amount, const Money(30000, usd));
    });

    test('removeBudget ends it from the given month', () async {
      final repo = DriftBudgetRepository(db);
      await repo.setBudget(categoryId: 'cat_gas', amount: const Money(5000, usd), fromMonth: const YearMonth(2026, 1));
      await repo.removeBudget(categoryId: 'cat_gas', fromMonth: const YearMonth(2026, 9));
      expect(await repo.watchForMonth(const YearMonth(2026, 9)).first, isEmpty);
      expect(await repo.watchForMonth(const YearMonth(2026, 8)).first, hasLength(1));
    });
  });

  test('archived categories are hidden from pickers but kept for labels', () async {
    final repo = DriftCategoryRepository(db);
    await repo.archive('cat_gas');
    expect((await repo.watchAll().first).map((c) => c.id), isNot(contains('cat_gas')));
    expect((await repo.watchAll(includeArchived: true).first).map((c) => c.id), contains('cat_gas'));
  });

  test('custom category and payment method are saved', () async {
    await DriftCategoryRepository(db).save(const FinanceCategory(
      id: 'custom', name: ' Pets ', iconKey: 'pets', color: 0xFF000000, kind: CategoryKind.expense,
    ));
    final saved = (await DriftCategoryRepository(db).watchAll().first).firstWhere((c) => c.id == 'custom');
    expect(saved.name, 'Pets'); // trimmed

    await DriftPaymentMethodRepository(db).save(
      const PaymentMethod(id: 'visa', name: 'Visa', type: PaymentMethodType.creditCard),
    );
    expect((await DriftPaymentMethodRepository(db).watchAll().first).map((m) => m.id), contains('visa'));
    expect(
      () => DriftPaymentMethodRepository(db).save(
        const PaymentMethod(id: 'x', name: '  ', type: PaymentMethodType.cash),
      ),
      throwsArgumentError,
    );
  });

  test('settings round-trip', () async {
    final repo = DriftSettingsRepository(db);
    expect(await repo.read('theme'), isNull);
    await repo.write('theme', 'dark');
    await repo.write('theme', 'light');
    expect(await repo.read('theme'), 'light');
  });
}
