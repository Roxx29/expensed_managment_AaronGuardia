import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/utils/ids.dart';
import '../../../data/repositories/savings_goal_repository_impl.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/savings_calculator.dart';
import '../../../domain/repositories/savings_goal_repository.dart';
import '../../../shared/providers/providers.dart';

final savingsGoalRepositoryProvider = Provider<SavingsGoalRepository>(
  (ref) => DriftSavingsGoalRepository(ref.watch(appDatabaseProvider)),
);

/// Active (non-archived) goals.
final savingsGoalsProvider = StreamProvider<List<SavingsGoal>>(
  (ref) => ref.watch(savingsGoalRepositoryProvider).watchAll(),
);

/// Progress of every active goal.
final savingsProgressProvider = FutureProvider<List<SavingsProgress>>((ref) async {
  final today = ref.watch(clockProvider)(); // read before any await
  final goals = ref.watch(savingsGoalsProvider.future);
  final transactions = ref.watch(allTransactionsProvider.future);
  return SavingsCalculator.progress(await goals, await transactions, today: today);
});

final savingsActionsProvider = Provider<SavingsActions>(SavingsActions.new);

/// Write-side use cases for savings goals. Widgets call these, never repositories.
class SavingsActions {
  SavingsActions(this._ref);

  final Ref _ref;

  /// Creates a goal when [id] is null, otherwise updates it.
  Future<void> saveGoal({String? id, required String name, required Money target, DateTime? targetDate}) =>
      _ref.read(savingsGoalRepositoryProvider).save(
            SavingsGoal(id: id ?? newId(), name: name, target: target, targetDate: targetDate),
          );

  /// Money already in the goal stays counted as saved.
  Future<void> archive(String id) => _ref.read(savingsGoalRepositoryProvider).archive(id);

  Future<void> deposit(String goalId, Money amount, {DateTime? date}) async {
    final goal = await _goal(goalId, amount);
    await _record(goal, TransactionType.savings, amount, date);
  }

  /// Throws [ArgumentError] when [amount] exceeds what the goal holds.
  // ponytail: check-then-insert is not atomic; fine for one user on one device,
  // move into a DB transaction when sync allows concurrent writers.
  Future<void> withdraw(String goalId, Money amount) async {
    final goal = await _goal(goalId, amount);
    final transactions = await _ref.read(transactionRepositoryProvider).watchAll().first;
    final saved = SavingsCalculator.progress([goal], transactions, today: _ref.read(clockProvider)()).single.saved;
    if (amount > saved) throw ArgumentError('exceeds the saved amount', 'amount');
    await _record(goal, TransactionType.savingsWithdrawal, amount, null);
  }

  Future<SavingsGoal> _goal(String goalId, Money amount) async {
    final goals = await _ref.read(savingsGoalRepositoryProvider).watchAll().first;
    final goal = goals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) throw ArgumentError('no active goal', 'goalId');
    if (amount.currency != goal.target.currency) throw ArgumentError('must use the goal currency', 'amount');
    if (!amount.isPositive) throw ArgumentError('must be > 0', 'amount');
    return goal;
  }

  Future<void> _record(SavingsGoal goal, TransactionType type, Money amount, DateTime? date) =>
      _ref.read(transactionRepositoryProvider).save(FinanceTransaction(
            id: newId(),
            type: type,
            amount: amount,
            occurredAt: date ?? _ref.read(clockProvider)(),
            description: goal.name,
            savingsGoalId: goal.id,
          ));
}
