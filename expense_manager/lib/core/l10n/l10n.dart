import 'package:flutter/widgets.dart';

import 'strings_es.dart';

/// Languages the app can show. English is the source language.
const supportedLocales = [Locale('en'), Locale('es')];

/// UI translation. The English text is the key (gettext style), so a missing
/// translation falls back to English instead of crashing. A test checks that
/// every `tr('...')` literal in lib/ has a Spanish entry.
// ponytail: English-as-key map; move to ARB + gen_l10n when a third language
// or outside translators join.
extension L10n on BuildContext {
  /// Language code of the current UI, e.g. `es`. Pass it to `DateFormat`.
  /// Reading it also rebuilds the widget when the language changes.
  String get lang => Localizations.localeOf(this).languageCode;

  /// Translates [en]; `{name}` placeholders are filled from [args].
  String tr(String en, [Map<String, Object?> args = const {}]) {
    var text = lang == 'es' ? (esStrings[en] ?? en) : en;
    for (final e in args.entries) {
      text = text.replaceAll('{${e.key}}', '${e.value}');
    }
    return text;
  }

  /// Translates a built-in category/payment-method name (kept apart from
  /// [tr] because e.g. the "Home" tab and the "Home" category differ).
  String trName(String en) => lang == 'es' ? (esDefaultNames[en] ?? en) : en;
}
