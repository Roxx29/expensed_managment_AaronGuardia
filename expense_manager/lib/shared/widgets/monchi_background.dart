import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Tuning knobs for the ambient background. Change a value and hot-restart.
abstract final class MonchiBackgroundStyle {
  /// One full Premium loop. Longer = slower.
  static const loop = Duration(seconds: 20);

  /// How soft the Premium lights are (0 = hard edge, 1 = very diffuse).
  static const softness = 0.45;

  /// Strength of the Premium lights over the light / dark picture.
  static const lightOpacity = 0.30;
  static const darkOpacity = 0.34;

  /// How far the lights travel, as a fraction of the screen.
  static const drift = 0.09;

  static const lightAsset = 'assets/backgrounds/monchi_light.jpg';
  static const darkAsset = 'assets/backgrounds/monchi_dark.jpg';
}

/// Background behind every screen (app.dart builder). The scaffolds are
/// transparent (app_theme.dart), so the background shows through.
/// Free: the still brand picture. Premium: the same picture with soft lights
/// drifting slowly over it.
class MonchiBackground extends StatelessWidget {
  const MonchiBackground({
    super.key,
    required this.isPremium,
    this.animationDuration = MonchiBackgroundStyle.loop,
    this.child,
  });

  final bool isPremium;
  final Duration animationDuration;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // The system "remove animations" setting keeps Premium still too.
    final animate = isPremium && !MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        // Repaints of the lights stay inside this layer; the screens on top
        // are never repainted by the background.
        RepaintBoundary(
          child: animate
              ? AnimatedMonchiBackground(duration: animationDuration)
              : const StaticMonchiBackground(),
        ),
        if (child case final c?) c,
      ],
    );
  }
}

/// Free plan: the picture from ELEMENTOS/, no ticker, painted once.
class StaticMonchiBackground extends StatelessWidget {
  const StaticMonchiBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      // Shown for the first frame, until the picture is decoded.
      color: dark ? Brand.ink : Brand.cream,
      child: Image.asset(
        dark ? MonchiBackgroundStyle.darkAsset : MonchiBackgroundStyle.lightAsset,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Premium: the static picture breathing very slowly, plus four blurred
/// brand lights orbiting its corners. One controller; Flutter stops it while
/// the app is in the background, and it is disposed with the widget.
class AnimatedMonchiBackground extends StatefulWidget {
  const AnimatedMonchiBackground({super.key, this.duration = MonchiBackgroundStyle.loop});

  final Duration duration;

  @override
  State<AnimatedMonchiBackground> createState() => _AnimatedMonchiBackgroundState();
}

class _AnimatedMonchiBackgroundState extends State<AnimatedMonchiBackground>
    with SingleTickerProviderStateMixin {
  // ponytail: keeps ticking behind the opaque PIN cover / full-screen dialogs;
  // pause via TickerMode from AppLockGate if battery traces ever show it.
  late final _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void didUpdateWidget(AnimatedMonchiBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller
        ..duration = widget.duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The picture is rasterized once (RepaintBoundary); each frame only
        // moves it, which is a cheap compositing step.
        AnimatedBuilder(
          animation: _controller,
          child: const RepaintBoundary(child: StaticMonchiBackground()),
          builder: (context, child) {
            final a = _controller.value * 2 * math.pi;
            return Transform.scale(
              scale: 1.06,
              child: FractionalTranslation(
                translation: Offset(0.012 * math.sin(a), 0.015 * math.cos(a)),
                child: child,
              ),
            );
          },
        ),
        // Lights fade in once, so switching from free to Premium is smooth.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
          child: CustomPaint(painter: _LightsPainter(_controller, dark: dark)),
        ),
      ],
    );
  }
}

/// One light: brand color, resting spot (fraction of the screen), size
/// (fraction of the longest side), start phase and whole-number speeds, so
/// the end of the loop meets its start with no jump.
class _Light {
  const _Light(this.color, this.x, this.y, this.radius, this.phase, this.fx, this.fy);

  final Color color;
  final double x, y, radius, phase;
  final int fx, fy;
}

// Same spots as the picture: mint top-left, yellow top-right, coral left,
// mint bottom-right. The center stays clean for balances and charts.
const _lights = [
  _Light(Brand.mint, 0.10, 0.12, 0.34, 0.0, 1, 1),
  _Light(Brand.yellow, 0.96, 0.16, 0.26, 2.1, 1, 2),
  _Light(Brand.coral, 0.02, 0.66, 0.28, 4.2, 2, 1),
  _Light(Brand.mint, 0.90, 0.94, 0.34, 1.3, 1, 1),
];

class _LightsPainter extends CustomPainter {
  _LightsPainter(this.progress, {required this.dark}) : super(repaint: progress);

  final Animation<double> progress;
  final bool dark;

  // Radial gradients are already blurred light, so no ImageFilter.blur (a
  // full-screen blur every frame is the expensive part on phones). Shaders
  // are built once at radius 1 and scaled, nothing is allocated per frame.
  late final List<Paint> _paints = [
    for (final l in _lights)
      Paint()
        ..shader = RadialGradient(
          colors: [
            l.color.withValues(alpha: _opacity),
            l.color.withValues(alpha: _opacity * 0.4),
            l.color.withValues(alpha: 0),
          ],
          stops: const [0, MonchiBackgroundStyle.softness, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
  ];

  double get _opacity => dark ? MonchiBackgroundStyle.darkOpacity : MonchiBackgroundStyle.lightOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final a = progress.value * 2 * math.pi;
    const d = MonchiBackgroundStyle.drift;
    for (final (i, l) in _lights.indexed) {
      final center = Offset(
        (l.x + d * math.sin(a * l.fx + l.phase)) * size.width,
        (l.y + d * 0.7 * math.cos(a * l.fy + l.phase)) * size.height,
      );
      final r = l.radius * size.longestSide * (1 + 0.06 * math.sin(a + l.phase));
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..scale(r)
        ..drawCircle(Offset.zero, 1, _paints[i])
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_LightsPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.progress != progress;
}
