import 'package:flutter/material.dart';

/// Spacing scale on a 4pt grid. Use these instead of ad-hoc numbers so the
/// whole app shares one vertical/horizontal rhythm.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii used by surfaces, chips and progress bars.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Semantic financial accent colors, tuned for light and dark surfaces.
abstract final class AppColors {
  static const Color brand = Color(0xFF0F766E);
  static const Color income = Color(0xFF15803D);
  static const Color incomeDark = Color(0xFF4ADE80);
  static const Color expense = Color(0xFFB91C1C);
  static const Color expenseDark = Color(0xFFF87171);
  static const Color warning = Color(0xFFB45309);
  static const Color warningDark = Color(0xFFFBBF24);

  /// Hairline border for cards and dividers.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF273244)
      : const Color(0xFFE7ECF3);

  /// Card / elevated surface fill.
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF131A26)
      : Colors.white;

  /// Color for a signed money value (green when positive, red when negative).
  static Color amount(BuildContext context, {required bool positive}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (positive) return dark ? incomeDark : income;
    return dark ? expenseDark : expense;
  }

  /// Color reflecting credit-card utilization: calm under 50%, amber under 90%,
  /// red when nearly maxed.
  static Color utilization(BuildContext context, double percent) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (percent >= 90) return dark ? expenseDark : expense;
    if (percent >= 60) return dark ? warningDark : warning;
    return Theme.of(context).colorScheme.primary;
  }
}
