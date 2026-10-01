// Savings goals against a real in-memory SQLite database.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/data/repositories/savings_goal_repository_impl.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/features/savings/application/savings_providers.dart';
import 'package:expense_manager/shared/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftSavingsGoalRepository repo;
  const usd = Currency.usd;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    repo = DriftSavingsGoalRepository(db);
  });
  tearDown(() => db.close());

  SavingsGoal goal(String id, {String name = 'Trip', int target = 100000}) =>
      SavingsGoal(id: id, name: name, target: Money(target, usd), targetDate: DateTime(2027, 6, 1));

  test('save trims the name, updates in place and round-trips', () async {
    await repo.save(goal('g1', name: '  Trip  '));
    await repo.save(goal('g1', name: 'Japan', target: 200000));
    final goals = await repo.watchAll().first;
    expect(goals, hasLength(1));
    expect(goals.single.name, 'Japan');
    expect(goals.single.target, const Money(200000, usd));
    expect(goals.single.targetDate, DateTime(2027, 6, 1));
  });

  test('rejects invalid name or target', () async {
    expect(() => repo.save(goal('g1', name: '   ')), throwsArgumentError);
    expect(() => repo.save(goal('g1', name: 'x' * 81)), throwsArgumentError);
    expect(() => repo.save(goal('g1', target: 0)), throwsArgumentError);
    expect(() => repo.save(goal('g1', target: -5)), throwsArgumentError);
    expect(await repo.watchAll(includeArchived: true).first, isEmpty);
  });

  test('archive hides from active list; delete hides everywhere', () async {
    await repo.save(goal('a'));
    await repo.save(goal('b'));
    await repo.archive('a');
    expect((await repo.watchAll().first).map((g) => g.id), ['b']);
    expect((await repo.watchAll(includeArchived: true).first).map((g) => g.id), containsAll(['a', 'b']));

    await repo.delete('b');
    expect(await repo.watchAll().first, isEmpty);
    expect((await repo.watchAll(includeArchived: true).first).map((g) => g.id), ['a']);
  });

  test('SavingsActions: deposit/withdraw record transactions; overdraw is rejected', () async {
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    final actions = container.read(savingsActionsProvider);

    await actions.saveGoal(name: 'Trip', target: const Money(100000, usd));
    final id = (await repo.watchAll().first).single.id;

    await actions.deposit(id, const Money(30000, usd));
    await actions.withdraw(id, const Money(10000, usd));
    await expectLater(actions.withdraw(id, const Money(20001, usd)), throwsArgumentError);
    await expectLater(actions.deposit(id, const Money(100, Currency.eur)), throwsArgumentError);

    final txs = await container.read(transactionRepositoryProvider).watchAll().first;
    expect(txs, hasLength(2));
    expect(txs.every((t) => t.savingsGoalId == id && t.description == 'Trip'), isTrue);
    expect(txs.map((t) => t.type), containsAll([TransactionType.savings, TransactionType.savingsWithdrawal]));

    container.listen(savingsProgressProvider, (_, _) {});
    final progress = await container.read(savingsProgressProvider.future);
    expect(progress.single.saved, const Money(20000, usd));
  });
}
