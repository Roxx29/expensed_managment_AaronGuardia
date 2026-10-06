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
  _Destination('More', Icons.menu_rounded, Icons.menu_open_rounded),
];

/// Bottom navigation on phones, navigation rail on tablets/landscape.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell, required this.location});

  final StatefulNavigationShell navigationShell;

  /// Current path: the + button shows only on the tabs' main screens.
  final String location;

  static const _tabRoots = {Routes.dashboard, Routes.transactions, Routes.budgets, Routes.more};

  void _onSelect(int index) => navigationShell.goBranch(
        index,
        // Tapping the active tab returns to its root.
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Hidden while typing and on inner screens (they have their own buttons).
    final showAdd = _tabRoots.contains(location) && MediaQuery.viewInsetsOf(context).bottom == 0;

    if (width < Breakpoints.medium) {
      // Figma layout: two tabs, the yellow + button, two tabs. The middle
      // slot is an empty, disabled destination the button sits over, so the
      // tab count must stay even to keep it centered.
      const gap = 2;
      final current = navigationShell.currentIndex;
      return Scaffold(
        body: _TabTransition(index: current, child: navigationShell),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: showAdd
            ? const Padding(padding: EdgeInsets.only(top: 24), child: _AddButton())
            : null,
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
              leading: showAdd
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: _AddButton())
                  : null,
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
            Expanded(child: _TabTransition(index: navigationShell.currentIndex, child: navigationShell)),
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
        shape: const CircleBorder(),
        onPressed: () => context.push(Routes.newTransaction),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
    );
  }
}

/// Switching tabs: the new tab fades in while sliding a few pixels from the
/// side of the tab it comes from (220 ms). The + button and the bar don't
/// move. One short controller, idle between switches.
class _TabTransition extends StatefulWidget {
  const _TabTransition({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  var _fromX = 0.0;

  @override
  void didUpdateWidget(_TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _fromX = widget.index > oldWidget.index ? 0.03 : -0.03;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: t.drive(Tween(begin: Offset(_fromX, 0), end: Offset.zero)),
        child: widget.child,
      ),
    );
  }
}
