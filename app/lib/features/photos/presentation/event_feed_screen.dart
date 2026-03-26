import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
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
      loading: () {
        debugPrint('[CliquePix] EventFeed: loading photos for ${widget.eventId}');
        return ListView.builder(
        itemCount: 3,
        itemBuilder: (_, __) => const PhotoCardShimmer(),
      );},
      error: (err, _) {
        debugPrint('[CliquePix] EventFeed: error=$err');
        return AppErrorWidget(
        message: err.toString(),
        onRetry: () => ref.invalidate(eventPhotosProvider(widget.eventId)),
      );},
      data: (photos) {
        debugPrint('[CliquePix] EventFeed: loaded ${photos.length} photos');
        if (photos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                    child: const Icon(Icons.photo_camera_outlined, size: 56, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No photos yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Be the first to share a photo!',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
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
