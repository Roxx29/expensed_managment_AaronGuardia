import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../data/backup/backup_codec.dart';
import '../../../data/backup/backup_crypto.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/wallets/invite_code.dart';
import '../../../shared/providers/providers.dart';
import '../../backup/application/cloud_backup.dart';
import '../../profile/application/profile_providers.dart';

/// Shared wallets (Carteras) in Firestore, see claude/WALLETS.md:
/// - `wallets/<id>` {owner, version, chunks, size, updatedAt} + `chunks/`:
///   the wallet's entries, encrypted on the phone with the wallet key;
/// - `wallets/<id>/members/<uid>` {profile, invite?}: each member's name and
///   photo, encrypted with the wallet key;
/// - `invites/<inviteId>` {walletId}: lets an invited, signed-in user add
///   themselves as a member. The key only travels inside the invite code.
final walletCloudProvider = Provider<WalletCloud>(WalletCloud.new);

/// Name and photo a member published for a wallet.
class WalletMember {
  const WalletMember({required this.uid, required this.name, this.photo});

  final String uid;
  final String name;
  final Uint8List? photo;
}

/// Creating or joining a wallet needs a signed-in account.
class NotSignedIn implements Exception {
  const NotSignedIn();
}

/// The text has no invite code, or the invitation no longer exists.
class InvalidInvite implements Exception {
  const InvalidInvite();
}

/// The signed-in account (null when signed out, or when the cloud is
/// unavailable, e.g. in tests).
String? get currentUid {
  if (!cloudAvailable) return null;
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } on Object {
    return null; // Firebase not started yet
  }
}

class WalletCloud {
  WalletCloud(this._ref);

  final Ref _ref;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _meta(String id) => _db.doc('wallets/$id');

  DocumentReference<Map<String, dynamic>> _chunk(String id, String version, int i) =>
      _db.doc('wallets/$id/chunks/${version}_$i');

  DocumentReference<Map<String, dynamic>> _member(String id, String uid) => _db.doc('wallets/$id/members/$uid');

  Future<User> _signedIn() async {
    if (!cloudAvailable) throw const NotSignedIn();
    await ensureCloudReady();
    // Firebase restores the signed-in user asynchronously after launch.
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) throw const NotSignedIn();
    return user;
  }

  /// A new business/family wallet owned by this account.
  Future<Wallet> create(String name, WalletKind kind) async {
    final user = await _signedIn();
    final wallet = Wallet(id: newId(), name: name.trim(), kind: kind, secret: newWalletSecret(), ownerUid: user.uid);
    await _meta(wallet.id).set({
      'owner': user.uid,
      'version': '',
      'chunks': 0,
      'size': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _member(wallet.id, user.uid).set({
      'profile': await encryptWithSecret(await _profileJson(), wallet.secret),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _ref.read(walletRepositoryProvider).save(wallet);
    await sync(wallet);
    return wallet;
  }

  /// A new invite code for [wallet] (anyone who has it can join).
  Future<String> invite(Wallet wallet) async {
    final user = await _signedIn();
    // 132 random bits; the id is the only secret that opens the invitation.
    final inviteId = newWalletSecret().substring(0, 22);
    await _db.doc('invites/$inviteId').set({
      'walletId': wallet.id,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return inviteCode(inviteId, wallet.secret);
  }

  /// Joins the wallet of the invite code found in [text].
  Future<Wallet> join(String text) async {
    final code = parseInviteCode(text);
    if (code == null) throw const InvalidInvite();
    final user = await _signedIn();
    final walletId = (await _db.doc('invites/${code.inviteId}').get()).data()?['walletId'];
    if (walletId is! String || walletId.isEmpty || walletId.length > 64) throw const InvalidInvite();
    await _member(walletId, user.uid).set({
      'invite': code.inviteId,
      'profile': await encryptWithSecret(await _profileJson(), code.walletKey),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Placeholder until the first sync brings the real name and kind.
    final wallet = Wallet(id: walletId, name: 'Wallet', kind: WalletKind.other, secret: code.walletKey);
    await _ref.read(walletRepositoryProvider).save(wallet, placeholder: true);
    await _ref.read(settingsRepositoryProvider).write(_syncedKey(walletId), '');
    await sync(wallet);
    return wallet;
  }

  /// Removes this account from [wallet] and hides it on this phone. The
  /// others keep using it. [strict] (account deletion): a cloud error is
  /// thrown instead of ignored, so no member record is left behind.
  Future<void> leave(Wallet wallet, {bool strict = false}) async {
    final uid = currentUid;
    if (uid != null) {
      try {
        await _member(wallet.id, uid).delete();
      } on FirebaseException {
        // Offline or already gone: the wallet is hidden anyway.
        if (strict) rethrow;
      }
    }
    await _ref.read(walletRepositoryProvider).delete(wallet.id);
  }

  static String _syncedKey(String walletId) => 'wallet.synced.$walletId';

  static String _profileKey(String walletId) => 'wallet.profile.$walletId';

  /// Wallet snapshots stay small (they are downloaded on every phone).
  static const maxSnapshotChars = 5 * 1024 * 1024;

  static final _version = RegExp(r'^[0-9]{13}$');

  /// Merges this phone's entries of [wallet] with the cloud copy (newest
  /// change per entry wins, deletions included), uploads what the cloud
  /// lacks and publishes this member's name and photo when they changed.
  Future<void> sync(Wallet wallet) async {
    final user = await _signedIn();
    final codec = BackupCodec(_ref.read(appDatabaseProvider));
    final settings = _ref.read(settingsRepositoryProvider);
    for (var attempt = 1;; attempt++) {
      try {
        final meta = (await _meta(wallet.id).get()).data();
        if (meta == null) throw const InvalidInvite(); // deleted in the cloud
        final cloudVersion = '${meta['version'] ?? ''}';
        // Any member can write the metadata: never trust its shape.
        if (cloudVersion.isNotEmpty && !_version.hasMatch(cloudVersion)) {
          throw const BackupException(BackupError.corrupted);
        }
        if (((meta['size'] as num?) ?? 0) > maxSnapshotChars) throw const BackupException(BackupError.tooLarge);
        final before = await codec.walletFingerprint(wallet.id);
        if (cloudVersion.isNotEmpty && await settings.read(_syncedKey(wallet.id)) == '$cloudVersion|$before') break;
        ValidatedBackup? remote;
        if (cloudVersion.isNotEmpty) {
          try {
            final text = await decryptWithSecret(await _download(wallet.id, meta), wallet.secret);
            remote = scopeToWallet(
              await BackupCodec.validate(text),
              wallet.id,
              notAfter: DateTime.now().add(const Duration(days: 1)),
            );
          } on BackupException catch (e) {
            // A chunk vanished because another member replaced the copy meanwhile.
            final latest = '${(await _meta(wallet.id).get()).data()?['version'] ?? ''}';
            if (e.error == BackupError.corrupted && latest != cloudVersion) throw const CloudChanged();
            rethrow;
          }
        }
        final local = await BackupCodec.validate(await codec.encode(walletId: wallet.id));
        // Decided on entries and the wallet row only: categories are added,
        // never compared, so members with different catalogs don't ping-pong.
        final result = remote == null ? null : mergeBackups(_entriesOnly(local), _entriesOnly(remote));
        var synced = before;
        if (result != null && result.localChanged) {
          await codec.applyWallet(
            ValidatedBackup(
              createdAt: remote!.createdAt,
              profiles: const [],
              categories: remote.categories,
              paymentMethods: remote.paymentMethods,
              recurringItems: const [],
              savingsGoals: const [],
              transactions: result.merged.transactions,
              budgets: const [],
              settings: const [],
              wallets: result.merged.wallets,
            ),
            wallet.id,
            secret: wallet.secret,
            expectFingerprint: before,
          );
          synced = await codec.walletFingerprint(wallet.id);
        }
        final version = result == null || result.remoteChanged ? await _upload(wallet, cloudVersion) : cloudVersion;
        await settings.write(_syncedKey(wallet.id), '$version|$synced');
        break;
      } on CloudChanged {
        if (attempt >= 3) rethrow;
      } on LocalDataChanged {
        if (attempt >= 3) rethrow;
      }
    }
    try {
      await _publishProfile(wallet, user.uid);
    } on Object {
      // Best effort: retried on the next sync.
    }
  }

  static ValidatedBackup _entriesOnly(ValidatedBackup b) => ValidatedBackup(
        createdAt: b.createdAt,
        profiles: const [],
        categories: const [],
        paymentMethods: const [],
        recurringItems: const [],
        savingsGoals: const [],
        transactions: b.transactions,
        budgets: const [],
        settings: const [],
        wallets: b.wallets,
      );

  /// Encrypts this wallet's snapshot and replaces the cloud copy only if it
  /// is still [expectVersion] (else [CloudChanged]). Returns the new version.
  // ponytail: same chunk/version logic as CloudBackup.upload; extract a shared
  // "encrypted slot" when a third copy of it appears.
  Future<String> _upload(Wallet wallet, String expectVersion) async {
    final encrypted =
        await encryptWithSecret(await BackupCodec(_ref.read(appDatabaseProvider)).encode(walletId: wallet.id), wallet.secret);
    // Always above the replaced version, so the cleanup only removes old copies.
    if (encrypted.length > maxSnapshotChars) throw const BackupException(BackupError.tooLarge);
    final floor = int.tryParse(expectVersion) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = (now > floor ? now : floor + 1).toString();
    final chunks = [
      for (var i = 0; i < encrypted.length; i += CloudBackup.chunkSize)
        encrypted.substring(i, i + CloudBackup.chunkSize < encrypted.length ? i + CloudBackup.chunkSize : encrypted.length),
    ];
    if (chunks.length > CloudBackup.maxChunks) throw const BackupException(BackupError.tooLarge);
    for (var i = 0; i < chunks.length; i++) {
      await _chunk(wallet.id, version, i).set({'data': chunks[i]});
    }
    final committed = await _db.runTransaction<bool>((tx) async {
      final current = (await tx.get(_meta(wallet.id))).data();
      if (current == null || '${current['version'] ?? ''}' != expectVersion) return false;
      tx.update(_meta(wallet.id), {
        'version': version,
        'chunks': chunks.length,
        'size': encrypted.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!committed) {
      for (var i = 0; i < chunks.length; i++) {
        await _chunk(wallet.id, version, i).delete();
      }
      throw const CloudChanged();
    }
    final limit = int.parse(version);
    final all = await _db.collection('wallets/${wallet.id}/chunks').get();
    for (final d in all.docs) {
      if ((int.tryParse(d.id.split('_').first) ?? 0) < limit) await d.reference.delete();
    }
    return version;
  }

  Future<String> _download(String walletId, Map<String, dynamic> meta) async {
    final content = StringBuffer();
    final count = (meta['chunks'] as num?)?.toInt() ?? 0;
    for (var i = 0; i < count; i++) {
      final part = (await _chunk(walletId, '${meta['version']}', i).get()).data()?['data'];
      if (part is! String) throw const BackupException(BackupError.corrupted);
      content.write(part);
      if (content.length > maxSnapshotChars) throw const BackupException(BackupError.tooLarge);
    }
    return content.toString();
  }

  /// `{"name","photo"}` of this phone's profile; photo = 96 px wide PNG,
  /// base64 (kept small: it is stored once per wallet).
  Future<String> _profileJson() async {
    final profile = await _ref.read(profileProvider.future);
    String? photo;
    try {
      final file = await _ref.read(avatarFileProvider.future);
      if (file != null) {
        final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 96);
        final frame = await codec.getNextFrame();
        final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        if (png != null) photo = base64.encode(png.buffer.asUint8List());
      }
    } on Object {
      // Unreadable photo: the name alone is published.
    }
    return jsonEncode({'name': profile.name.trim(), 'photo': photo});
  }

  Future<void> _publishProfile(Wallet wallet, String uid) async {
    final json = await _profileJson();
    final hash = sha256.convert(utf8.encode(json)).toString();
    final settings = _ref.read(settingsRepositoryProvider);
    if (await settings.read(_profileKey(wallet.id)) == hash) return;
    await _member(wallet.id, uid).update({
      'profile': await encryptWithSecret(json, wallet.secret),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await settings.write(_profileKey(wallet.id), hash);
  }

  /// Members of [wallet] with the name and photo they published.
  Future<Map<String, WalletMember>> members(Wallet wallet) async {
    await _signedIn();
    final docs = await _db.collection('wallets/${wallet.id}/members').get();
    final members = <String, WalletMember>{};
    for (final d in docs.docs) {
      var name = '';
      Uint8List? photo;
      try {
        final profile = jsonDecode(await decryptWithSecret('${d.data()['profile']}', wallet.secret));
        if (profile is Map<String, dynamic>) {
          final n = profile['name'];
          if (n is String) name = n.length > 60 ? n.substring(0, 60) : n;
          final p = profile['photo'];
          if (p is String && p.length <= 200000) photo = base64.decode(p);
        }
      } on Object {
        // Unreadable profile: shown as an anonymous member.
      }
      members[d.id] = WalletMember(uid: d.id, name: name, photo: photo);
    }
    return members;
  }

  /// Syncs every wallet; errors are ignored (offline, signed out…) and the
  /// next launch/resume/open tries again.
  Future<void> syncAllQuietly() async {
    if (!cloudAvailable) return;
    final wallets = await _ref.read(walletRepositoryProvider).watchAll().first;
    for (final w in wallets) {
      try {
        await sync(w);
      } on Object {
        // Next time.
      }
    }
  }
}
