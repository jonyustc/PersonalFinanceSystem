import 'package:flutter/material.dart';

import 'app_spacing.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  const seed = AppColors.brand;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: seed,
    secondary: const Color(0xFF2563EB),
    tertiary: const Color(0xFFF59E0B),
  );
  final isDark = brightness == Brightness.dark;

  final surfaceBorder = isDark
      ? const Color(0xFF273244)
      : const Color(0xFFE7ECF3);
  final scaffold = isDark ? const Color(0xFF0B1118) : const Color(0xFFF6F8FB);
  final cardColor = isDark ? const Color(0xFF131A26) : Colors.white;
  final onSurface = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scaffold,
      foregroundColor: onSurface,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: surfaceBorder),
      ),
    ),
    dividerTheme: DividerThemeData(color: surfaceBorder, thickness: 1, space: 1),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: surfaceBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: seed, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        minimumSize: const Size.fromHeight(48),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}
