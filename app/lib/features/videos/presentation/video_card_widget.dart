import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/video_model.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/loading_shimmer.dart';

/// Feed card variant for videos. Three visual states based on video.status:
///   1. processing — placeholder card with spinner (poster doesn't exist yet)
///   2. active     — poster + duration overlay + play icon (tap to open player)
///   3. rejected   — error card with friendly message
class VideoCardWidget extends StatelessWidget {
  final VideoModel video;
  final String eventId;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const VideoCardWidget({
    super.key,
    required this.video,
    required this.eventId,
    this.isSelecting = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.standardPadding, vertical: 8),
      child: GestureDetector(
        onTap: isSelecting ? onSelectionToggle : null,
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            side: isSelected
                ? const BorderSide(color: AppColors.electricAqua, width: 2)
                : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User attribution
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    AvatarWidget(name: video.uploadedByName ?? 'User', size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.uploadedByName ?? 'User',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            AppDateUtils.timeAgo(video.createdAt),
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
              // Body — switches based on processing state
              _buildBody(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (video.isProcessing) {
      return _buildProcessingPlaceholder();
    }
    if (video.isFailed) {
      return _buildFailedState();
    }
    return _buildReadyState(context);
  }

  /// ★ USER CONTRIBUTION POINT 7 — Processing-state UX copy
  ///
  /// Shown while a video is transcoding (status='processing'). The user
  /// sees this for 1-5 minutes per video upload, so it's some of the most-
  /// viewed copy in the entire app.
  ///
  /// Approved default (Gene 2026-04-07): friendly + reassuring tone, no
  /// technical jargon ("transcoding", "HDR normalization"). Single line of
  /// copy plus a short subtitle. Spinner provides movement so the card
  /// doesn't look frozen.
  ///
  /// Tone: "Almost ready..." conveys progress without overpromising speed.
  /// The subtitle "Polishing your video" is conversational without being twee.
  Widget _buildProcessingPlaceholder() {
    return Container(
      height: 240,
      width: double.infinity,
      color: AppColors.softAquaBackground.withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Almost ready...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Polishing your video',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedState() {
    return Container(
      height: 200,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "We couldn't process this video",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            if (video.processingError != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  video.processingError!,
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
          ],
        ),
      ),
    );
  }

  Widget _buildReadyState(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: isSelecting
              ? onSelectionToggle
              : () => context.push('/events/$eventId/videos/${video.id}'),
          child: Hero(
            tag: 'video_${video.id}',
            child: CachedNetworkImage(
              imageUrl: video.posterUrl ?? '',
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) => const LoadingShimmer(height: 300),
              errorWidget: (_, __, ___) => Container(
                height: 300,
                color: AppColors.softAquaBackground,
                child: const Center(
                  child: Icon(Icons.broken_image, size: 48, color: AppColors.secondaryText),
                ),
              ),
            ),
          ),
        ),
        // Play icon overlay (centered)
        if (!isSelecting)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                ),
              ),
            ),
          ),
        // Duration overlay (bottom right)
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
              video.durationLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // Selection checkbox (top right)
        if (isSelecting)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.electricAqua
                    : Colors.black.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}
