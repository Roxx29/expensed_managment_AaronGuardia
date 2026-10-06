/// Invite codes of shared wallets: `<inviteId>.<walletKey>` (base64url).
/// The id finds the wallet in the cloud; the key decrypts it and never
/// leaves the phones (see claude/WALLETS.md).
library;

final _code = RegExp(r'([A-Za-z0-9_-]{22})\.([A-Za-z0-9_-]{43})');

String inviteCode(String inviteId, String walletKey) => '$inviteId.$walletKey';

/// Finds a code anywhere in [text], so the whole shared message can be
/// pasted. Null when there is none.
({String inviteId, String walletKey})? parseInviteCode(String text) {
  final m = _code.firstMatch(text);
  return m == null ? null : (inviteId: m[1]!, walletKey: m[2]!);
}
