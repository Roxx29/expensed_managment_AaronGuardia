import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/finance/recurring_poster.dart';
import '../../../shared/providers/providers.dart';

final recurringActionsProvider = Provider<RecurringActions>(RecurringActions.new);

class RecurringActions {
  RecurringActions(this._ref);

  final Ref _ref;

  Future<void> save(RecurringItem item) {
    final items = _ref.read(recurringItemsProvider).value ?? const <RecurringItem>[];
    final previous = items.where((i) => i.id == item.id);
    final toSave = RecurringPoster.withPostingStart(
      previous.isEmpty ? null : previous.first,
      item,
      _ref.read(clockProvider)(),
    );
    return _ref.read(recurringItemRepositoryProvider).save(toSave);
  }

  /// Past generated transactions are kept; only future charges stop.
  Future<void> delete(String id) => _ref.read(recurringItemRepositoryProvider).delete(id);
}

/// Records due recurring charges as expenses. Re-runs whenever the items
/// change; idempotent thanks to deterministic transaction IDs.
// ponytail: runs on launch and on item changes; a background job (WorkManager)
// would post charges while the app stays closed for days — not needed since the
// next launch back-fills them.
final autoPostRecurringProvider = FutureProvider<int>((ref) async {
  final today = ref.watch(clockProvider)(); // read before any await
  final repo = ref.watch(transactionRepositoryProvider);
  final items = await ref.watch(recurringItemsProvider.future);
  final due = RecurringPoster.dueTransactions(items: items, today: today);
  if (due.isEmpty) return 0;
  await repo.insertMissing(due);
  return due.length;
});
