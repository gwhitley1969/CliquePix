import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Outcome of the first-sign-in welcome prompt.
enum AvatarWelcomeChoice { yes, later, no }

/// Branded modal shown once to a brand-new user whose backend flag
/// `should_prompt_for_avatar` is true. Three choices:
///
///   * **Yes**    → pop with `AvatarWelcomeChoice.yes` — caller launches
///                  the AvatarPickerSheet → editor flow
///   * **Later**  → pop with `AvatarWelcomeChoice.later` — caller
///                  records a 7-day snooze server-side
///   * **No**     → pop with `AvatarWelcomeChoice.no` — caller records a
///                  permanent dismiss
///
/// Back-button / tap-outside both resolve to `later` (safer default than
/// a permanent dismiss from an accidental dismiss).
class AvatarWelcomePrompt {
  static Future<AvatarWelcomeChoice> show(BuildContext context) async {
    final choice = await showDialog<AvatarWelcomeChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient camera-icon hero
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.electricAqua,
                      AppColors.deepBlue,
                      AppColors.violetAccent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Make yourself known',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Add a photo so friends recognize who\'s sharing. You can always change it later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Primary: Yes
              _PrimaryGradientButton(
                label: 'Add a Photo',
                onPressed: () => Navigator.of(ctx).pop(AvatarWelcomeChoice.yes),
              ),
              const SizedBox(height: 12),
              // Secondary: Maybe Later
              _SecondaryOutlineButton(
                label: 'Maybe Later',
                onPressed: () => Navigator.of(ctx).pop(AvatarWelcomeChoice.later),
              ),
              const SizedBox(height: 4),
              // Tertiary: No Thanks
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(AvatarWelcomeChoice.no),
                child: Text(
                  'No Thanks',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Any dismiss path that isn't an explicit button tap = snooze (safer
    // default than permanent dismiss from a fat-fingered barrier tap).
    return choice ?? AvatarWelcomeChoice.later;
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryGradientButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              AppColors.electricAqua,
              AppColors.deepBlue,
              AppColors.violetAccent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _SecondaryOutlineButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
