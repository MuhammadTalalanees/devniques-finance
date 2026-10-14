import 'package:flutter/material.dart';

/// Devniques Finance — clean light professional theme.
/// White / light-grey surfaces, dark slate text, deep emerald accent.
class AppTheme {
  static const background = Color(0xFFF6F7F9);
  static const card = Colors.white;
  static const border = Color(0xFFE3E7EE);

  static const primary = Color(0xFF0E7A4F); // deep emerald
  static const primaryDark = Color(0xFF0A5C3C);

  static const ink = Color(0xFF1E293B); // dark slate text
  static const muted = Color(0xFF64748B); // slate grey secondary text

  static const income = Color(0xFF0E7A4F); // green
  static const expense = Color(0xFFDC2626); // restrained red
  static const investment = Color(0xFFB45309); // amber / bronze

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: primary,
        surface: background,
        surfaceContainerHighest: card,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
        shadowColor: const Color(0x1A1E293B),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor:
              primary.withValues(alpha: 0.12),
          selectedForegroundColor: primaryDark,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: muted,
      ),
      dividerTheme: const DividerThemeData(color: border),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: ink),
        bodyMedium: TextStyle(color: ink),
        bodySmall: TextStyle(color: muted),
        titleLarge: TextStyle(color: ink),
        titleMedium: TextStyle(color: ink),
        titleSmall: TextStyle(color: ink),
      ),
    );
  }
}
