import 'dart:convert';

/// How often each feature was used on this phone, for the admin panel's
/// "Funciones más usadas" (admin_web/metrics.js). Keys are fixed names
/// (`featureForPath`, plus events like `expense_added`), never user data.
const maxFeatureKeys = 40;

/// [counts] with [key] + 1. A new key is dropped once there are
/// [maxFeatureKeys] (the Firestore rules allow no more).
Map<String, int> bumpFeature(Map<String, int> counts, String key) {
  if (!counts.containsKey(key) && counts.length >= maxFeatureKeys) return counts;
  return {...counts, key: (counts[key] ?? 0) + 1};
}

Map<String, int> parseFeatures(String? json) {
  try {
    final value = jsonDecode(json ?? '{}');
    if (value is! Map) return {};
    return {
      for (final e in value.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
  } on FormatException {
    return {};
  }
}

String encodeFeatures(Map<String, int> counts) => jsonEncode(counts);

/// Feature name of a route path, or null for paths not worth counting.
/// Ids are dropped (`/wallet/abc` → `wallet`).
String? featureForPath(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'home';
  return switch (parts.first) {
    'more' when parts.length > 1 => parts[1],
    'more' => 'more',
    'transactions' => 'history',
    'budgets' => 'budgets',
    'wallet' => 'wallet_open',
    'premium' => 'paywall',
    'transaction' || 'recurring' || 'welcome' => null, // forms: counted as events
    _ => null,
  };
}
