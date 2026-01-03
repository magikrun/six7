import 'package:flutter/material.dart';

abstract final class AppColors {
  // Violet to Coral gradient color palette (matches app logo)
  static const Color violet = Color(0xFF7C3AED);
  static const Color coral = Color(0xFFFF2859);
  static const Color lightViolet = Color(0xFFB388FF);
  static const Color darkViolet = Color(0xFF5B21B6);
  static const Color lightCoral = Color(0xFFFF6B8A);

  // Light theme colors
  static const Color lightBackground = Color(0xFFFAF5FF);
  static const Color lightSurface = Color(0xFFF3E8FF);
  static const Color lightDivider = Color(0xFFE9D5FF);

  // Dark theme colors
  static const Color darkBackground = Color(0xFF0F0A1A);
  static const Color darkSurface = Color(0xFF1E1529);
  static const Color darkDivider = Color(0xFF3B2D4D);
  static const Color darkText = Color(0xFFF3E8FF);

  // Gradient definitions
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [violet, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [darkViolet, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient verticalGradient = LinearGradient(
    colors: [violet, coral],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.violet,
          secondary: AppColors.coral,
          tertiary: AppColors.lightViolet,
          surface: AppColors.lightSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black87,
        ),
        scaffoldBackgroundColor: AppColors.lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.lightDivider,
          thickness: 0.5,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.violet,
          secondary: AppColors.coral,
          tertiary: AppColors.lightViolet,
          surface: AppColors.darkSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.darkText,
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkSurface,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.darkDivider,
          thickness: 0.5,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      );
}
