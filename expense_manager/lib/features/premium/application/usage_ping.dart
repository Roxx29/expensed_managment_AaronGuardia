import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/usage/active_days.dart';
import '../../../domain/usage/feature_counts.dart';
import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';
import 'crash_reporting.dart';

const _daysKey = 'usage.active_days';
const _featuresKey = 'usage.features';

/// Counts feature use on this phone (`usage.features`); the ping sends the
/// totals. Off Android (tests) it does nothing.
final usageTrackerProvider = Provider<UsageTracker>(UsageTracker.new);

class UsageTracker {
  UsageTracker(this._ref);

  final Ref _ref;
  Future<void> _queue = Future.value();

  /// One more use of [feature] (a fixed name, never user data).
  void track(String feature) {
    if (!cloudAvailable) return;
    // Queued so two quick events never overwrite each other's count.
    _queue = _queue.then((_) => _bump(feature)).catchError((Object _) {});
  }

  Future<void> _bump(String feature, [int times = 1]) async {
    final settings = _ref.read(settingsRepositoryProvider);
    var counts = parseFeatures(await settings.read(_featuresKey));
    for (var i = 0; i < times; i++) {
      counts = bumpFeature(counts, feature);
    }
    await settings.write(_featuresKey, encodeFeatures(counts));
  }

  /// Adds the crash of the last run and the errors caught since the last
  /// ping, then returns the totals.
  Future<Map<String, int>> totals() async {
    if (await crashedLastTime) {
      crashedLastTime = Future.value(false);
      await _bump('crash');
    }
    final errors = pendingErrors;
    pendingErrors = 0;
    if (errors > 0) await _bump('error', errors);
    await _queue;
    return parseFeatures(await _ref.read(settingsRepositoryProvider).read(_featuresKey));
  }
}

/// Usage numbers for the admin panel (admin_web, "Métricas"): on launch and
/// when the app returns after 30+ minutes, a signed-in user's row
/// `users/<uid>` gets `opens + 1`, the last 60 active days and the feature
/// counts (`features`, incl. `crash`/`error`). Nothing for
/// signed-out users (privacy) and nothing off Android (tests).
final usagePingProvider = Provider<void>((ref) {
  if (!cloudAvailable) return;
  DateTime? last;
  Future<void> ping() async {
    final now = DateTime.now();
    if (last != null && now.difference(last!) < const Duration(minutes: 30)) return;
    last = now;
    try {
      await ensureCloudReady();
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) return;
      final settings = ref.read(settingsRepositoryProvider);
      final days = addActiveDay(parseActiveDays(await settings.read(_daysKey)), now);
      await settings.write(_daysKey, days.join(','));
      // update(), not set(): the row is created by giftPremiumProvider (with
      // createdAt); before that the ping is simply skipped.
      await FirebaseFirestore.instance.doc('users/${user.uid}').update({
        'opens': FieldValue.increment(1),
        'activeDays': days,
        'features': await ref.read(usageTrackerProvider).totals(),
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } on Object {
      // Offline or no row yet: next launch.
    }
  }

  unawaited(ping());
  final listener = AppLifecycleListener(onResume: () => unawaited(ping()));
  ref.onDispose(listener.dispose);
});
