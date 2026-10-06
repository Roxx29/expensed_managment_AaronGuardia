import 'package:flutter/material.dart';

import '../../shared/widgets/motion.dart';

/// Monchi brand colors taken from the logo and the Figma design.
abstract final class Brand {
  /// Logo yellow: main call to action (center + button, highlights).
  static const yellow = Color(0xFFFFC800);

  /// "Azul tinta": balance card, splash, text on yellow.
  static const ink = Color(0xFF131B2E);
  static const inkLight = Color(0xFF283044);
  /// Figma "mint": Material 3 seed, every color role derives from it.
  static const mint = Color(0xFF14B8A6);
  static const coral = Color(0xFFFD7958);

  /// Light background base (the dark one is [ink]).
  static const cream = Color(0xFFFAFAF7);
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final base = ColorScheme.fromSeed(seedColor: Brand.mint, brightness: brightness);
    // Light surfaces copied from the Figma design (lavender-tinted).
    final scheme = light
        ? base.copyWith(
            primary: const Color(0xFF006B5F),
            surface: const Color(0xFFFAF8FF),
            onSurface: Brand.ink,
            onSurfaceVariant: const Color(0xFF3C4947),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF2F3FF),
            surfaceContainer: const Color(0xFFEAEDFF),
            surfaceContainerHigh: const Color(0xFFDAE2FD),
            surfaceContainerHighest: const Color(0xFFDAE2FD),
          )
        : base.copyWith(surface: const Color(0xFF0D1220));
    final radius = BorderRadius.circular(20);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Transparent: MonchiBackground (app.dart) shows behind every screen.
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [
        brightness == Brightness.light ? FinanceColors.light : FinanceColors.dark,
      ],
      appBarTheme: AppBarTheme(
        // Always clear over the background, also while scrolling.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
              fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: light ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        color: light ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Brand.yellow,
        foregroundColor: Brand.ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light ? Colors.white : scheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: light ? Colors.white : scheme.surfaceContainerLow,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: light ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MonchiPageTransitionsBuilder(),
          TargetPlatform.iOS: MonchiPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Semantic colors for money that Material roles do not cover.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.warning,
  });

  final Color income;
  final Color expense;
  final Color warning;

  static const light = FinanceColors(
    income: Color(0xFF006E2F),
    expense: Color(0xFFC62828),
    warning: Color(0xFFB26A00),
  );

  static const dark = FinanceColors(
    income: Color(0xFF7BD88F),
    expense: Color(0xFFFF8A80),
    warning: Color(0xFFFFC266),
  );

  static FinanceColors of(BuildContext context) =>
      Theme.of(context).extension<FinanceColors>() ?? light;

  @override
  FinanceColors copyWith({Color? income, Color? expense, Color? warning}) =>
      FinanceColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        warning: warning ?? this.warning,
      );

  @override
  FinanceColors lerp(covariant FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
