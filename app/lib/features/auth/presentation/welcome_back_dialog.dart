import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';

/// Layer 5: Graceful Re-Login UX (fallback when all background mechanisms fail)
/// Shows "Welcome back, [Name]!" instead of a cold login screen.
/// Uses loginHint to pre-fill email for one-tap re-auth.
class WelcomeBackDialog extends StatelessWidget {
  final String? displayName;
  final String? email;
  final void Function(String? loginHint) onSignIn;
  final VoidCallback onDifferentAccount;

  const WelcomeBackDialog({
    super.key,
    this.displayName,
    this.email,
    required this.onSignIn,
    required this.onDifferentAccount,
  });

  static Future<void> show(
    BuildContext context, {
    String? displayName,
    String? email,
    required void Function(String? loginHint) onSignIn,
    required VoidCallback onDifferentAccount,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WelcomeBackDialog(
        displayName: displayName,
        email: email,
        onSignIn: onSignIn,
        onDifferentAccount: onDifferentAccount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = displayName != null && displayName!.isNotEmpty
        ? 'Welcome back, $displayName!'
        : 'Welcome back!';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.waving_hand, size: 48, color: AppColors.electricAqua),
            const SizedBox(height: 16),
            Text(greeting, style: AppTextStyles.heading2, textAlign: TextAlign.center),
            if (email != null) ...[
              const SizedBox(height: 8),
              Text(email!, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 8),
            Text(
              'Your session has expired. Tap below to sign in again.',
              style: AppTextStyles.body.copyWith(color: AppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GradientButton(text: 'Sign In', onPressed: () => onSignIn(email)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onDifferentAccount,
              child: const Text('Use a different account'),
            ),
          ],
        ),
      ),
    );
  }
}
