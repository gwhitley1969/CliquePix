import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // Headings
  static const heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryText,
    height: 1.3,
  );

  static const heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryText,
    height: 1.3,
  );

  static const heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryText,
    height: 1.3,
  );

  // Body
  static const bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.primaryText,
    height: 1.5,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.primaryText,
    height: 1.5,
  );

  // Captions
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.secondaryText,
    height: 1.4,
  );

  // Button text
  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteSurface,
    height: 1.2,
  );
}
