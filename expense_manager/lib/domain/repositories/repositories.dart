/// Repository contracts. The UI and use cases depend on these; `data/`
/// provides the local (Drift) implementations. A cloud-synced implementation
/// can be swapped in with a provider override.
library;

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';

abstract interface class TransactionRepository {
  /// Transactions with `from <= occurredAt < toExclusive`, newest first.
  Stream<List<FinanceTransaction>> watchBetween(DateTime from, DateTime toExclusive);

  Stream<List<FinanceTransaction>> watchRecent({int limit = 10});

  /// Every non-deleted transaction of the user's own money (not in a shared
  /// wallet), newest first. The other personal queries skip wallets too.
  Stream<List<FinanceTransaction>> watchAll();

  /// Non-deleted entries of the shared wallet [walletId], newest first.
  Stream<List<FinanceTransaction>> watchWallet(String walletId);

  Future<FinanceTransaction?> getById(String id);

  /// All-time totals per type in [currency] (for the available balance).
  Stream<Map<TransactionType, Money>> watchTotalsByType(Currency currency);

  /// Inserts or updates (also restores a soft-deleted row, used by "undo").
  /// Throws [ArgumentError] on invalid data.
  Future<void> save(FinanceTransaction transaction);

  /// Soft delete (kept for sync).
  Future<void> delete(String id);

  /// Inserts only transactions whose ID does not exist yet (deleted ones
  /// included). Used for idempotent auto-posting of recurring items.
  Future<void> insertMissing(List<FinanceTransaction> transactions);
}

abstract interface class WalletRepository {
  /// Wallets the user belongs to (not left), A–Z.
  Stream<List<Wallet>> watchAll();

  /// [placeholder]: dated 2000-01-01 so the real wallet row from the first
  /// sync wins the merge (used right after joining).
  Future<void> save(Wallet wallet, {bool placeholder = false});

  /// Soft delete ("Leave wallet"); its entries stay hidden in the database.
  Future<void> delete(String id);

  /// Sets the owner from the cloud (the only trusted source) without
  /// touching `updatedAt`, so it never wins or triggers a sync by itself.
  Future<void> setOwner(String id, String ownerUid);
}

abstract interface class CategoryRepository {
  Stream<List<FinanceCategory>> watchAll({bool includeArchived = false});
  Future<void> save(FinanceCategory category);
  Future<void> archive(String id);
}

abstract interface class PaymentMethodRepository {
  Stream<List<PaymentMethod>> watchAll({bool includeArchived = false});
  Future<void> save(PaymentMethod method);
  Future<void> archive(String id);
}

abstract interface class BudgetRepository {
  /// Budgets whose month range includes [month].
  Stream<List<Budget>> watchForMonth(YearMonth month);

  /// Sets the budget for [categoryId] (null = global) from [fromMonth] on,
  /// preserving earlier months' amounts.
  Future<void> setBudget({
    required String? categoryId,
    required Money amount,
    required YearMonth fromMonth,
  });

  /// Stops the budget from [fromMonth] on.
  Future<void> removeBudget({required String? categoryId, required YearMonth fromMonth});
}

abstract interface class RecurringItemRepository {
  Stream<List<RecurringItem>> watchAll({RecurringKind? kind});
  Future<void> save(RecurringItem item);
  Future<void> delete(String id);
}

abstract interface class ProfileRepository {
  Stream<Profile> watch();
  Future<void> save(Profile profile);
}

abstract interface class SettingsRepository {
  Stream<String?> watch(String key);
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
