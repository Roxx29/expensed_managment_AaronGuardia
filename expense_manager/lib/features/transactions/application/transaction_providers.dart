import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/finance/savings_calculator.dart';
import '../../../domain/finance/transaction_filter.dart';
import '../../../shared/providers/providers.dart';
import '../../wallets/application/wallet_cloud.dart';

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(TransactionFilterNotifier.new);

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void set(TransactionFilter filter) => state = filter;

  void reset() => state = TransactionFilter(sort: state.sort);
}

/// History after search/filter/sort.
final filteredTransactionsProvider = Provider<AsyncValue<List<FinanceTransaction>>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final names = {
    for (final c in ref.watch(categoryByIdProvider).values) c.id: c.name,
  };
  return ref
      .watch(allTransactionsProvider)
      .whenData((list) => filter.apply(list, categoryNames: names));
});

/// autoDispose: each visit to the edit screen reads the current row.
final transactionByIdProvider = FutureProvider.autoDispose.family<FinanceTransaction?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).getById(id),
);

/// Deleting this deposit would leave its savings goal below zero.
class SavingsGoalWouldBeNegative implements Exception {
  const SavingsGoalWouldBeNegative();
}

final transactionActionsProvider = Provider<TransactionActions>(TransactionActions.new);

/// Write-side use cases for transactions. Widgets call these, never repositories.
class TransactionActions {
  TransactionActions(this._ref);

  final Ref _ref;

  Future<void> save(FinanceTransaction tx) async {
    await _ref.read(transactionRepositoryProvider).save(tx);
    _shareChange(tx.walletId);
  }

  /// Throws [SavingsGoalWouldBeNegative] for a deposit that was already withdrawn.
  Future<void> delete(String id) async {
    final repo = _ref.read(transactionRepositoryProvider);
    final tx = await repo.getById(id);
    if (tx != null && !SavingsCalculator.canDelete(tx, await repo.watchAll().first)) {
      throw const SavingsGoalWouldBeNegative();
    }
    await repo.delete(id);
    _shareChange(tx?.walletId);
  }

  /// A change in a shared wallet is sent to the other members right away
  /// (in the background; offline it goes with the next sync).
  void _shareChange(String? walletId) {
    if (walletId == null || currentUid == null) return;
    unawaited(() async {
      try {
        final wallets = await _ref.read(walletRepositoryProvider).watchAll().first;
        final wallet = wallets.where((w) => w.id == walletId).firstOrNull;
        if (wallet != null) await _ref.read(walletCloudProvider).sync(wallet);
      } on Object {
        // Offline: it goes with the next sync.
      }
    }());
  }

  /// Undo for [delete]: saving again clears the soft-delete marker.
  Future<void> restore(FinanceTransaction tx) => save(tx);
}
