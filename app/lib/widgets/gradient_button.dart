import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_gradients.dart';
import '../core/theme/app_text_styles.dart';
import '../core/theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: AppTheme.minTapTarget,
      decoration: BoxDecoration(
        gradient: onPressed != null ? AppGradients.primary : null,
        color: onPressed == null ? AppColors.secondaryText.withOpacity(0.3) : null,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: AppColors.whiteSurface,
                      strokeWidth: 2,
                    ),
                  )
                : Text(text, style: AppTextStyles.button),
          ),
        ),
      ),
    );
  }
}
