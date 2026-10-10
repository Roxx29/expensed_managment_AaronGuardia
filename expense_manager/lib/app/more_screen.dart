import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/breakpoints.dart';
import '../core/theme/app_theme.dart';
import '../features/premium/application/premium_providers.dart';
import '../features/premium/presentation/paywall_screen.dart';
import '../shared/providers/providers.dart';
import 'routes.dart';

/// More: a profile header, then the options grouped by what people look
/// for (money, planning, tools, data & security, app).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  // Labels are tr() keys (see l10n_test dynamicKeys).
  static const _sections = [
    ('Your money', [
      (Icons.account_balance_wallet_rounded, 'Wallets', Routes.wallets),
      (Icons.insights_rounded, 'Statistics', Routes.statistics),
      (Icons.flag_rounded, 'Savings goals', Routes.savings),
    ]),
    ('Planning', [
      (Icons.autorenew_rounded, 'Subscriptions', Routes.subscriptions),
      (Icons.event_repeat_rounded, 'Recurring expenses', Routes.recurring),
      (Icons.category_rounded, 'Categories & payment methods', Routes.categories),
    ]),
    ('Tools', [
      (Icons.auto_awesome_rounded, 'Assistant', Routes.assistant),
      (Icons.upload_file_rounded, 'Import bank statement', Routes.importStatement),
    ]),
    ('Data & security', [
      (Icons.backup_rounded, 'Backup & restore', Routes.backup),
      (Icons.lock_rounded, 'Security', Routes.security),
      (Icons.notifications_rounded, 'Notifications', Routes.notifications),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        );
    Widget group(List<Widget> tiles) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        );
    Widget tile(IconData icon, String label, VoidCallback onTap, {Widget? subtitle, Color? color}) => ListTile(
          leading: Icon(icon, color: color),
          title: Text(label),
          subtitle: subtitle,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('More'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _ProfileHeader(),
              for (final (title, entries) in _sections) ...[
                header(context.tr(title)),
                group([
                  for (final (icon, label, route) in entries) tile(icon, context.tr(label), () => context.go(route)),
                ]),
              ],
              header(context.tr('App')),
              group([
                Consumer(
                  builder: (context, ref, _) => tile(
                    Icons.workspace_premium_rounded,
                    context.tr('Monchi Premium'),
                    () => context.push(Routes.premium),
                    subtitle: Text(premiumSummary(context, ref.watch(premiumStatusProvider))),
                    color: Brand.yellow,
                  ),
                ),
                tile(Icons.account_circle_rounded, context.tr('Your account'), () => context.push(Routes.welcome)),
                tile(Icons.support_agent_rounded, context.tr('Report a problem'), () => context.go(Routes.report)),
                tile(Icons.settings_rounded, context.tr('Settings'), () => context.go(Routes.settings)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name and plan; opens the profile.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(profileProvider).value?.name.trim() ?? '';
    final premium = ref.watch(premiumProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: theme.colorScheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.profile),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  name.isEmpty ? 'M' : name.characters.first.toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? context.tr('Your profile') : name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (premium) ...[
                          const Icon(Icons.workspace_premium_rounded, size: 16, color: Brand.yellow),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            premium ? context.tr('Monchi Premium') : context.tr('Free plan'),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
