import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/error_widget.dart';
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
        title: photoAsync.when(
          data: (p) => Text(AppDateUtils.formatDateTime(p.createdAt),
              style: const TextStyle(color: AppColors.whiteSurface, fontSize: 14)),
          loading: () => null,
          error: (_, __) => null,
        ),
        actions: [
          photoAsync.when(
            data: (photo) => PopupMenuButton<String>(
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
                    Share.share(photo.originalUrl ?? photo.thumbnailUrl ?? '');
                    break;
                  case 'delete':
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Photo'),
                        content: const Text('This photo will be permanently deleted.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await ref.read(photosRepositoryProvider).deletePhoto(photo.id);
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
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: AppColors.error), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.error))])),
              ],
            ),
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
                        style: AppTextStyles.caption.copyWith(color: AppColors.whiteSurface.withOpacity(0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ReactionBarWidget(
                    photoId: photo.id,
                    reactionCounts: photo.reactionCounts,
                    userReactions: photo.userReactions,
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
