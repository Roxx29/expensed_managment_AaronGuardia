import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/usage/active_days.dart';
import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';

const _daysKey = 'usage.active_days';

/// Usage numbers for the admin panel (admin_web, "Métricas"): on launch and
/// when the app returns after 30+ minutes, a signed-in user's row
/// `users/<uid>` gets `opens + 1` and the last 60 active days. Nothing for
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
