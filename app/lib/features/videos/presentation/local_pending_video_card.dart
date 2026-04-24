import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/avatar_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/local_pending_video.dart';

/// Feed card for a local pending video — the uploader's in-progress upload
/// that exists only on their device. Always tappable for local file playback.
class LocalPendingVideoCard extends ConsumerWidget {
  final LocalPendingVideo localVideo;
  final String eventId;

  const LocalPendingVideoCard({
    super.key,
    required this.localVideo,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth is AuthAuthenticated ? auth.user : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.standardPadding, vertical: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User attribution
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AvatarWidget(
                    name: currentUser?.displayName ?? 'You',
                    imageUrl: currentUser?.avatarUrl,
                    thumbUrl: currentUser?.avatarThumbUrl,
                    cacheKey: currentUser?.avatarCacheKey,
                    framePreset: currentUser?.avatarFramePreset,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          AppDateUtils.timeAgo(localVideo.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body — upload-stage-specific content
            _buildBody(context),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (localVideo.uploadStage == UploadStage.failed) {
      return _buildFailedState(context);
    }
    return _buildProgressState(context);
  }

  Widget _buildProgressState(BuildContext context) {
    final stage = localVideo.uploadStage;
    final title = switch (stage) {
      UploadStage.localOnly => 'Ready to upload',
      UploadStage.uploading => 'Uploading...',
      UploadStage.committing => 'Finalizing...',
      UploadStage.processing => 'Processing for sharing...',
      _ => 'Preparing...',
    };
    final subtitle = stage == UploadStage.uploading
        ? '${(localVideo.uploadProgress * 100).toInt()}% \u2022 Tap to play'
        : 'Tap to play';

    return GestureDetector(
      onTap: () => _openLocalPlayer(context),
      child: Stack(
        children: [
          Container(
            height: 240,
            width: double.infinity,
            color: AppColors.softAquaBackground.withValues(alpha: 0.15),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Play button overlay
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  // Upload progress bar for uploading stage
                  if (stage == UploadStage.uploading) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: localVideo.uploadProgress,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  ],
                  // Spinner for committing/processing stages
                  if (stage == UploadStage.committing || stage == UploadStage.processing) ...[
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Duration badge (bottom right)
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                localVideo.durationLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedState(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      color: Colors.red.withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Colors.red.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload failed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (localVideo.errorMessage != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  localVideo.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openLocalPlayer(context),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _retryUpload(context),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricAqua,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openLocalPlayer(BuildContext context) {
    context.push(
      '/events/$eventId/videos/${localVideo.serverVideoId ?? localVideo.localTempId}',
      extra: <String, String?>{
        'localFilePath': localVideo.localFilePath,
        'previewUrl': localVideo.previewUrl,
      },
    );
  }

  void _retryUpload(BuildContext context) {
    context.pushReplacement(
      '/events/$eventId/videos/upload',
      extra: {
        'file': File(localVideo.localFilePath),
        'durationSeconds': localVideo.durationSeconds,
        'localTempId': localVideo.localTempId,
      },
    );
  }
}
