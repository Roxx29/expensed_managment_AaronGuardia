import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_backup.dart';

/// True when the signed-in account's e-mail is verified (Google accounts
/// always are); false when signed out or still pending.
final emailVerifiedProvider = StreamProvider<bool>((ref) async* {
  if (!cloudAvailable) {
    yield false;
    return;
  }
  await ensureCloudReady();
  // userChanges fires again after reload() picks up the verification.
  yield* FirebaseAuth.instance.userChanges().map((u) => u?.emailVerified ?? false);
});

/// Automatic e-mail verification: while an e-mail account is still pending,
/// the app checks every 5 s (in the foreground, for up to 10 min after a
/// launch or a return to the app) whether the link was opened, so nobody has
/// to press "I already verified it". reloadUser() also refreshes the token
/// the Firestore rules read.
final emailVerificationWatcherProvider = Provider<void>((ref) {
  if (!cloudAvailable) return;
  Timer? timer;
  var checks = 0;
  const maxChecks = 120; // 10 min at 5 s

  void stop() {
    timer?.cancel();
    timer = null;
  }

  bool pending() {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.emailVerified;
  }

  Future<void> check() async {
    if (!pending() || ++checks > maxChecks) return stop();
    try {
      await ref.read(cloudBackupProvider).reloadUser();
    } on Object {
      // Offline: the next tick tries again.
    }
    if (!pending()) stop();
  }

  void start() {
    if (!pending()) return stop();
    checks = 0;
    timer ??= Timer.periodic(const Duration(seconds: 5), (_) => unawaited(check()));
    unawaited(check());
  }

  ref.listen(emailVerifiedProvider, (_, next) {
    if (next.value == false) start();
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(onResume: start, onPause: stop);
  ref.onDispose(() {
    stop();
    lifecycle.dispose();
  });
});
