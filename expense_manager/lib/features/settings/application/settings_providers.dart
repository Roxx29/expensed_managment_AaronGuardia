import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency.dart';
import '../../../shared/providers/providers.dart';

abstract final class SettingKeys {
  static const themeMode = 'theme_mode';
  static const language = 'language';
}

/// Persisted theme preference; defaults to following the system.
final themeModeProvider = StreamProvider<ThemeMode>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.themeMode)
      .map((value) => ThemeMode.values.asNameMap()[value] ?? ThemeMode.system),
);

/// Chosen UI language (`en`/`es`), or null to follow the device.
final languageProvider = StreamProvider<Locale?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.language)
      .map((code) => code == 'en' || code == 'es' ? Locale(code!) : null),
);

final settingsControllerProvider = Provider<SettingsController>(SettingsController.new);

/// Write-side of settings. Widgets call these methods; they never touch
/// repositories directly.
class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;

  Future<void> setThemeMode(ThemeMode mode) =>
      _ref.read(settingsRepositoryProvider).write(SettingKeys.themeMode, mode.name);

  /// [locale] null = follow the device language.
  Future<void> setLanguage(Locale? locale) =>
      _ref.read(settingsRepositoryProvider).write(SettingKeys.language, locale?.languageCode ?? 'system');

  Future<void> setCurrency(Currency currency) async {
    final repo = _ref.read(profileRepositoryProvider);
    final profile = await repo.watch().first;
    await repo.save(profile.copyWith(currency: currency));
  }
}
