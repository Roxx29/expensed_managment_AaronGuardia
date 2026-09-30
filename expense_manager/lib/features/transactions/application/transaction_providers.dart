import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/finance/transaction_filter.dart';
import '../../../shared/providers/providers.dart';

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

final transactionActionsProvider = Provider<TransactionActions>(TransactionActions.new);

/// Write-side use cases for transactions. Widgets call these, never repositories.
class TransactionActions {
  TransactionActions(this._ref);

  final Ref _ref;

  Future<void> save(FinanceTransaction tx) =>
      _ref.read(transactionRepositoryProvider).save(tx);

  Future<void> delete(String id) => _ref.read(transactionRepositoryProvider).delete(id);

  /// Undo for [delete]: saving again clears the soft-delete marker.
  Future<void> restore(FinanceTransaction tx) => save(tx);
}
