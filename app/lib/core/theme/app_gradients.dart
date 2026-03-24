import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppGradients {
  AppGradients._();

  static const primary = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientMiddle, AppColors.gradientEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const primaryVertical = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientMiddle, AppColors.gradientEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const subtle = LinearGradient(
    colors: [
      AppColors.softAquaBackground,
      AppColors.whiteSurface,
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
