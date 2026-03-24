import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/gradient_app_bar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/domain/auth_state.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Avatar
            if (authState is AuthAuthenticated) ...[
              AvatarWidget(
                name: authState.user.displayName,
                imageUrl: authState.user.avatarUrl,
                size: 96,
              ),
              const SizedBox(height: 16),
              Text(authState.user.displayName, style: AppTextStyles.heading2),
              const SizedBox(height: 4),
              Text(authState.user.emailOrPhone, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 32),
            // Settings cards
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About Clique Pix'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Clique Pix',
                        applicationVersion: '1.0.0',
                        applicationLegalese: 'Private photo sharing for your inner circle.',
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                    onTap: () {
                      // TODO: Open privacy policy URL
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                    onTap: () {
                      // TODO: Open terms URL
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Sign out
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text('Sign Out', style: AppTextStyles.body.copyWith(color: AppColors.error)),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    ref.read(authStateProvider.notifier).signOut();
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('Version 1.0.0', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
