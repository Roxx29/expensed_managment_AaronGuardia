import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../premium/application/premium_providers.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final language = ref.watch(languageProvider).value?.languageCode ?? 'system';
    final currency = ref.watch(currencyProvider);
    final controller = ref.read(settingsControllerProvider);
    final premium = ref.watch(premiumProvider);
    final ambient = premium && (ref.watch(ambientBackgroundProvider).value ?? true);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Settings'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: context.tr('Appearance'),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(value: ThemeMode.light, label: Text(context.tr('Light')), icon: const Icon(Icons.light_mode_rounded)),
                          ButtonSegment(value: ThemeMode.dark, label: Text(context.tr('Dark')), icon: const Icon(Icons.dark_mode_rounded)),
                          ButtonSegment(value: ThemeMode.system, label: Text(context.tr('System')), icon: const Icon(Icons.brightness_auto_rounded)),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (selection) => controller.setThemeMode(selection.first),
                      ),
                    ),
                    // Premium only: free users get the plain background and the paywall on tap.
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(premium ? Icons.auto_awesome_rounded : Icons.lock_rounded),
                      title: Text(context.tr('Animated background')),
                      subtitle: Text(context.tr('Soft brand lights moving behind the app. Premium.')),
                      value: ambient,
                      onChanged: (on) {
                        if (requirePremium(context, ref)) controller.setAmbientBackground(on);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: context.tr('Language'),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      // Language names stay in their own language so they are always recognizable.
                      const ButtonSegment(value: 'en', label: Text('English')),
                      const ButtonSegment(value: 'es', label: Text('Español')),
                      ButtonSegment(value: 'system', label: Text(context.tr('System')), icon: const Icon(Icons.language_rounded)),
                    ],
                    selected: {language},
                    onSelectionChanged: (s) => controller.setLanguage(s.first == 'system' ? null : Locale(s.first)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: context.tr('Currency'),
                child: DropdownButtonFormField<Currency>(
                  key: ValueKey(currency),
                  initialValue: currency,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('Main currency')),
                  items: [
                    for (final c in Currency.values)
                      DropdownMenuItem(value: c, child: Text('${c.code} — ${context.tr(c.displayName)}')),
                  ],
                  onChanged: (c) {
                    if (c != null) controller.setCurrency(c);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.tr('Amounts are not converted between currencies.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
