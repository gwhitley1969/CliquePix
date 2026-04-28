import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/confirm_destructive_dialog.dart';
import '../../../widgets/error_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../events/presentation/events_providers.dart';
import 'photos_providers.dart';
import 'reaction_bar_widget.dart';

class PhotoDetailScreen extends ConsumerWidget {
  final String photoId;
  const PhotoDetailScreen({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoDetailProvider(photoId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.whiteSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/events');
            }
          },
        ),
        title: photoAsync.when(
          data: (p) => Text(AppDateUtils.formatDateTime(p.createdAt),
              style: const TextStyle(color: AppColors.whiteSurface, fontSize: 14)),
          loading: () => null,
          error: (_, __) => null,
        ),
        actions: [
          photoAsync.when(
            data: (photo) {
              final authState = ref.watch(authStateProvider);
              final currentUserId = authState is AuthAuthenticated
                  ? authState.user.id
                  : null;
              final eventAsync =
                  ref.watch(eventDetailProvider(photo.eventId));
              final eventCreatedByUserId =
                  eventAsync.valueOrNull?.createdByUserId;
              final isUploader = currentUserId != null &&
                  photo.uploadedByUserId == currentUserId;
              final isOrganizerDeletingOthers = currentUserId != null &&
                  eventCreatedByUserId != null &&
                  eventCreatedByUserId == currentUserId &&
                  photo.uploadedByUserId != currentUserId;
              final canDelete = isUploader || isOrganizerDeletingOthers;
              return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.whiteSurface),
              onSelected: (value) async {
                switch (value) {
                  case 'save':
                    try {
                      final storageService = ref.read(storageServiceProvider);
                      await storageService.savePhotoToGallery(
                        photo.originalUrl ?? photo.thumbnailUrl ?? '',
                        photo.id,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Photo saved to gallery')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')),
                        );
                      }
                    }
                    break;
                  case 'share':
                    try {
                      final storageService = ref.read(storageServiceProvider);
                      final filePath = await storageService.downloadToTempFile(
                        photo.originalUrl ?? photo.thumbnailUrl ?? '',
                        photo.id,
                      );
                      await Share.shareXFiles([XFile(filePath)]);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to share: $e')),
                        );
                      }
                    }
                    break;
                  case 'delete':
                    final copy = deleteDialogCopy(
                      mediaLabel: 'Photo',
                      isOrganizerDeletingOthers: isOrganizerDeletingOthers,
                    );
                    final confirm = await confirmDestructive(
                      context,
                      title: copy.title,
                      body: copy.body,
                      confirmLabel: copy.confirmLabel,
                    );
                    if (confirm) {
                      try {
                        await ref.read(photosRepositoryProvider).deletePhoto(photo.id);
                        // Invalidate feed before popping so the card vanishes
                        // immediately on return (without waiting for 30s poll).
                        ref.invalidate(eventPhotosProvider(photo.eventId));
                        if (context.mounted) context.pop();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to delete: $e')),
                          );
                        }
                      }
                    }
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'save', child: Row(children: [Icon(Icons.download), SizedBox(width: 8), Text('Save to Device')])),
                const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share), SizedBox(width: 8), Text('Share')])),
                if (canDelete)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Text(
                          isOrganizerDeletingOthers ? 'Remove' : 'Delete',
                          style: const TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ],
                    ),
                  ),
              ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: photoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.whiteSurface)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (photo) => Column(
          children: [
            Expanded(
              child: Hero(
                tag: 'photo_${photo.id}',
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: photo.originalUrl ?? photo.thumbnailUrl ?? '',
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: AppColors.whiteSurface)),
                    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: AppColors.whiteSurface, size: 48)),
                  ),
                ),
              ),
            ),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        photo.uploadedByName ?? 'User',
                        style: AppTextStyles.body.copyWith(color: AppColors.whiteSurface, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        AppDateUtils.timeAgo(photo.createdAt),
                        style: AppTextStyles.caption.copyWith(color: AppColors.whiteSurface.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ReactionBarWidget(
                    mediaId: photo.id,
                    reactionCounts: photo.reactionCounts,
                    userReactions: photo.userReactions,
                    onAdd: (type) =>
                        ref.read(photosRepositoryProvider).addReaction(photo.id, type),
                    onRemove: (reactionId) => ref
                        .read(photosRepositoryProvider)
                        .removeReaction(photo.id, reactionId),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
