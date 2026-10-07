/// Days the app was opened, for the admin panel's usage metrics
/// (admin_web/metrics.js reads the same `yyyymmdd` keys).
library;

/// `yyyymmdd` of a local date.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// [days] plus [today], without duplicates, sorted, only the newest [keep]
/// (keeps the Firestore row small; the rules allow at most 60).
List<int> addActiveDay(Iterable<int> days, DateTime today, {int keep = 60}) {
  final all = {...days, dayKey(today)}.toList()..sort();
  return all.length <= keep ? all : all.sublist(all.length - keep);
}

/// The setting is stored as `20261006,20261007`; bad parts are dropped.
List<int> parseActiveDays(String? text) =>
    [for (final p in (text ?? '').split(',')) ?int.tryParse(p.trim())];
