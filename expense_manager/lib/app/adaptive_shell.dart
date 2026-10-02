import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/breakpoints.dart';
import 'routes.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Destination('Transactions', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _Destination('Budgets', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
  _Destination('Statistics', Icons.insights_outlined, Icons.insights_rounded),
  _Destination('More', Icons.menu_rounded, Icons.menu_open_rounded),
];

/// Bottom navigation on phones, navigation rail on tablets/landscape.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onSelect(int index) => navigationShell.goBranch(
        index,
        // Tapping the active tab returns to its root.
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < Breakpoints.medium) {
      // Figma layout: two tabs, the yellow + button, then the rest. The
      // middle slot is an empty, disabled destination the button sits over.
      const gap = 2;
      final current = navigationShell.currentIndex;
      return Scaffold(
        body: navigationShell,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: const Padding(
          padding: EdgeInsets.only(top: 24),
          child: _AddButton(),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: current < gap ? current : current + 1,
          onDestinationSelected: (i) => _onSelect(i < gap ? i : i - 1),
          destinations: [
            for (final (i, d) in _destinations.indexed) ...[
              if (i == gap) const NavigationDestination(enabled: false, icon: SizedBox.shrink(), label: ''),
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: context.tr(d.label)),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: width >= Breakpoints.large,
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onSelect,
              labelType: width >= Breakpoints.large ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: _AddButton(),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(context.tr(d.label)),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}

/// Yellow "+" from the logo palette; pops in with a small bounce.
class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: FloatingActionButton(
        heroTag: null,
        tooltip: context.tr('Add'),
        elevation: 6,
        onPressed: () => context.push(Routes.newTransaction),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
    );
  }
}
