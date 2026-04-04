import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../widgets/avatar_widget.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/domain/auth_state.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0E1525),
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.violetAccent, Color(0xFFEC4899)],
                ).createShader(bounds),
                child: const Text(
                  'Profile',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              centerTitle: true,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFEC4899).withValues(alpha: 0.1),
                      const Color(0xFF0E1525),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Profile card
                  if (authState is AuthAuthenticated) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.violetAccent.withValues(alpha: 0.1),
                            const Color(0xFFEC4899).withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: AppColors.violetAccent.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          AvatarWidget(
                            name: authState.user.displayName,
                            imageUrl: authState.user.avatarUrl,
                            size: 88,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            authState.user.displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                authState.user.id,
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: authState.user.id));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('ID copied!'),
                                      backgroundColor: AppColors.deepBlue,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                },
                                child: Icon(Icons.copy_rounded, size: 14, color: Colors.white.withValues(alpha: 0.35)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            authState.user.emailOrPhone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Settings section
                  _SettingsGroup(
                    children: [
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        iconColors: [AppColors.electricAqua, AppColors.deepBlue],
                        title: 'About Clique Pix',
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'Clique Pix',
                            applicationVersion: '1.0.0',
                            applicationLegalese: 'Private photo sharing for your inner circle.',
                          );
                        },
                      ),
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        iconColors: [AppColors.deepBlue, AppColors.violetAccent],
                        title: 'Privacy Policy',
                        onTap: () {},
                      ),
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        iconColors: [AppColors.violetAccent, const Color(0xFFEC4899)],
                        title: 'Terms of Service',
                        onTap: () {},
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sign out
                  _SettingsGroup(
                    children: [
                      _SettingsTile(
                        icon: Icons.logout_rounded,
                        iconColors: [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                        title: 'Sign Out',
                        titleColor: const Color(0xFFEF4444),
                        showDivider: false,
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A2035),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                              content: Text(
                                'Are you sure you want to sign out?',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444))),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ref.read(authStateProvider.notifier).signOut();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Delete Account
                  _SettingsGroup(
                    children: [
                      _SettingsTile(
                        icon: Icons.delete_forever_rounded,
                        iconColors: [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                        title: 'Delete Account',
                        titleColor: const Color(0xFFEF4444),
                        showDivider: false,
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A2035),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('Delete Account?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              content: Text(
                                'This will permanently delete your account, remove you from all circles, and delete all your photos. This action cannot be undone.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete My Account', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              await ref.read(authStateProvider.notifier).deleteAccount();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: const Color(0xFFEF4444)),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final List<Color> iconColors;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsTile({
    required this.icon,
    required this.iconColors,
    required this.title,
    this.titleColor,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: showDivider ? null : BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: iconColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: titleColor ?? Colors.white,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 64,
            color: Colors.white.withValues(alpha: 0.06),
          ),
      ],
    );
  }
}
