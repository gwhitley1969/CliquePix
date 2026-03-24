import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/theme/app_theme.dart';

class DurationPicker extends StatelessWidget {
  final int selectedHours;
  final ValueChanged<int> onChanged;

  const DurationPicker({
    super.key,
    required this.selectedHours,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: AppConstants.durationPresets.map((hours) {
        final isSelected = hours == selectedHours;
        final label = AppConstants.durationLabels[hours] ?? '$hours h';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onChanged(hours),
              child: Container(
                height: AppTheme.minTapTarget,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.deepBlue : AppColors.whiteSurface,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(
                    color: isSelected ? AppColors.deepBlue : AppColors.secondaryText.withOpacity(0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: isSelected ? AppColors.whiteSurface : AppColors.primaryText,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
