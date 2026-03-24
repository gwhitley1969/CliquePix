import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';
import 'auth_providers.dart';
import '../domain/auth_state.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState is AuthLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.subtle),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.standardPadding * 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // App icon placeholder
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.camera_alt, color: AppColors.whiteSurface, size: 48),
                ),
                const SizedBox(height: 24),
                Text('Clique Pix', style: AppTextStyles.heading1.copyWith(fontSize: 32)),
                const SizedBox(height: 8),
                Text(
                  'Private photo sharing for your inner circle',
                  style: AppTextStyles.body.copyWith(color: AppColors.secondaryText),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                if (authState is AuthError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      authState.message,
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                GradientButton(
                  text: 'Sign In with Email',
                  isLoading: isLoading,
                  onPressed: isLoading ? null : () => ref.read(authStateProvider.notifier).signIn(),
                ),
                const SizedBox(height: 16),
                Text(
                  'We\'ll send you a magic link — no password needed',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
