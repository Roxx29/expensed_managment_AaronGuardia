/// Premium given from the admin panel: an e-mail grant or a redeemed code.
class Gift {
  const Gift({this.until, this.revoked = false});

  /// A code lasts [days] from its redemption; null days = forever. A
  /// redemption whose server time is still pending counts from now.
  factory Gift.fromCode({required DateTime? redeemedAt, required int? days, bool revoked = false}) => Gift(
        until: days == null ? null : (redeemedAt ?? DateTime.now()).add(Duration(days: days)),
        revoked: revoked,
      );

  /// Null = forever.
  final DateTime? until;
  final bool revoked;
}

/// Whether any gift is in force. A blocked user gets none.
bool giftPremiumActive(Iterable<Gift> gifts, {required bool blocked, required DateTime now}) =>
    !blocked && gifts.any((g) => !g.revoked && (g.until == null || now.isBefore(g.until!)));

/// Codes are typed by hand: case and spaces don't matter.
String normalizeCode(String code) => code.trim().toUpperCase();

/// Letters, digits and dashes, 4 to 32 characters (also a safe document id).
bool isValidCode(String code) => RegExp(r'^[A-Z0-9-]{4,32}$').hasMatch(code);
