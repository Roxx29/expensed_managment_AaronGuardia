import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency.dart';
import '../../../shared/providers/providers.dart';

abstract final class SettingKeys {
  static const themeMode = 'theme_mode';
}

/// Persisted theme preference; defaults to following the system.
final themeModeProvider = StreamProvider<ThemeMode>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.themeMode)
      .map((value) => ThemeMode.values.asNameMap()[value] ?? ThemeMode.system),
);

final settingsControllerProvider = Provider<SettingsController>(SettingsController.new);

/// Write-side of settings. Widgets call these methods; they never touch
/// repositories directly.
class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;

  Future<void> setThemeMode(ThemeMode mode) =>
      _ref.read(settingsRepositoryProvider).write(SettingKeys.themeMode, mode.name);

  Future<void> setCurrency(Currency currency) async {
    final repo = _ref.read(profileRepositoryProvider);
    final profile = await repo.watch().first;
    await repo.save(profile.copyWith(currency: currency));
  }
}
