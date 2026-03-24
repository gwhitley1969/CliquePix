import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/loading_shimmer.dart';
import 'photos_providers.dart';
import 'photo_card_widget.dart';

class EventFeedScreen extends ConsumerWidget {
  final String eventId;
  const EventFeedScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(eventPhotosProvider(eventId));

    return photosAsync.when(
      loading: () => ListView.builder(
        itemCount: 3,
        itemBuilder: (_, __) => const PhotoCardShimmer(),
      ),
      error: (err, _) => AppErrorWidget(
        message: err.toString(),
        onRetry: () => ref.invalidate(eventPhotosProvider(eventId)),
      ),
      data: (photos) {
        if (photos.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.photo_camera_outlined,
            title: 'No photos yet',
            subtitle: 'Be the first to share a photo!',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(eventPhotosProvider(eventId)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: photos.length,
            itemBuilder: (context, index) => PhotoCardWidget(
              photo: photos[index],
              eventId: eventId,
            ),
          ),
        );
      },
    );
  }
}
