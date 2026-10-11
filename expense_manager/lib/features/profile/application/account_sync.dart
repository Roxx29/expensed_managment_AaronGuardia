import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';
import '../../wallets/application/wallet_cloud.dart';
import 'profile_providers.dart';

/// Keeps the profile name and the cloud account's name the same, so every
/// phone signed in to the account (and every shared wallet) shows it.
/// On sign-in the account wins (it holds the latest edit from any phone);
/// an account without a name takes this phone's. Editing the name here
/// updates the account, the admin panel row and the wallets' member card.
// shortcut: only the name is synced; the photo stays per phone (needs Cloud Storage).
final accountProfileSyncProvider = Provider<void>((ref) {
  if (!cloudAvailable) return;

  Future<void> push(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || name.isEmpty) return;
    try {
      if ((user.displayName ?? '').trim() != name) await user.updateDisplayName(name);
      await FirebaseFirestore.instance.doc('users/${user.uid}').update({'name': name});
    } on Object {
      // Offline or no panel row yet: the next sign-in or edit tries again.
    }
    // New name on the wallets' member cards (best effort, offline-safe).
    unawaited(ref.read(walletCloudProvider).syncAllQuietly());
  }

  Future<void> pull() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final account = (user.displayName ?? '').trim();
      final local = (await ref.read(profileProvider.future)).name.trim();
      if (account.isNotEmpty && account != local) {
        await ref.read(profileActionsProvider).setName(account);
      } else if (account.isEmpty && local.isNotEmpty) {
        await push(local);
      }
    } on Object {
      // Profile not loaded / offline: next launch.
    }
  }

  ref.listen(cloudUserProvider, (_, next) {
    if (next.value != null) unawaited(pull());
  }, fireImmediately: true);
  ref.listen(profileProvider.select((p) => p.value?.name.trim()), (previous, next) {
    if (previous != null && next != null && next != previous) unawaited(push(next));
  });
});
