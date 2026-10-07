import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../backup/application/cloud_backup.dart';

/// Errors caught since the last usage ping (sent to the admin panel as
/// `features.error`; details go to Firebase Crashlytics).
int pendingErrors = 0;

/// True when the app crashed the previous time it ran (Crashlytics knows it
/// on the next launch). The usage ping counts it as `features.crash`.
Future<bool> crashedLastTime = Future.value(false);

/// Sends crashes and uncaught errors to Firebase Crashlytics (Firebase
/// console › Crashlytics). Android with Firebase only; never in tests.
/// Crashlytics gets no user data: no ids, no e-mail, no amounts.
void installCrashReporting() {
  if (!cloudAvailable) return;
  void record(Object error, StackTrace? stack, {required bool fatal}) {
    pendingErrors++;
    if (Firebase.apps.isEmpty) return; // Firebase still starting: counted only
    unawaited(FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal));
  }

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    record(details.exception, details.stack, fatal: false);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    record(error, stack, fatal: true);
    return true;
  };
  crashedLastTime = () async {
    try {
      await ensureCloudReady();
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      return await crashlytics.didCrashOnPreviousExecution();
    } on Object {
      return false;
    }
  }();
}
