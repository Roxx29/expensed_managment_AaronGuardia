import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../data/backup/backup_codec.dart';
import '../../../data/backup/backup_crypto.dart';
import 'backup_providers.dart';

// Firebase settings come from `--dart-define-from-file` in CI (secret
// FIREBASE_DEFINES), so the public repository holds no project keys.
const _apiKey = String.fromEnvironment('FB_API_KEY');
const _appId = String.fromEnvironment('FB_APP_ID');
const _senderId = String.fromEnvironment('FB_SENDER_ID');
const _projectId = String.fromEnvironment('FB_PROJECT_ID');
const _bucket = String.fromEnvironment('FB_BUCKET');
const _webClientId = String.fromEnvironment('FB_WEB_CLIENT_ID');

/// Android builds made with the Firebase settings (not tests, not local builds).
bool get cloudAvailable => _apiKey.isNotEmpty && _webClientId.isNotEmpty && Platform.isAndroid;

Future<void>? _ready;

/// Starts Firebase and Google sign-in once; a failure is retried next call.
Future<void> ensureCloudReady() => _ready ??= () async {
      try {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
            storageBucket: _bucket,
          ),
        );
        await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
      } on Object {
        _ready = null;
        rethrow;
      }
    }();

/// E-mail of the signed-in cloud account, null when signed out.
final cloudUserProvider = StreamProvider<String?>((ref) async* {
  if (!cloudAvailable) {
    yield null;
    return;
  }
  await ensureCloudReady();
  yield* FirebaseAuth.instance.authStateChanges().map((u) => u?.email);
});

final cloudBackupProvider = Provider<CloudBackup>(CloudBackup.new);

/// One backup per account at `users/<uid>/backup.enc.json`, always encrypted
/// on the phone with the user's passphrase (backup_crypto.dart) before upload.
// ponytail: manual upload only (the passphrase is asked each time); automatic
// cloud uploads need the passphrase kept in secure storage.
class CloudBackup {
  CloudBackup(this._ref);

  final Ref _ref;

  User get _user => FirebaseAuth.instance.currentUser ?? (throw StateError('Not signed in'));

  Reference _file(User user) => FirebaseStorage.instance.ref('users/${user.uid}/backup.enc.json');

  /// Returns false when the user closes the Google account picker.
  Future<bool> signIn() async {
    await ensureCloudReady();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    await FirebaseAuth.instance
        .signInWithCredential(GoogleAuthProvider.credential(idToken: account.authentication.idToken));
    return true;
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }

  /// Replaces the cloud backup with the current data.
  Future<void> upload(String passphrase) async {
    final encrypted = await encryptBackup(await _ref.read(backupServiceProvider).encode(), passphrase);
    await _file(_user).putString(encrypted, metadata: SettableMetadata(contentType: 'application/json'));
  }

  /// Returns false when the passphrase prompt is cancelled.
  Future<bool> restore({required Future<String?> Function() askPassphrase}) async {
    final bytes = await _file(_user).getData(BackupCodec.maxBytes * 2);
    final content = utf8.decode(bytes ?? const <int>[]);
    if (!isEncryptedBackup(content)) throw const BackupException(BackupError.notABackup);
    final passphrase = await askPassphrase();
    if (passphrase == null) return false;
    await _ref.read(backupServiceProvider).restoreFromContent(await decryptBackup(content, passphrase));
    return true;
  }

  /// Deletes the cloud backup and the account (Google Play requires in-app
  /// account deletion). Local data on the phone is kept.
  Future<void> deleteAccount() async {
    final user = _user;
    try {
      await _file(user).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
    try {
      // The admin panel row (refused for blocked accounts: the admin keeps it).
      await FirebaseFirestore.instance.doc('users/${user.uid}').delete();
    } on FirebaseException {
      // Best effort; the account itself is deleted next.
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      // Re-authenticates this same user; another Google account fails with
      // `user-mismatch` instead of being deleted.
      final account = await GoogleSignIn.instance.authenticate();
      await user.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: account.authentication.idToken));
      await user.delete();
    }
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      // The account is already gone; forgetting the Google choice is optional.
    }
  }
}
