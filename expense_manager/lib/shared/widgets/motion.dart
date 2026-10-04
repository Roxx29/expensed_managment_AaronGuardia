import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money/money.dart';

/// Shrinks a little while pressed, so taps feel physical.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.borderRadius = 16});

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap != null && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and slides its child in once; [index] staggers lists.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    // ponytail: stagger is baked into one tween (delay = leading flat part of the
    // curve), so no controllers or timers to dispose.
    final delay = (index * 0.08).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + (delay * 1000).round()),
      curve: Interval(delay, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
    );
  }
}

/// Counts from the previous value (0 on first build) up to [value].
class CountUpMoney extends StatelessWidget {
  const CountUpMoney({super.key, required this.value, this.style});

  final Money value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.minor.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(Money(v.round(), value.currency).format(), style: style),
    );
  }
}

/// Celebrates a saved item: a check pops in with a ring burst over the whole
/// app, then fades out and removes itself. Pass the root overlay captured
/// before navigating away (`Overlay.of(context, rootOverlay: true)`).
void showSuccessBurst(OverlayState overlay, {required String message, required IconData icon, required Color color}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessBurst(message: message, icon: icon, color: color, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
}

class _SuccessBurst extends StatelessWidget {
  const _SuccessBurst({required this.message, required this.icon, required this.color, required this.onDone});

  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One-shot tween (no repeat), so widget tests can pumpAndSettle.
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1300),
        onEnd: onDone,
        builder: (context, t, _) {
          final pop = Curves.elasticOut.transform((t / 0.5).clamp(0.0, 1.0));
          final ring = Curves.easeOutCubic.transform((t / 0.6).clamp(0.0, 1.0));
          final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: 0.4 + ring,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color.withValues(alpha: 1 - ring), width: 6),
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: pop,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 24)],
                            ),
                            child: Icon(icon, size: 52, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, 12 * (1 - pop.clamp(0.0, 1.0))),
                    child: Material(
                      color: theme.colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          message,
                          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onInverseSurface),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
