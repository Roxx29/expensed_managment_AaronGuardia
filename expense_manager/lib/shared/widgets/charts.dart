import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/money/money.dart';
import '../../domain/entities/entities.dart';
import 'common_widgets.dart';

/// Single-series vertical bar chart. Tapping a bar selects it; the readout
/// above the plot acts as the tooltip on touch screens.
/// Built from plain widgets (no chart dependency) so it adapts to any width.
class MoneyBarChart extends StatelessWidget {
  const MoneyBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.selectedIndex,
    this.onSelected,
    this.height = 180,
    this.readoutLabels,
  }) : assert(values.length == labels.length),
       assert(readoutLabels == null || readoutLabels.length == values.length);

  final List<Money> values;

  /// Short axis labels ("J", "2026").
  final List<String> labels;

  /// Long labels for the readout and screen readers ("September").
  final List<String>? readoutLabels;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final maxMinor = values.fold<int>(0, (m, v) => v.minor > m ? v.minor : m);
    final selected = selectedIndex;
    final longLabels = readoutLabels ?? labels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Readout (tooltip): selected bar, else the maximum.
        Text(
          selected != null
              ? '${longLabels[selected]}: ${values[selected].format()}'
              : (maxMinor == 0
                  ? context.tr('No data')
                  : context.tr('Max {amount}', {'amount': values.firstWhere((v) => v.minor == maxMinor).format()})),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Semantics(
                    button: onSelected != null,
                    selected: i == selected,
                    label: '${longLabels[i]}: ${values[i].format()}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque, // whole column is the hit target
                      onTap: onSelected == null ? null : () => onSelected!(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2), // 2px gap between bars
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: maxMinor == 0 ? 0.0 : values[i].minor / maxMinor),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            builder: (context, factor, _) => FractionallySizedBox(
                              heightFactor: factor,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 28),
                                decoration: BoxDecoration(
                                  color: selected == null || i == selected
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.35),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant), // baseline
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: i == selected ? muted?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700) : muted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Category row with a share bar: icon, name, amount and optional note
/// (e.g. change vs last month). Text uses ink colors; the category color only
/// marks identity.
class CategoryAmountRow extends StatelessWidget {
  const CategoryAmountRow({
    super.key,
    required this.category,
    required this.amount,
    required this.share,
    this.note,
  });

  final FinanceCategory? category;
  final Money amount;
  final double share;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF757575);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(iconForKey(category?.iconKey ?? ''), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category?.label(context) ?? context.tr('Uncategorized'), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: share.isFinite ? share.clamp(0.0, 1.0).toDouble() : 0,
                  color: color,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount.format()),
              if (note != null) Text(note!, style: muted),
            ],
          ),
        ],
      ),
    );
  }
}
