import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/currency.dart';
import '../../core/time/year_month.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/catalog_repositories_impl.dart';
import '../../data/repositories/planning_repositories_impl.dart';
import '../../data/repositories/profile_settings_repositories_impl.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/entities/entities.dart';
import '../../domain/insights/insights.dart';
import '../../domain/repositories/repositories.dart';

/// Dependency wiring. Override any of these in tests or to plug in cloud
/// implementations later (e.g. a synced TransactionRepository).

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => DriftTransactionRepository(ref.watch(appDatabaseProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => DriftCategoryRepository(ref.watch(appDatabaseProvider)),
);

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => DriftPaymentMethodRepository(ref.watch(appDatabaseProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => DriftBudgetRepository(ref.watch(appDatabaseProvider)),
);

final recurringItemRepositoryProvider = Provider<RecurringItemRepository>(
  (ref) => DriftRecurringItemRepository(ref.watch(appDatabaseProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => DriftProfileRepository(ref.watch(appDatabaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Swap for an AI-backed engine later.
final insightsEngineProvider = Provider<InsightsEngine>(
  (ref) => RuleBasedInsightsEngine.withDefaultRules(),
);

// --- Shared read models -------------------------------------------------------

final profileProvider = StreamProvider<Profile>(
  (ref) => ref.watch(profileRepositoryProvider).watch(),
);

/// The user's main currency (defaults to USD until the profile loads).
final currencyProvider = Provider<Currency>(
  (ref) => ref.watch(profileProvider).value?.currency ?? Currency.fallback,
);

/// Active (non-archived) categories, for pickers.
final categoriesProvider = StreamProvider<List<FinanceCategory>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

/// Categories by id — including archived ones, so old transactions keep
/// their labels.
final categoryByIdProvider = Provider<Map<String, FinanceCategory>>((ref) {
  final categories = ref.watch(_allCategoriesProvider).value ?? const [];
  return {for (final c in categories) c.id: c};
});

final _allCategoriesProvider = StreamProvider<List<FinanceCategory>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(includeArchived: true),
);

/// Active payment methods, for pickers.
final paymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Payment methods by id, including archived ones (for editing old records).
final paymentMethodByIdProvider = Provider<Map<String, PaymentMethod>>((ref) {
  final methods = ref.watch(_allPaymentMethodsProvider).value ?? const [];
  return {for (final m in methods) m.id: m};
});

final _allPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(includeArchived: true),
);

final recurringItemsProvider = StreamProvider<List<RecurringItem>>(
  (ref) => ref.watch(recurringItemRepositoryProvider).watchAll(),
);

/// Injectable clock so time-dependent features are testable.
final clockProvider = Provider<Clock>((ref) => systemClock);

/// Full transaction history (history screen and statistics).
final allTransactionsProvider = StreamProvider<List<FinanceTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchAll(),
);
