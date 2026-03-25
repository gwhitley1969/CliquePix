import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const double baseSpacing = 8.0;
  static const double cardRadius = 12.0;
  static const double standardPadding = 16.0;
  static const double minTapTarget = 48.0;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.deepBlue,
      primary: AppColors.deepBlue,
      secondary: AppColors.electricAqua,
      tertiary: AppColors.violetAccent,
      surface: AppColors.whiteSurface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.softAquaBackground,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      color: AppColors.whiteSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.whiteSurface,
      foregroundColor: AppColors.primaryText,
      elevation: 0,
      centerTitle: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.whiteSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: BorderSide(color: AppColors.secondaryText.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: BorderSide(color: AppColors.secondaryText.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        borderSide: const BorderSide(color: AppColors.deepBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.whiteSurface,
      selectedItemColor: AppColors.deepBlue,
      unselectedItemColor: AppColors.secondaryText,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
