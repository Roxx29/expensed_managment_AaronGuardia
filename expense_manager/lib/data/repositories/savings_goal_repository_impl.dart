import 'package:drift/drift.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/savings_goal_repository.dart';
import '../database/app_database.dart';

class DriftSavingsGoalRepository implements SavingsGoalRepository {
  DriftSavingsGoalRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<SavingsGoal>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.savingsGoals)
      ..where((g) =>
          g.deletedAt.isNull() &
          (includeArchived ? const Constant(true) : g.archived.equals(false)))
      ..orderBy([(g) => OrderingTerm.asc(g.createdAt), (g) => OrderingTerm.asc(g.name)]);
    return query.watch().map((rows) => rows
        .map((r) => SavingsGoal(
              id: r.id,
              name: r.name,
              target: Money(r.targetMinor, Currency.fromCode(r.currencyCode)),
              targetDate: r.targetDate,
              archived: r.archived,
            ))
        .toList());
  }

  @override
  Future<void> save(SavingsGoal goal) {
    final name = goal.name.trim();
    if (name.isEmpty || name.length > 80) throw ArgumentError('must be 1-80 characters', 'name');
    if (!goal.target.isPositive || !goal.target.isWithinLimits) {
      throw ArgumentError('must be > 0 and <= Money.maxMinor', 'target');
    }
    return _db.into(_db.savingsGoals).insertOnConflictUpdate(
          SavingsGoalsCompanion.insert(
            id: goal.id,
            name: name,
            targetMinor: goal.target.minor,
            currencyCode: goal.target.currency.code,
            targetDate: Value(goal.targetDate),
            archived: Value(goal.archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> archive(String id) =>
      (_db.update(_db.savingsGoals)..where((g) => g.id.equals(id))).write(
        SavingsGoalsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now())),
      );

  @override
  Future<void> delete(String id) {
    final now = DateTime.now();
    return (_db.update(_db.savingsGoals)..where((g) => g.id.equals(id)))
        .write(SavingsGoalsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
