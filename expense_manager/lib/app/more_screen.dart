import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/breakpoints.dart';
import 'routes.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _entries = [
    (Icons.autorenew_rounded, 'Subscriptions', Routes.subscriptions),
    (Icons.event_repeat_rounded, 'Recurring expenses', Routes.recurring),
    (Icons.flag_rounded, 'Savings goals', Routes.savings),
    (Icons.category_rounded, 'Categories & payment methods', Routes.categories),
    (Icons.person_rounded, 'Profile', Routes.profile),
    (Icons.backup_rounded, 'Backup & restore', Routes.backup),
    (Icons.settings_rounded, 'Settings', Routes.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            children: [
              for (final (icon, label, route) in _entries)
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
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
