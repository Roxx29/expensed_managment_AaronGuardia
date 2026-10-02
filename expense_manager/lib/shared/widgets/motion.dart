import 'package:flutter/material.dart';

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
