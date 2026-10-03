import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import '../features/backup/application/backup_providers.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/premium/application/premium_providers.dart';
import '../features/recurring/application/recurring_providers.dart';
import '../features/security/presentation/app_lock_gate.dart';
import '../features/settings/application/settings_providers.dart';
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
    // Keeps payment reminders and budget alerts in sync (no-op when off).
    ref.watch(notificationSyncProvider);
    // Listens for Google Play purchases from launch (none would be missed).
    ref.listen(premiumProvider, (_, _) {});
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
      builder: (context, child) => AppLockGate(child: child!),
    );
  }
}
