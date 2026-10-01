import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/breakpoints.dart';
import 'routes.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _entries = [
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
