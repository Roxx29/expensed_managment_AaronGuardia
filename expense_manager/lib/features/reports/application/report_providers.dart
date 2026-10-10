import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';

/// Build number set by CI (`--dart-define=APP_BUILD=<run>`).
const _appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'local');

/// Fixed names: the same list is checked by firebase/firestore.rules.
const reportCategories = ['error', 'backup', 'sync', 'payments', 'other'];
const reportMinLength = 10;
const reportMaxLength = 1000;

/// A ticket is sent as `reports/<auto id>` and read in the admin panel (Reportes).
final reportActionsProvider = Provider<ReportActions>(ReportActions.new);

class ReportActions {
  ReportActions(this._ref);

  final Ref _ref;

  /// Sends a ticket with the signed-in user's name, e-mail, time and [reason].
  /// Throws [StateError] when nobody is signed in or [reason] has a bad length.
  // shortcut: no per-user rate limit (the rules only cap size), add one if tickets get spammed.
  Future<void> send({required String category, required String reason}) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    final text = reason.trim();
    if (user == null || email == null) throw StateError('Not signed in');
    if (text.length < reportMinLength || text.length > reportMaxLength || !reportCategories.contains(category)) {
      throw StateError('Invalid report');
    }
    final profileName = (_ref.read(profileProvider).value?.name ?? '').trim();
    final name = profileName.isNotEmpty ? profileName : (user.displayName ?? '').trim();
    await FirebaseFirestore.instance.collection('reports').add({
      'uid': user.uid,
      'email': email,
      'name': name.length > 80 ? name.substring(0, 80) : name,
      'category': category,
      'reason': text,
      'appBuild': _appBuild,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Signed-in e-mail, or null (also in builds without Firebase).
final reportEmailProvider = Provider<String?>((ref) => cloudAvailable ? ref.watch(cloudUserProvider).value : null);
