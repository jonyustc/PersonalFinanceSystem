import 'package:flutter/material.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  const seed = Color(0xFF0F766E);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: seed,
    secondary: const Color(0xFF2563EB),
    tertiary: const Color(0xFFF59E0B),
  );
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      foregroundColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF111827) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF111827) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: seed, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size.fromHeight(48),
      ),
    ),
  );
}
