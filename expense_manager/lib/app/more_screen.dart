import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/breakpoints.dart';
import '../core/theme/app_theme.dart';
import '../features/premium/application/premium_providers.dart';
import '../features/premium/presentation/paywall_screen.dart';
import 'routes.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _entries = [
    (Icons.account_balance_wallet_rounded, 'Wallets', Routes.wallets),
    (Icons.insights_rounded, 'Statistics', Routes.statistics),
    (Icons.auto_awesome_rounded, 'Assistant', Routes.assistant),
    (Icons.autorenew_rounded, 'Subscriptions', Routes.subscriptions),
    (Icons.event_repeat_rounded, 'Recurring expenses', Routes.recurring),
    (Icons.flag_rounded, 'Savings goals', Routes.savings),
    (Icons.category_rounded, 'Categories & payment methods', Routes.categories),
    (Icons.person_rounded, 'Profile', Routes.profile),
    (Icons.upload_file_rounded, 'Import bank statement', Routes.importStatement),
    (Icons.backup_rounded, 'Backup & restore', Routes.backup),
    (Icons.lock_rounded, 'Security', Routes.security),
    (Icons.notifications_rounded, 'Notifications', Routes.notifications),
    (Icons.settings_rounded, 'Settings', Routes.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('More'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            children: [
              Consumer(
                builder: (context, ref, _) => ListTile(
                  leading: const Icon(Icons.workspace_premium_rounded, color: Brand.yellow),
                  title: Text(context.tr('Monchi Premium')),
                  subtitle: Text(premiumSummary(context, ref.watch(premiumStatusProvider))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.premium),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_circle_rounded),
                title: Text(context.tr('Your account')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.welcome),
              ),
              for (final (icon, label, route) in _entries)
                ListTile(
                  leading: Icon(icon),
                  title: Text(context.tr(label)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go(route),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
