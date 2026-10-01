import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/breakpoints.dart';

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
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onSelect,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: context.tr(d.label)),
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
