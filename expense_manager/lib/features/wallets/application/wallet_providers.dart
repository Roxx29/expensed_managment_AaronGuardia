import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/summary_calculator.dart';
import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';
import 'wallet_cloud.dart';

/// Shared wallets this user belongs to, A–Z.
final walletsProvider = StreamProvider<List<Wallet>>((ref) => ref.watch(walletRepositoryProvider).watchAll());

final walletByIdProvider = Provider.family<Wallet?, String>(
  (ref, id) => ref.watch(walletsProvider).value?.where((w) => w.id == id).firstOrNull,
);

/// A wallet's entries, newest first.
final walletTransactionsProvider = StreamProvider.family<List<FinanceTransaction>, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchWallet(id),
);

/// This month's income/expenses of a wallet in the user's currency.
final walletMonthSummaryProvider = Provider.family<MonthSummary?, String>((ref, id) {
  final transactions = ref.watch(walletTransactionsProvider(id)).value;
  if (transactions == null) return null;
  return SummaryCalculator.month(
    transactions: transactions,
    month: YearMonth.fromDate(ref.watch(clockProvider)()),
    currency: ref.watch(currencyProvider),
  );
});

/// Members (name + photo) of a wallet; empty when offline or signed out.
final walletMembersProvider = FutureProvider.family<Map<String, WalletMember>, String>((ref, id) async {
  // Re-read only when the key changes, not on every wallet-table update.
  if (ref.watch(walletByIdProvider(id).select((w) => w?.secret)) == null) return const {};
  final wallet = ref.read(walletByIdProvider(id));
  if (wallet == null) return const {};
  try {
    return await ref.read(walletCloudProvider).members(wallet);
  } on Object {
    return const {};
  }
});

/// Syncs every wallet on launch and when the app returns to the foreground
/// (at most once a minute), so entries from the other members show up.
final walletAutoSyncProvider = Provider<void>((ref) {
  if (!cloudAvailable) return;
  DateTime? last;
  void run() {
    final now = DateTime.now();
    if (last != null && now.difference(last!) < const Duration(minutes: 1)) return;
    last = now;
    unawaited(ref.read(walletCloudProvider).syncAllQuietly());
  }

  run();
  final listener = AppLifecycleListener(onResume: run);
  ref.onDispose(listener.dispose);
});
