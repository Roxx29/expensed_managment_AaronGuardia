import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/premium/gift_premium.dart';
import '../../backup/application/cloud_backup.dart';
import 'premium_providers.dart';

/// Build number set by CI (`--dart-define=APP_BUILD=<run>`), shown in the admin panel.
const _appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'local');

FirebaseFirestore get _db => FirebaseFirestore.instance;

/// Premium given from the admin panel (see firebase/firestore.rules):
/// `grants/<email>` and `redemptions/<uid>`; `users/<uid>.blocked` cancels both.
/// Also keeps the user's row in the panel up to date. Needs Google sign-in;
/// Firestore's offline cache answers when there is no connection.
/// The gift in force (forever wins, else the latest end) or null.
final giftPremiumProvider = FutureProvider<Gift?>((ref) async {
  final email = await ref.watch(cloudUserProvider.future);
  if (email == null) return null; // also every build without Firebase (tests)
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  // Re-runs when Google Play answers, so the panel's row is right.
  final playPremium = ref.watch(playPremiumProvider.select((s) => s != null));
  try {
    final me = _db.doc('users/${user.uid}');
    final snapshot = await me.get();
    // Not awaited: Firestore confirms writes only when online.
    unawaited(me.set({
      'email': email,
      'name': user.displayName,
      'lastSeen': FieldValue.serverTimestamp(),
      'appBuild': _appBuild,
      'playPremium': playPremium,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((Object _) {}));
    final grant = await _db.doc('grants/${email.toLowerCase()}').get();
    final redemption = await _db.doc('redemptions/${user.uid}').get();
    return bestGift(
      [
        if (grant.exists) Gift(until: _date(grant.data()?['until'])),
        if (redemption.exists)
          Gift.fromCode(
            redeemedAt: _date(redemption.data()?['redeemedAt']),
            days: (redemption.data()?['days'] as num?)?.toInt(),
            revoked: redemption.data()?['revoked'] == true,
          ),
      ],
      blocked: snapshot.data()?['blocked'] == true,
      now: DateTime.now(),
    );
  } on Object {
    return null; // offline with nothing cached, or Firebase misconfigured
  }
});

DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;

enum RedeemResult { redeemed, invalid, used, alreadyRedeemed }

final giftActionsProvider = Provider<GiftActions>(GiftActions.new);

class GiftActions {
  GiftActions(this._ref);

  final Ref _ref;

  /// Redeems a promo code for the signed-in user (firestore.rules check it again).
  Future<RedeemResult> redeem(String input) async {
    final code = normalizeCode(input);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isValidCode(code)) return RedeemResult.invalid;
    try {
      final result = await _db.runTransaction((tx) async {
        // One code per user; the admin panel can allow another.
        if ((await tx.get(_db.doc('redemptions/${user.uid}'))).exists) return RedeemResult.alreadyRedeemed;
        final codeDoc = await tx.get(_db.doc('codes/$code'));
        final data = codeDoc.data();
        final expires = _date(data?['expiresAt']);
        if (data == null || data['active'] != true || (expires != null && !DateTime.now().isBefore(expires))) {
          return RedeemResult.invalid;
        }
        if ((data['uses'] as num) >= (data['maxUses'] as num)) return RedeemResult.used;
        tx.update(codeDoc.reference, {'uses': FieldValue.increment(1)});
        tx.set(_db.doc('redemptions/${user.uid}'), {
          'code': code,
          'days': data['days'],
          'redeemedAt': FieldValue.serverTimestamp(),
        });
        return RedeemResult.redeemed;
      });
      if (result == RedeemResult.redeemed) _ref.invalidate(giftPremiumProvider);
      return result;
    } on FirebaseException catch (e) {
      // The rules refuse it (e.g. a blocked account): same answer as a bad code.
      if (e.code == 'permission-denied') return RedeemResult.invalid;
      rethrow;
    }
  }
}

/// Message from the admin panel shown on Home (`config/announcement`).
final announcementProvider = FutureProvider<Map<String, Object?>?>((ref) async {
  if (!cloudAvailable) return null;
  try {
    await ensureCloudReady();
    final data = (await _db.doc('config/announcement').get()).data();
    final es = '${data?['es'] ?? ''}'.trim();
    return data?['active'] == true && es.isNotEmpty ? data : null;
  } on Object {
    return null;
  }
});
