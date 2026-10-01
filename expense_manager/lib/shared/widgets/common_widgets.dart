import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../../domain/finance/budget_calculator.dart';

/// Built-in categories are stored with English names; show them translated.
/// Names the user typed are shown as-is.
extension CategoryLabel on FinanceCategory {
  String label(BuildContext context) => isDefault ? context.trName(name) : name;
}

extension PaymentMethodLabel on PaymentMethod {
  String label(BuildContext context) => isDefault ? context.trName(name) : name;
}

/// Persisted icon keys → Material icons (keeps Flutter out of the domain).
/// Add new keys at the end; never rename existing ones.
const categoryIcons = <String, IconData>{
  'food': Icons.restaurant_rounded,
  'gas': Icons.local_gas_station_rounded,
  'transportation': Icons.directions_bus_rounded,
  'clothing': Icons.checkroom_rounded,
  'entertainment': Icons.movie_rounded,
  'health': Icons.favorite_rounded,
  'education': Icons.school_rounded,
  'home': Icons.home_rounded,
  'technology': Icons.devices_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'subscriptions': Icons.autorenew_rounded,
  'salary': Icons.payments_rounded,
  'other': Icons.category_rounded,
  'pets': Icons.pets_rounded,
  'travel': Icons.flight_rounded,
  'gifts': Icons.card_giftcard_rounded,
  'sports': Icons.fitness_center_rounded,
  'kids': Icons.child_friendly_rounded,
  'bills': Icons.receipt_rounded,
  'car': Icons.directions_car_rounded,
  'coffee': Icons.local_cafe_rounded,
  'business': Icons.work_rounded,
  'investments': Icons.trending_up_rounded,
  'savings': Icons.savings_rounded,
};

IconData iconForKey(String key) => categoryIcons[key] ?? Icons.category_rounded;

/// Palette offered for custom categories (ARGB).
const categoryColors = <int>[
  0xFFEF6C00, 0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF5E35B1, 0xFF3949AB,
  0xFF1E88E5, 0xFF00897B, 0xFF2E7D32, 0xFF7CB342, 0xFFF9A825, 0xFF6D4C41,
  0xFF546E7A, 0xFF757575,
];

/// Titled card used to group dashboard/settings content.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

/// Animated budget bar colored by [BudgetStatus].
class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({super.key, required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final finance = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (progress.status) {
      BudgetStatus.onTrack => scheme.primary,
      BudgetStatus.nearLimit => finance.warning,
      BudgetStatus.overBudget => finance.expense,
    };
    final value = progress.ratio.isFinite ? progress.ratio.clamp(0.0, 1.0).toDouble() : 1.0;
    return Semantics(
      label: context.tr('Budget used'),
      value: '${(value * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 10,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

/// Placeholder for screens scheduled in a later phase.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(title))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.construction_rounded,
            message: context.tr('{title} is planned for {phase}.', {'title': context.tr(title), 'phase': context.tr(phase)}),
          ),
        ),
      ),
    );
  }
}
