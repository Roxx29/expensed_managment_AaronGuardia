import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import '../features/backup/application/backup_providers.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/premium/application/premium_providers.dart';
import '../features/profile/application/account_sync.dart';
import '../features/recurring/application/recurring_providers.dart';
import '../features/security/presentation/app_lock_gate.dart';
import '../features/settings/application/settings_providers.dart';
import '../features/premium/application/usage_ping.dart';
import '../features/wallets/application/wallet_providers.dart';
import '../shared/widgets/monchi_background.dart';
import 'router.dart';

class ExpenseManagerApp extends ConsumerWidget {
  const ExpenseManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    // Posts due recurring charges on launch and whenever the items change.
    ref.watch(autoPostRecurringProvider);
    // Automatic backup when the schedule says it is due.
    ref.watch(autoBackupProvider);
    // Premium sync when the app returns to the foreground (stage 3).
    ref.watch(cloudSyncOnResumeProvider);
    // Shared wallets: entries of the other members on launch and resume.
    ref.watch(walletAutoSyncProvider);
    // Opens and active days for the admin panel (signed-in users only).
    ref.watch(usagePingProvider);
    // Profile name <-> account name (every phone of the account, wallets).
    ref.watch(accountProfileSyncProvider);
    // Keeps payment reminders and budget alerts in sync (no-op when off).
    ref.watch(notificationSyncProvider);
    // Listens for Google Play purchases from launch (none would be missed).
    ref.listen(playPremiumProvider, (_, _) {});
    // Premium-only ambient background, switchable in Settings.
    final ambient = ref.watch(premiumProvider) && (ref.watch(ambientBackgroundProvider).value ?? true);
    return MaterialApp.router(
      title: 'Monchi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 250),
      // null = device language (Spanish devices get Spanish, others English).
      locale: ref.watch(languageProvider).value,
      supportedLocales: supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      // Above the router: no screen or deep link renders before unlock.
      // The brand background sits behind every screen (scaffolds are transparent).
      builder: (context, child) => MonchiBackground(
        ambient: ambient,
        child: AppLockGate(child: child!),
      ),
    );
  }
}
