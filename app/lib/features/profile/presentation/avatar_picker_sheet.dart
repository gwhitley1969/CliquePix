import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

/// Result of the picker bottom sheet. `null` = user cancelled.
enum AvatarPickerResult { takePhoto, chooseFromLibrary, remove }

/// Dark-themed bottom sheet offering Take Photo / Choose from Library /
/// Remove / Cancel. `canRemove` controls whether the destructive remove
/// option is shown (omitted for first-time uploaders who have no avatar
/// to remove).
class AvatarPickerSheet {
  static Future<AvatarPickerResult?> show(
    BuildContext context, {
    required bool canRemove,
  }) async {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<AvatarPickerResult>(
      context: context,
      backgroundColor: const Color(0xFF1A2035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTile(
                icon: Icons.camera_alt_rounded,
                label: 'Take Photo',
                onTap: () => Navigator.pop(ctx, AvatarPickerResult.takePhoto),
              ),
              _SheetTile(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Library',
                onTap: () => Navigator.pop(ctx, AvatarPickerResult.chooseFromLibrary),
              ),
              if (canRemove)
                _SheetTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove Photo',
                  destructive: true,
                  onTap: () => Navigator.pop(ctx, AvatarPickerResult.remove),
                ),
              const SizedBox(height: 4),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              _SheetTile(
                icon: Icons.close_rounded,
                label: 'Cancel',
                muted: true,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool muted;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (destructive) {
      color = const Color(0xFFEF4444);
    } else if (muted) {
      color = Colors.white.withValues(alpha: 0.55);
    } else {
      color = Colors.white;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: destructive || !muted ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience re-export so screens can use the same color constant
/// without importing the theme.
const _kSheetAccent = AppColors.electricAqua;
// ignore: unused_element
const _unused = _kSheetAccent;
