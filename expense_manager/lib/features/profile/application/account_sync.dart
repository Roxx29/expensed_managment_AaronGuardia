import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';
import '../../premium/application/crash_reporting.dart';
import '../../wallets/application/wallet_cloud.dart';
import 'profile_providers.dart';

/// Hash of the account photo this phone already has ('none' = removed).
/// `security.` keeps it out of backups (it describes this phone only).
const _photoHashKey = 'security.profile_photo_hash';

/// Set once the Google account photo was offered to this phone.
const _googlePhotoKey = 'security.profile_google_photo';

/// Width of the photo kept in the account (PNG, about 15–40 KB in base64).
const _photoWidth = 128;

/// Keeps the profile and the cloud account the same on every phone signed in
/// to it (and on the shared wallets' member cards):
/// - name: Firebase account name; on sign-in the account wins (it holds the
///   latest edit from any phone), an account without a name takes this phone's.
/// - photo: small PNG in `profiles/<uid>` {photo, updatedAt} (Firestore, no
///   Cloud Storage); a removal is synced too (`photo: null`).
final accountProfileSyncProvider = Provider<void>((ref) {
  if (!cloudAvailable) return;
  final settings = ref.read(settingsRepositoryProvider);
  DocumentReference<Map<String, dynamic>> doc(String uid) => FirebaseFirestore.instance.doc('profiles/$uid');

  /// This phone's photo as stored in the account, or null when there is none.
  Future<String?> localPhoto() async {
    final file = await ref.read(avatarFileProvider.future);
    if (file == null) return null;
    final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: _photoWidth);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return png == null ? null : base64.encode(png.buffer.asUint8List());
  }

  String hashOf(String? photo) => photo == null ? 'none' : sha256.convert(utf8.encode(photo)).toString();

  Future<void> pushName(String name) async {
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

  Future<void> pushPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final photo = await localPhoto();
      final hash = hashOf(photo);
      if (await settings.read(_photoHashKey) == hash) return; // the account already has it
      await doc(user.uid).set({'photo': photo, 'updatedAt': FieldValue.serverTimestamp()});
      await settings.write(_photoHashKey, hash);
    } on Object {
      // Offline: the next sign-in or change tries again.
    }
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
        await pushName(local);
      }
    } on Object {
      // Profile not loaded / offline: next launch.
    }
    try {
      // No document yet = no photo in the account (the first phone uploads its own below).
      final photo = (await doc(user.uid).get()).data()?['photo'];
      final cloud = photo is String && photo.length <= 150000 ? photo : null;
      final hash = hashOf(cloud);
      // No photo anywhere yet: start once with the Google account's photo
      // (a photo removed later stays removed).
      final google = user.photoURL;
      if (cloud == null &&
          google != null &&
          await settings.read(_googlePhotoKey) == null &&
          await ref.read(avatarFileProvider.future) == null) {
        await settings.write(_googlePhotoKey, '1');
        final bytes = await _download(google);
        if (bytes != null) {
          await ref.read(profileActionsProvider).setPhotoBytes(bytes); // the avatar listener uploads it
          return;
        }
      }
      final last = await settings.read(_photoHashKey);
      if (last == hash) return; // already in sync
      // A phone that never synced keeps its own photo instead of losing it to
      // an empty account (e.g. the account was first used on a phone without one).
      if (cloud == null && last == null) {
        await pushPhoto();
        return;
      }
      // Hash first, so the avatar change below is not uploaded back.
      await settings.write(_photoHashKey, hash);
      final actions = ref.read(profileActionsProvider);
      if (cloud == null) {
        await actions.removePhoto();
      } else {
        await actions.setPhotoBytes(base64.decode(cloud));
      }
    } on FirebaseException catch (e, stack) {
      // Offline: next launch. Anything else (e.g. rules not published) must be seen.
      if (e.code != 'unavailable') reportCaughtError(e, stack, 'profile photo sync');
    } on Object catch (e, stack) {
      reportCaughtError(e, stack, 'profile photo sync');
    }
  }

  ref.listen(cloudUserProvider, (_, next) {
    if (next.value != null) unawaited(pull());
  }, fireImmediately: true);
  ref.listen(profileProvider.select((p) => p.value?.name.trim()), (previous, next) {
    if (previous != null && next != null && next != previous) unawaited(pushName(next));
  });
  ref.listen(profileProvider.select((p) => p.value?.avatarPath), (previous, next) {
    if (previous != next) unawaited(pushPhoto());
  });
});

/// Bytes at [url] (the Google account photo, a few KB), or null on any error.
Future<List<int>?> _download(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) return null; // not a profile photo
    }
    return bytes;
  } on Object {
    return null;
  } finally {
    client.close();
  }
}
