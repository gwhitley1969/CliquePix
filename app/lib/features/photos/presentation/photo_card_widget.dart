import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/photo_model.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/loading_shimmer.dart';
import 'reaction_bar_widget.dart';

class PhotoCardWidget extends StatelessWidget {
  final PhotoModel photo;
  final String eventId;

  const PhotoCardWidget({
    super.key,
    required this.photo,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.standardPadding, vertical: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User attribution
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AvatarWidget(name: photo.uploadedByName ?? 'User', size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photo.uploadedByName ?? 'User',
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          AppDateUtils.timeAgo(photo.createdAt),
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Photo
            GestureDetector(
              onTap: () => context.go('/events/$eventId/photos/${photo.id}'),
              child: Hero(
                tag: 'photo_${photo.id}',
                child: CachedNetworkImage(
                  imageUrl: photo.thumbnailUrl ?? photo.originalUrl ?? '',
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
            // Reactions
            Padding(
              padding: const EdgeInsets.all(12),
              child: ReactionBarWidget(
                photoId: photo.id,
                reactionCounts: photo.reactionCounts,
                userReactions: photo.userReactions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
