import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/photo_model.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/loading_shimmer.dart';
import '../../../widgets/media_owner_menu.dart';
import '../../../widgets/reactor_list_sheet.dart';
import '../../../widgets/reactor_strip.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import 'photos_providers.dart';
import 'reaction_bar_widget.dart';

class PhotoCardWidget extends ConsumerWidget {
  final PhotoModel photo;
  final String eventId;
  /// Event organizer's user ID — passed down from the feed so the 3-dot
  /// menu can render for organizers acting on someone else's media.
  /// Nullable when the event creator's account has been deleted.
  final String? eventCreatedByUserId;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const PhotoCardWidget({
    super.key,
    required this.photo,
    required this.eventId,
    this.eventCreatedByUserId,
    this.isSelecting = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    final isUploader =
        currentUserId != null && photo.uploadedByUserId == currentUserId;
    final isOrganizerDeletingOthers = currentUserId != null &&
        eventCreatedByUserId != null &&
        eventCreatedByUserId == currentUserId &&
        photo.uploadedByUserId != currentUserId;
    final canDelete = isUploader || isOrganizerDeletingOthers;

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
                    AvatarWidget(
                      name: photo.uploadedByName ?? 'User',
                      imageUrl: photo.uploadedByAvatarUrl,
                      thumbUrl: photo.uploadedByAvatarThumbUrl,
                      cacheKey: photo.uploadedByAvatarCacheKey,
                      framePreset: photo.uploadedByAvatarFramePreset,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photo.uploadedByName ?? 'User',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            AppDateUtils.timeAgo(photo.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    MediaOwnerMenu(
                      mediaLabel: 'Photo',
                      canDelete: canDelete,
                      isOrganizerDeletingOthers: isOrganizerDeletingOthers,
                      isSelecting: isSelecting,
                      onDelete: () async {
                        await ref
                            .read(photosRepositoryProvider)
                            .deletePhoto(photo.id);
                        ref.invalidate(eventPhotosProvider(photo.eventId));
                      },
                    ),
                  ],
                ),
              ),
              // Photo with optional selection checkbox
              Stack(
                children: [
                  GestureDetector(
                    onTap: isSelecting
                        ? onSelectionToggle
                        : () => context.push('/events/$eventId/photos/${photo.id}'),
                    child: Hero(
                      tag: 'photo_${photo.id}',
                      child: CachedNetworkImage(
                        imageUrl: photo.thumbnailUrl ?? photo.originalUrl ?? '',
                        // Stable cache key keyed on the photo ID. The backend
                        // regenerates fresh SAS URLs every feed refetch — without
                        // this, CachedNetworkImage cache-misses on every poll and
                        // the thumbnail flickers.
                        cacheKey: 'photo_thumb_${photo.id}',
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const LoadingShimmer(height: 300),
                        errorWidget: (_, __, ___) => Container(
                          height: 300,
                          color: AppColors.softAquaBackground,
                          child: const Center(child: Icon(Icons.broken_image, size: 48, color: AppColors.secondaryText)),
                        ),
                      ),
                    ),
                  ),
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
              ),
              // "Who reacted?" strip — only visible when total > 0; tap
              // opens the reactor sheet on the All tab.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: ReactorStrip(
                  totalReactions: photo.totalReactions,
                  topReactors: photo.topReactors,
                  onTap: () => ReactorListSheet.show(
                    context,
                    fetchReactors: () => ref
                        .read(photosRepositoryProvider)
                        .listReactors(photo.id),
                  ),
                ),
              ),
              // Reactions
              Padding(
                padding: const EdgeInsets.all(12),
                child: ReactionBarWidget(
                  mediaId: photo.id,
                  reactionCounts: photo.reactionCounts,
                  userReactions: photo.userReactions,
                  onAdd: (type) =>
                      ref.read(photosRepositoryProvider).addReaction(photo.id, type),
                  onRemove: (reactionId) => ref
                      .read(photosRepositoryProvider)
                      .removeReaction(photo.id, reactionId),
                  // Long-press a pill with count > 0 → sheet pre-filtered to
                  // that reaction type.
                  onShowReactors: (reactionType) => ReactorListSheet.show(
                    context,
                    fetchReactors: () => ref
                        .read(photosRepositoryProvider)
                        .listReactors(photo.id),
                    initialFilter: reactionType,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
