import '../entities/entities.dart';

abstract interface class SavingsGoalRepository {
  /// Non-deleted goals, oldest first. Archived ones only when [includeArchived].
  Stream<List<SavingsGoal>> watchAll({bool includeArchived = false});

  /// Inserts or updates. Throws [ArgumentError] on invalid data.
  Future<void> save(SavingsGoal goal);

  Future<void> archive(String id);

  /// Soft delete (kept for sync).
  Future<void> delete(String id);
}
