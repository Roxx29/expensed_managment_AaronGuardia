import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../data/backup/backup_codec.dart';
import '../../../data/backup/backup_crypto.dart';
import '../../../domain/backup/backup_policy.dart';
import '../../../shared/providers/providers.dart';
import '../../premium/application/premium_providers.dart';
import 'backup_providers.dart';

// Firebase project settings. They ship inside every APK and are not secret
// (firebase/firestore.rules protects the data); a CI
// `--dart-define=FB_...` can still override them.
const _apiKey = String.fromEnvironment('FB_API_KEY', defaultValue: 'AIzaSyBkezYd2AHIb3hAr34EAz_CqQk-9_rJUGU');
const _appId = String.fromEnvironment('FB_APP_ID', defaultValue: '1:699143520703:android:f364c0261158b82559a10a');
const _senderId = String.fromEnvironment('FB_SENDER_ID', defaultValue: '699143520703');
const _projectId = String.fromEnvironment('FB_PROJECT_ID', defaultValue: 'monchi-fb5e9');
const _bucket = String.fromEnvironment('FB_BUCKET', defaultValue: 'monchi-fb5e9.firebasestorage.app');
// OAuth "Web client" of the project (Firebase › Authentication › Google ›
// Web SDK configuration). Google sign-in needs it on Android.
const _webClientId = String.fromEnvironment(
  'FB_WEB_CLIENT_ID',
  defaultValue: '699143520703-rtr1opuhkvgpdg103g4ecqq3pfi6b55m.apps.googleusercontent.com',
);

/// Android with Google sign-in configured (never in tests).
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
  // userChanges also fires when the e-mail gets verified (after reload()).
  yield* FirebaseAuth.instance.userChanges().map((u) => u?.email);
});

final cloudBackupProvider = Provider<CloudBackup>(CloudBackup.new);

/// App setting with the time of this phone's last successful cloud upload.
const lastCloudUploadKey = 'backup.cloud_last_upload';

/// `<uid>:<passphrase>` for automatic uploads, so another account signing in
/// on this phone never inherits it. Secure storage only: never in the
/// database, so it is never inside a backup.
// ponytail: not wiped on an iOS reinstall like the PIN keys (app_lock.dart);
// cloud is Android-only today, add it to that wipe when iOS gets the cloud.
const _autoPassphraseKey = 'cloud.auto_passphrase';
const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// The saved passphrase when it belongs to the signed-in account.
Future<String?> _autoPassphrase() async {
  final saved = await _secure.read(key: _autoPassphraseKey);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (saved == null || uid == null || !saved.startsWith('$uid:')) return null;
  return saved.substring(uid.length + 1);
}

/// When this phone last uploaded its cloud backup; null = never.
final lastCloudUploadProvider = StreamProvider<DateTime?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(lastCloudUploadKey)
      .map((v) => v == null ? null : DateTime.tryParse(v)),
);

const _reminderSnoozeKey = 'backup.cloud_reminder_snoozed_until';

final _reminderSnoozeProvider = StreamProvider<DateTime?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(_reminderSnoozeKey)
      .map((v) => v == null ? null : DateTime.tryParse(v)),
);

/// Home card "Protect your data" (rule: BackupPolicy.shouldRemindCloudBackup).
final cloudBackupReminderProvider = Provider<bool>((ref) {
  if (!cloudAvailable) return false;
  final last = ref.watch(lastCloudUploadProvider);
  final snoozed = ref.watch(_reminderSnoozeProvider);
  final count = ref.watch(allTransactionsProvider.select((t) => t.value?.length ?? 0));
  // Hidden until both settings loaded, so the card never flashes.
  if (!last.hasValue || !snoozed.hasValue) return false;
  return BackupPolicy.shouldRemindCloudBackup(
    lastUpload: last.value,
    snoozedUntil: snoozed.value,
    transactionCount: count,
    now: ref.watch(clockProvider)(),
  );
});

/// `<cloud version>|<local fingerprint>` after the last sync: when both are
/// unchanged, the next sync needs no download.
const _syncedKey = 'backup.cloud_synced';

/// Another phone replaced the cloud copy while this one was syncing.
class CloudChanged implements Exception {
  const CloudChanged();
}

/// Premium "Sync automatically": this phone and the cloud copy are merged
/// on launch, on resume and with "Sync now".
final cloudAutoUploadProvider = FutureProvider<bool>((ref) async {
  // Re-checked when the account changes.
  if (await ref.watch(cloudUserProvider.future) == null) return false;
  return await _autoPassphrase() != null;
});

/// One backup per account in Firestore (no Cloud Storage, so no paid plan):
/// `backups/<uid>` {version, chunks, size, updatedAt} plus the text in
/// `backups/<uid>/chunks/<version>_<i>` (a document holds at most 1 MiB).
/// Always encrypted on the phone with the user's passphrase (backup_crypto.dart).
/// Manual uploads are free; automatic ones (Premium) reuse the passphrase kept
/// in secure storage and run right after an automatic local backup.
class CloudBackup {
  CloudBackup(this._ref);

  final Ref _ref;

  /// Characters per chunk document (base64, so bytes = characters).
  static const chunkSize = 900000;

  /// Same limit as firestore.rules (about 108 MB).
  static const maxChunks = 120;

  User get _user => FirebaseAuth.instance.currentUser ?? (throw StateError('Not signed in'));

  DocumentReference<Map<String, dynamic>> _meta(String uid) => FirebaseFirestore.instance.doc('backups/$uid');

  DocumentReference<Map<String, dynamic>> _chunk(String uid, String version, int i) =>
      FirebaseFirestore.instance.doc('backups/$uid/chunks/${version}_$i');

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

  /// E-mail + password accounts (Firebase › Authentication › Email/Password).
  Future<void> signInWithEmail(String email, String password) async {
    await ensureCloudReady();
    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  /// Creates the account and sends the verification e-mail (gifts and the
  /// admin panel only trust verified e-mails, see firestore.rules).
  Future<void> register(String email, String password, String name) async {
    await ensureCloudReady();
    final credential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim(), password: password);
    // The name shows in shared wallets, tickets and the admin panel.
    await credential.user?.updateDisplayName(name.trim());
    try {
      await credential.user?.sendEmailVerification();
    } on FirebaseAuthException {
      // The account exists; "Send the e-mail again" covers a failed send.
    }
  }

  Future<void> resetPassword(String email) async {
    await ensureCloudReady();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Same answer whether or not the account exists (no e-mail enumeration).
      if (e.code != 'user-not-found') rethrow;
    }
  }

  /// False for an e-mail account that hasn't opened the verification link yet.
  bool get emailVerified => FirebaseAuth.instance.currentUser?.emailVerified ?? false;

  Future<void> resendVerification() async => FirebaseAuth.instance.currentUser?.sendEmailVerification();

  /// Picks up a verification done in the e-mail app (cloudUserProvider updates).
  /// Also refreshes the ID token: firestore.rules read email_verified from it.
  Future<void> reloadUser() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.emailVerified) await user.getIdToken(true);
  }

  Future<void> signOut() async {
    try {
      await disableAutoUpload();
    } on Object {
      // Still sign out; the saved passphrase is bound to this account anyway.
    }
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }

  /// Replaces the cloud backup with the current data. The new chunks are
  /// written first and the old ones deleted last, so a failed upload never
  /// leaves the account without a complete backup. With [expectVersion]
  /// (sync) the copy is only replaced if the cloud still has that version
  /// ('' = none), else [CloudChanged]. Returns the new version.
  Future<String> upload(String passphrase, {String? expectVersion}) async {
    final uid = _user.uid;
    final encrypted = await encryptBackup(await _ref.read(backupServiceProvider).encode(walletKeys: true), passphrase);
    // Always above the version being replaced (even with a phone clock that
    // runs behind), so "older than" in the chunk cleanup means "replaced".
    final floor = int.tryParse(expectVersion ?? '${(await _meta(uid).get()).data()?['version'] ?? ''}') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = (now > floor ? now : floor + 1).toString();
    final chunks = [
      for (var i = 0; i < encrypted.length; i += chunkSize)
        encrypted.substring(i, i + chunkSize < encrypted.length ? i + chunkSize : encrypted.length),
    ];
    if (chunks.length > maxChunks) throw const BackupException(BackupError.tooLarge);
    for (var i = 0; i < chunks.length; i++) {
      await _chunk(uid, version, i).set({'data': chunks[i]});
    }
    final meta = {
      'version': version,
      'chunks': chunks.length,
      'size': encrypted.length,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (expectVersion == null) {
      await _meta(uid).set(meta);
    } else {
      final committed = await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final current = (await tx.get(_meta(uid))).data()?['version'];
        if ('${current ?? ''}' != expectVersion) return false;
        tx.set(_meta(uid), meta);
        return true;
      });
      if (!committed) {
        for (var i = 0; i < chunks.length; i++) {
          await _chunk(uid, version, i).delete();
        }
        throw const CloudChanged();
      }
    }
    await _deleteChunks(uid, olderThan: version);
    await _markUploaded();
    return version;
  }

  /// Merges this phone with the cloud copy (mergeBackups: the newest change
  /// of each row wins, deletions included) and uploads the result when the
  /// cloud lacks something. Retries when another phone or a local edit got
  /// in between; then throws [CloudChanged] / [LocalDataChanged].
  Future<void> sync(String passphrase) async {
    final uid = _user.uid;
    final codec = BackupCodec(_ref.read(appDatabaseProvider));
    final settings = _ref.read(settingsRepositoryProvider);
    for (var attempt = 1;; attempt++) {
      try {
        final meta = (await _meta(uid).get()).data();
        final cloudVersion = '${meta?['version'] ?? ''}';
        final before = await codec.fingerprint();
        if (meta != null && await settings.read(_syncedKey) == '$cloudVersion|$before') return;
        // A damaged copy (BackupError.corrupted) is never replaced here: the
        // user can do it knowingly with "Upload to the cloud".
        ValidatedBackup? remote;
        if (meta != null) {
          try {
            remote = await BackupCodec.validate(await decryptBackup(await _download(uid, meta), passphrase));
          } on BackupException catch (e) {
            // A chunk vanished because another phone replaced the copy meanwhile: merge again.
            final latest = '${(await _meta(uid).get()).data()?['version'] ?? ''}';
            if (e.error == BackupError.corrupted && latest != cloudVersion) throw const CloudChanged();
            rethrow;
          }
        }
        final result = remote == null ? null : mergeBackups(await BackupCodec.validate(await codec.encode(walletKeys: true)), remote);
        var synced = before;
        if (result != null && result.localChanged) {
          await codec.restore(result.merged, keepSettings: true, expectFingerprint: before);
          synced = await codec.fingerprint();
        }
        // Taken before the upload encodes the data: an edit made meanwhile
        // changes the fingerprint, so the next sync uploads it.
        final version = result == null || result.remoteChanged
            ? await upload(passphrase, expectVersion: cloudVersion)
            : cloudVersion;
        if (version == cloudVersion) await _markUploaded();
        await settings.write(_syncedKey, '$version|$synced');
        return;
      } on CloudChanged {
        if (attempt >= 3) rethrow;
      } on LocalDataChanged {
        if (attempt >= 3) rethrow;
      }
    }
  }

  Future<void> _markUploaded() =>
      _ref.read(settingsRepositoryProvider).write(lastCloudUploadKey, _ref.read(clockProvider)().toIso8601String());

  /// "Later" on the Home reminder.
  Future<void> snoozeReminder() => _ref
      .read(settingsRepositoryProvider)
      .write(_reminderSnoozeKey, _ref.read(clockProvider)().add(BackupPolicy.remindSnooze).toIso8601String());

  Future<void> enableAutoUpload(String passphrase) async {
    await _secure.write(key: _autoPassphraseKey, value: '${_user.uid}:$passphrase');
    _ref.invalidate(cloudAutoUploadProvider);
  }

  Future<void> disableAutoUpload() async {
    await _secure.delete(key: _autoPassphraseKey);
    _ref.invalidate(cloudAutoUploadProvider);
  }

  DateTime? _lastAutoSync;

  /// Premium automatic sync with the saved passphrase, at most every
  /// 2 minutes; does nothing when it is off or nobody is signed in.
  Future<void> syncIfAuto() async {
    if (!cloudAvailable || !_ref.read(premiumProvider)) return;
    final now = DateTime.now();
    final last = _lastAutoSync;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) return;
    _lastAutoSync = now;
    await ensureCloudReady();
    // Firebase restores the signed-in user asynchronously after launch.
    if (await FirebaseAuth.instance.authStateChanges().first == null) return;
    final passphrase = await _autoPassphrase();
    if (passphrase != null) await sync(passphrase);
  }

  /// "Sync now" with the saved passphrase.
  Future<void> syncNow() async {
    final passphrase = await _autoPassphrase();
    if (passphrase == null) throw StateError('Automatic sync is off');
    await sync(passphrase);
  }

  /// Deletes the chunks of versions older than [olderThan] (all when null),
  /// also ones a failed upload left. Newer ones may belong to another phone's
  /// upload in progress (versions only grow, see upload).
  Future<void> _deleteChunks(String uid, {String? olderThan}) async {
    final limit = olderThan == null ? null : int.parse(olderThan);
    final all = await FirebaseFirestore.instance.collection('backups/$uid/chunks').get();
    for (final d in all.docs) {
      final v = int.tryParse(d.id.split('_').first) ?? 0;
      if (limit == null || v < limit) await d.reference.delete();
    }
  }

  /// The encrypted text of the cloud copy described by [meta].
  Future<String> _download(String uid, Map<String, dynamic> meta) async {
    final content = StringBuffer();
    for (var i = 0; i < (meta['chunks'] as num).toInt(); i++) {
      final part = (await _chunk(uid, '${meta['version']}', i).get()).data()?['data'];
      // Missing while another phone replaces the backup: try again later.
      if (part is! String) throw const BackupException(BackupError.corrupted);
      content.write(part);
    }
    final text = content.toString();
    if (text.length > BackupCodec.maxBytes * 2 || !isEncryptedBackup(text)) {
      throw const BackupException(BackupError.notABackup);
    }
    return text;
  }

  /// When this account's cloud backup was last uploaded; null when none.
  Future<DateTime?> backupDate() async {
    final meta = (await _meta(_user.uid).get()).data();
    if (meta == null) return null;
    final at = meta['updatedAt'];
    return at is Timestamp ? at.toDate() : DateTime.now();
  }

  /// Returns false when the passphrase prompt is cancelled.
  Future<bool> restore({required Future<String?> Function() askPassphrase}) async {
    final uid = _user.uid;
    final meta = (await _meta(uid).get()).data();
    if (meta == null) throw FirebaseException(plugin: 'monchi', code: 'not-found');
    final text = await _download(uid, meta);
    final passphrase = await askPassphrase();
    if (passphrase == null) return false;
    await _ref.read(backupServiceProvider).restoreFromContent(await decryptBackup(text, passphrase));
    // The restored settings carry an older upload date; this phone now
    // matches the cloud copy.
    await _markUploaded();
    return true;
  }

  /// Deletes the cloud backup and the account (Google Play requires in-app
  /// account deletion). Local data on the phone is kept.
  Future<void> deleteAccount() async {
    final user = _user;
    await _deleteChunks(user.uid);
    await _meta(user.uid).delete();
    try {
      await FirebaseFirestore.instance.doc('profiles/${user.uid}').delete(); // account photo
      // The admin panel row (refused for blocked accounts: the admin keeps it).
      await FirebaseFirestore.instance.doc('users/${user.uid}').delete();
    } on FirebaseException {
      // Best effort; the account itself is deleted next.
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // E-mail accounts must sign in again by hand (backup_screen explains).
      if (e.code != 'requires-recent-login' || !user.providerData.any((p) => p.providerId == 'google.com')) rethrow;
      // Re-authenticates this same user; another Google account fails with
      // `user-mismatch` instead of being deleted.
      final account = await GoogleSignIn.instance.authenticate();
      await user.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: account.authentication.idToken));
      await user.delete();
    }
    await disableAutoUpload();
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      // The account is already gone; forgetting the Google choice is optional.
    }
  }
}
