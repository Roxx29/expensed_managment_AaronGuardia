import 'package:flutter/foundation.dart' show visibleForTesting;

/// Time for `updatedAt`. Sync keeps the row with the newer `updatedAt`, so a
/// phone whose clock runs behind would always lose. This clock never returns
/// a time at or before the newest change seen from another phone ([observe]);
/// one second later is enough because the database stores whole seconds.
// ponytail: the floor lives in memory; the sync at launch sets it again. Persist it if edits before the first sync must win too.
class SyncClock {
  static DateTime _seen = DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime now() {
    final wall = DateTime.now();
    final floor = _seen.add(const Duration(seconds: 1));
    return wall.isBefore(floor) ? floor : wall;
  }

  /// A change made elsewhere at [time]: later local edits sort after it.
  /// Times over a day ahead are ignored (a broken clock must not drag ours along).
  static void observe(DateTime time) {
    if (time.isAfter(_seen) && time.isBefore(DateTime.now().add(const Duration(days: 1)))) _seen = time;
  }

  @visibleForTesting
  static void reset() => _seen = DateTime.fromMillisecondsSinceEpoch(0);
}
