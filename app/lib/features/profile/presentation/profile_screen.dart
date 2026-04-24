import 'dart:io';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/branded_sliver_app_bar.dart';
import '../../../widgets/confirm_destructive_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../../models/user_model.dart';
import 'avatar_editor_screen.dart';
import 'avatar_picker_sheet.dart';
import 'avatar_providers.dart';
import 'widgets/animated_empty_avatar.dart';
import 'widgets/first_visit_hint.dart';

const _supportEmail = 'support@xtend-ai.com';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          const BrandedSliverAppBar(
            screenTitle: 'Profile',
            accentColor: Color(0xFFEC4899),
            accentOpacity: 0.10,
            screenTitleGradient: LinearGradient(
              colors: [AppColors.violetAccent, Color(0xFFEC4899)],
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
                          _TappableAvatarSection(user: authState.user),
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
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clique Pix'),
                              content: const Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Version 1.0.0'),
                                  SizedBox(height: 12),
                                  Text('Private photo and video sharing for your inner circle.'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        iconColors: [AppColors.deepBlue, AppColors.violetAccent],
                        title: 'Terms of Service',
                        onTap: () => launchUrl(
                          Uri.parse('https://clique-pix.com/docs/terms'),
                          mode: LaunchMode.inAppBrowserView,
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        iconColors: [AppColors.violetAccent, const Color(0xFFEC4899)],
                        title: 'Privacy Policy',
                        onTap: () => launchUrl(
                          Uri.parse('https://clique-pix.com/docs/privacy'),
                          mode: LaunchMode.inAppBrowserView,
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.mail_outline_rounded,
                        iconColors: [const Color(0xFFEC4899), AppColors.electricAqua],
                        title: 'Contact Us',
                        showDivider: false,
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A2035),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text(
                                'Contact Us',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'For help, feedback, or bug reports:',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                  ),
                                  const SizedBox(height: 12),
                                  const SelectableText(
                                    _supportEmail,
                                    style: TextStyle(
                                      color: AppColors.electricAqua,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Clipboard.setData(const ClipboardData(text: _supportEmail));
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Email copied!'),
                                        backgroundColor: AppColors.deepBlue,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Copy Email',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await launchUrl(
                                      Uri.parse(
                                        'mailto:$_supportEmail'
                                        '?subject=${Uri.encodeComponent('Clique Pix Support')}',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  child: const Text(
                                    'Send Email',
                                    style: TextStyle(color: AppColors.electricAqua, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
                          final confirm = await confirmDestructive(
                            context,
                            title: 'Delete Account?',
                            body:
                                'This will permanently delete your account, remove you from all cliques, and delete all your photos. This action cannot be undone.',
                            confirmLabel: 'Delete My Account',
                          );
                          if (confirm) {
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
                  const _VersionTapCounter(),
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

/// Tap the version 7 times to unlock the Token Diagnostics screen. The
/// unlock persists — once tapped, a discrete "Token Diagnostics" link
/// appears below the version for the remainder of the session.
class _VersionTapCounter extends ConsumerStatefulWidget {
  const _VersionTapCounter();

  @override
  ConsumerState<_VersionTapCounter> createState() =>
      _VersionTapCounterState();
}

class _VersionTapCounterState extends ConsumerState<_VersionTapCounter> {
  int _taps = 0;
  bool _unlocked = false;

  void _tap() {
    if (_unlocked) {
      context.push('/diagnostics/tokens');
      return;
    }
    setState(() => _taps++);
    if (_taps >= 7) {
      setState(() => _unlocked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token Diagnostics unlocked')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Text(
            'Version 1.0.0',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),
        if (_unlocked) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => context.push('/diagnostics/tokens'),
            child: Text(
              'Token Diagnostics',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tappable profile avatar with first-visit hint, animated empty-state
/// pulse, picker sheet wiring, and a confetti burst on the user's first
/// successful upload. Lives inline in this file because it's only used
/// on the Profile screen — extracting it to a separate file would make
/// the session-local "has confetti already fired" state harder to reason
/// about.
class _TappableAvatarSection extends ConsumerStatefulWidget {
  final UserModel user;
  const _TappableAvatarSection({required this.user});

  @override
  ConsumerState<_TappableAvatarSection> createState() => _TappableAvatarSectionState();
}

class _TappableAvatarSectionState extends ConsumerState<_TappableAvatarSection> {
  static const _confettiPrefsKey = 'first_avatar_celebrated';
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 1500));

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final user = widget.user;
    HapticFeedback.selectionClick();
    final choice = await AvatarPickerSheet.show(
      context,
      canRemove: user.avatarUrl != null,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case AvatarPickerResult.takePhoto:
      case AvatarPickerResult.chooseFromLibrary:
        await _launchEditor(fromCamera: choice == AvatarPickerResult.takePhoto);
        break;
      case AvatarPickerResult.remove:
        await _removeAvatar();
        break;
    }
  }

  Future<void> _launchEditor({required bool fromCamera}) async {
    final repo = ref.read(avatarRepositoryProvider);
    final pick = fromCamera ? await repo.pickFromCamera() : await repo.pickFromGallery();
    if (!mounted || pick == null) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarEditorScreen(sourceFile: File(pick.path)),
      ),
    );
    if (!mounted || result == null) return;
    // Fire confetti on the user's first-ever successful upload.
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_confettiPrefsKey) ?? false)) {
      await prefs.setBool(_confettiPrefsKey, true);
      HapticFeedback.mediumImpact();
      _confetti.play();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _removeAvatar() async {
    final confirm = await confirmDestructive(
      context,
      title: 'Remove avatar?',
      body: 'Your initials will be shown on photos, videos, and messages instead.',
      confirmLabel: 'Remove',
    );
    if (!confirm || !mounted) return;
    try {
      final updated = await ref.read(avatarRepositoryProvider).deleteAvatar();
      ref.read(authStateProvider.notifier).updateUserAvatar(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove avatar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final hasAvatar = user.avatarUrl != null;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            if (!hasAvatar) const FirstVisitHint(),
            if (hasAvatar)
              GestureDetector(
                onTap: _onTap,
                behavior: HitTestBehavior.opaque,
                child: AvatarWidget(
                  name: user.displayName,
                  imageUrl: user.avatarUrl,
                  thumbUrl: user.avatarThumbUrl,
                  cacheKey: user.avatarCacheKey,
                  framePreset: user.avatarFramePreset,
                  size: 88,
                ),
              )
            else
              AnimatedEmptyAvatar(
                name: user.displayName,
                framePreset: user.avatarFramePreset,
                size: 88,
                onTap: _onTap,
              ),
          ],
        ),
        // Confetti fires from behind the avatar and blasts outward in a
        // downward arc so particles land on the user card below.
        Positioned(
          top: 44,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 24,
            gravity: 0.3,
            maxBlastForce: 14,
            minBlastForce: 6,
            colors: const [
              AppColors.electricAqua,
              AppColors.deepBlue,
              AppColors.violetAccent,
              Color(0xFFEC4899),
              Color(0xFFFBBF24),
            ],
          ),
        ),
      ],
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
