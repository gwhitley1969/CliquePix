import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/loading_shimmer.dart';
import 'photos_providers.dart';
import 'photo_card_widget.dart';

class EventFeedScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventFeedScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventFeedScreen> createState() => _EventFeedScreenState();
}

class _EventFeedScreenState extends ConsumerState<EventFeedScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      Duration(seconds: AppConstants.feedPollIntervalSeconds),
      (_) => ref.invalidate(eventPhotosProvider(widget.eventId)),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(eventPhotosProvider(widget.eventId));

    return photosAsync.when(
      loading: () => ListView.builder(
        itemCount: 3,
        itemBuilder: (_, __) => const PhotoCardShimmer(),
      ),
      error: (err, _) => AppErrorWidget(
        message: err.toString(),
        onRetry: () => ref.invalidate(eventPhotosProvider(widget.eventId)),
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
          onRefresh: () async => ref.invalidate(eventPhotosProvider(widget.eventId)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: photos.length,
            itemBuilder: (context, index) => PhotoCardWidget(
              photo: photos[index],
              eventId: widget.eventId,
            ),
          ),
        );
      },
    );
  }
}
