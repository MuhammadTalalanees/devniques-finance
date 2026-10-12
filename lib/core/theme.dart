import 'package:flutter/material.dart';

/// Devniques brand theme — dark navy + blue accent.
class AppTheme {
  static const navy = Color(0xFF060B18);
  static const navyCard = Color(0xFF0B1327);
  static const blue = Color(0xFF2F7FF7);
  static const cyan = Color(0xFF00F0FF);
  static const income = Color(0xFF34D399);
  static const expense = Color(0xFFF87171);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: navy,
        surfaceContainerHighest: navyCard,
      ),
      scaffoldBackgroundColor: navy,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: navyCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: navyCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}
