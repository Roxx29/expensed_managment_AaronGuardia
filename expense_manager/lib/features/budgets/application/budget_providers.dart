import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../shared/providers/providers.dart';

/// Month shown on the Budgets screen.
final budgetMonthProvider = NotifierProvider<BudgetMonthNotifier, YearMonth>(BudgetMonthNotifier.new);

class BudgetMonthNotifier extends Notifier<YearMonth> {
  @override
  YearMonth build() => YearMonth.fromDate(ref.watch(clockProvider)());

  void previous() => state = state.previous;
  void next() => state = state.next;
}

final _monthTransactionsProvider = StreamProvider.autoDispose.family<List<FinanceTransaction>, YearMonth>(
  (ref, month) => ref.watch(transactionRepositoryProvider).watchBetween(month.start, month.endExclusive),
);

final _monthBudgetsProvider = StreamProvider.autoDispose.family<List<Budget>, YearMonth>(
  (ref, month) => ref.watch(budgetRepositoryProvider).watchForMonth(month),
);

final budgetReportProvider = FutureProvider<MonthlyBudgetReport>((ref) async {
  final month = ref.watch(budgetMonthProvider);
  final currency = ref.watch(currencyProvider); // read before any await
  final transactions = ref.watch(_monthTransactionsProvider(month).future);
  final budgets = ref.watch(_monthBudgetsProvider(month).future);
  return BudgetCalculator.monthlyReport(
    budgets: await budgets,
    transactions: await transactions,
    month: month,
    currency: currency,
  );
});

final budgetActionsProvider = Provider<BudgetActions>(BudgetActions.new);

/// Budget changes apply from the selected month onwards; earlier months keep
/// the amount they had.
class BudgetActions {
  BudgetActions(this._ref);

  final Ref _ref;

  Future<void> setBudget({String? categoryId, required Money amount}) =>
      _ref.read(budgetRepositoryProvider).setBudget(
            categoryId: categoryId,
            amount: amount,
            fromMonth: _ref.read(budgetMonthProvider),
          );

  Future<void> removeBudget({String? categoryId}) => _ref
      .read(budgetRepositoryProvider)
      .removeBudget(categoryId: categoryId, fromMonth: _ref.read(budgetMonthProvider));
}
