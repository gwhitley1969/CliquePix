import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';
import 'circles_providers.dart';

class InviteScreen extends ConsumerWidget {
  final String circleId;
  const InviteScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleAsync = ref.watch(circleDetailProvider(circleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Invite Friends')),
      body: circleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (circle) {
          final inviteUrl = 'https://clique-pix.com/invite/${circle.inviteCode}';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.standardPadding * 2),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text('Invite to ${circle.name}', style: AppTextStyles.heading2),
                const SizedBox(height: 8),
                Text(
                  'Share this QR code or link to invite friends',
                  style: AppTextStyles.body.copyWith(color: AppColors.secondaryText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // QR Code
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.whiteSurface,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: inviteUrl,
                    size: 200,
                    backgroundColor: AppColors.whiteSurface,
                    eyeStyle: const QrEyeStyle(color: AppColors.deepBlue),
                    dataModuleStyle: const QrDataModuleStyle(color: AppColors.primaryText),
                  ),
                ),
                const SizedBox(height: 24),
                // Invite code display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.softAquaBackground,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(circle.inviteCode, style: AppTextStyles.heading2),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: inviteUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                GradientButton(
                  text: 'Share Invite Link',
                  onPressed: () {
                    Share.share(
                      'Join my circle "${circle.name}" on Clique Pix!\n$inviteUrl',
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
