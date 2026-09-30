import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/dashboard.dart';
import '../../../shared/providers/providers.dart';

// ponytail: month is read once per provider build; refreshes on any data change
// or app restart. Add a midnight timer if users keep the app open across months.
final _dashboardMonthProvider = Provider<YearMonth>(
  (ref) => YearMonth.fromDate(ref.watch(clockProvider)()),
);

final _dashboardTransactionsProvider = StreamProvider<List<FinanceTransaction>>((ref) {
  final month = ref.watch(_dashboardMonthProvider);
  final from = month.addMonths(-DashboardComposer.historyMonths).start;
  return ref.watch(transactionRepositoryProvider).watchBetween(from, month.endExclusive);
});

final _dashboardBudgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchForMonth(ref.watch(_dashboardMonthProvider)),
);

final _totalsProvider = StreamProvider<Map<TransactionType, Money>>((ref) =>
    ref.watch(transactionRepositoryProvider).watchTotalsByType(ref.watch(currencyProvider)));

final recentTransactionsProvider = StreamProvider<List<FinanceTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchRecent(limit: 8),
);

/// Recomputes whenever any underlying table changes.
final dashboardProvider = FutureProvider<DashboardSnapshot>((ref) async {
  // Watch all sources before awaiting so every dependency is registered.
  final transactions = ref.watch(_dashboardTransactionsProvider.future);
  final budgets = ref.watch(_dashboardBudgetsProvider.future);
  final recurring = ref.watch(recurringItemsProvider.future);
  final totals = ref.watch(_totalsProvider.future);
  final currency = ref.watch(currencyProvider);
  final engine = ref.watch(insightsEngineProvider);
  final today = ref.watch(clockProvider)();

  return DashboardComposer.compose(
    today: today,
    currency: currency,
    transactions: await transactions,
    budgets: await budgets,
    recurringItems: await recurring,
    totalsByType: await totals,
    insightsEngine: engine,
  );
});
