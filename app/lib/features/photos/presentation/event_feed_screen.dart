import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/photo_model.dart';
import '../../../models/video_model.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/loading_shimmer.dart';
import '../../dm/domain/dm_realtime_service.dart';
import '../../dm/presentation/dm_providers.dart';
import '../../videos/domain/local_pending_video.dart';
import '../../videos/presentation/videos_providers.dart';
import '../../videos/presentation/video_card_widget.dart';
import '../../videos/presentation/local_pending_video_card.dart';
import 'photos_providers.dart';
import 'photo_card_widget.dart';

/// Discriminated union for mixed-media feed items.
/// Exactly one of `photo`, `video`, or `localVideo` is non-null.
class _MediaListItem {
  final DateTime createdAt;
  final PhotoModel? photo;
  final VideoModel? video;
  final LocalPendingVideo? localVideo;

  _MediaListItem.photo(PhotoModel p)
      : photo = p,
        video = null,
        localVideo = null,
        createdAt = p.createdAt;

  _MediaListItem.video(VideoModel v)
      : photo = null,
        video = v,
        localVideo = null,
        createdAt = v.createdAt;

  _MediaListItem.localVideo(LocalPendingVideo lv)
      : photo = null,
        video = null,
        localVideo = lv,
        createdAt = lv.createdAt;

  bool get isPhoto => photo != null;
  bool get isLocalVideo => localVideo != null;
  String get id => photo?.id ?? video?.id ?? localVideo!.localTempId;
}

class EventFeedScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventFeedScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventFeedScreen> createState() => _EventFeedScreenState();
}

class _EventFeedScreenState extends ConsumerState<EventFeedScreen> {
  Timer? _pollTimer;
  StreamSubscription<VideoReadyEvent>? _videoReadySub;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      Duration(seconds: AppConstants.feedPollIntervalSeconds),
      (_) {
        ref.invalidate(eventPhotosProvider(widget.eventId));
        ref.invalidate(eventVideosProvider(widget.eventId));
      },
    );
    _setupVideoReadyListener();
  }

  /// Subscribe to the Web PubSub `video_ready` stream so the feed refreshes
  /// in-place the instant a video finishes transcoding (no waiting for the
  /// 30-second poll timer). Mirrors the DM realtime setup in dm_chat_screen.
  Future<void> _setupVideoReadyListener() async {
    try {
      final realtimeService = ref.read(dmRealtimeServiceProvider);
      realtimeService.onNegotiate = () => ref.read(dmRepositoryProvider).negotiate();
      if (!realtimeService.isConnected) {
        final url = await ref.read(dmRepositoryProvider).negotiate();
        await realtimeService.connect(url);
      }
      _videoReadySub = realtimeService.onVideoReady.listen((event) {
        if (event.eventId == widget.eventId && mounted) {
          debugPrint('[CliquePix EventFeed] video_ready: invalidating feed for ${event.videoId}');
          ref.invalidate(eventVideosProvider(widget.eventId));
          ref.invalidate(eventPhotosProvider(widget.eventId));
          // Reconcile: mark the matching local pending item as complete so
          // the server's active card takes over in the next build.
          ref.read(localPendingVideosProvider(widget.eventId).notifier)
              .reconcileComplete(event.videoId);
        }
      });
    } catch (e) {
      debugPrint('[CliquePix EventFeed] Video realtime setup failed: $e');
    }
  }

  @override
  void dispose() {
    _videoReadySub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _downloadSelected(List<({String url, String photoId})> photos) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadTotal = photos.length;
    });

    final storageService = ref.read(storageServiceProvider);
    final saved = await storageService.savePhotosToGallery(
      photos,
      (completed, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = completed;
            _downloadTotal = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() => _isDownloading = false);
      ref.read(photoSelectionProvider(widget.eventId).notifier).exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $saved of ${photos.length} photos to gallery'),
          backgroundColor: const Color(0xFF1A2035),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(eventPhotosProvider(widget.eventId));
    final videosAsync = ref.watch(eventVideosProvider(widget.eventId));
    final selectionState = ref.watch(photoSelectionProvider(widget.eventId));
    final isSelecting = selectionState.isSelecting;
    final selectedIds = selectionState.selectedIds;

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
        // Pull videos out of the AsyncValue (gracefully degrade if videos
        // endpoint errors — the photo feed should still render).
        final videos = videosAsync.maybeWhen(
          data: (v) => v,
          orElse: () => <VideoModel>[],
        );

        // Local pending videos for this event (uploader-only items)
        final localPendings = ref.watch(localPendingVideosProvider(widget.eventId));

        // Server video IDs that a local pending item "owns" (still in
        // progress). These server items get suppressed so the local item
        // takes precedence — it has the local file path for instant playback.
        final locallyOwnedServerIds = localPendings
            .where((lp) => lp.serverVideoId != null && lp.uploadStage != UploadStage.complete)
            .map((lp) => lp.serverVideoId!)
            .toSet();
        final filteredVideos = videos.where((v) => !locallyOwnedServerIds.contains(v.id)).toList();

        // Filter out local items that should be retired (server version active)
        final activeLocalPendings = localPendings.where((lp) {
          if (lp.uploadStage == UploadStage.complete) return false;
          if (lp.serverVideoId != null) {
            final serverVideo = videos.where((v) => v.id == lp.serverVideoId).firstOrNull;
            if (serverVideo != null && serverVideo.isReady) {
              // Auto-retire: server video is active, local item no longer needed.
              // Deferred to avoid modifying provider state during build.
              Future.microtask(() {
                ref.read(localPendingVideosProvider(widget.eventId).notifier)
                    .reconcileComplete(lp.serverVideoId!);
              });
              return false;
            }
          }
          return true;
        }).toList();

        // Build the unified, time-ordered media list
        final mediaItems = <_MediaListItem>[
          ...photos.map(_MediaListItem.photo),
          ...filteredVideos.map(_MediaListItem.video),
          ...activeLocalPendings.map(_MediaListItem.localVideo),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        debugPrint('[CliquePix] EventFeed: loaded ${photos.length} photos + ${videos.length} videos + ${activeLocalPendings.length} local pending');

        if (mediaItems.isEmpty) {
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
                    'No photos or videos yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Be the first to share something!',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // Selection toolbar (still uses photo IDs only — videos are excluded
            // from multi-select download in v1; the user can save individual
            // videos via the video player screen)
            _SelectionToolbar(
              isSelecting: isSelecting,
              selectedCount: selectedIds.length,
              totalCount: photos.length,
              allSelected: selectedIds.length == photos.length,
              onEnterSelection: () {
                ref.read(photoSelectionProvider(widget.eventId).notifier).enterSelectionMode();
              },
              onSelectAll: () {
                ref.read(photoSelectionProvider(widget.eventId).notifier)
                    .selectAll(photos.map((p) => p.id).toList());
              },
              onDeselectAll: () {
                ref.read(photoSelectionProvider(widget.eventId).notifier).deselectAll();
              },
              onCancel: () {
                ref.read(photoSelectionProvider(widget.eventId).notifier).exitSelectionMode();
              },
            ),

            // Mixed media feed (photos + videos interleaved by created_at)
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(eventPhotosProvider(widget.eventId));
                  ref.invalidate(eventVideosProvider(widget.eventId));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: mediaItems.length,
                  itemBuilder: (context, index) {
                    final item = mediaItems[index];
                    if (item.isLocalVideo) {
                      return LocalPendingVideoCard(
                        localVideo: item.localVideo!,
                        eventId: widget.eventId,
                      );
                    } else if (item.isPhoto) {
                      final photo = item.photo!;
                      return PhotoCardWidget(
                        photo: photo,
                        eventId: widget.eventId,
                        isSelecting: isSelecting,
                        isSelected: selectedIds.contains(photo.id),
                        onSelectionToggle: () {
                          ref.read(photoSelectionProvider(widget.eventId).notifier)
                              .togglePhoto(photo.id);
                        },
                      );
                    } else {
                      // Video card — selection mode doesn't apply to videos in v1
                      return VideoCardWidget(
                        video: item.video!,
                        eventId: widget.eventId,
                        isSelecting: false,
                      );
                    }
                  },
                ),
              ),
            ),

            // Download action bar
            if (isSelecting && selectedIds.isNotEmpty)
              _DownloadActionBar(
                selectedCount: selectedIds.length,
                isDownloading: _isDownloading,
                progress: _downloadTotal > 0 ? _downloadProgress / _downloadTotal : 0,
                onDownload: _isDownloading
                    ? null
                    : () {
                        final selected = photos
                            .where((p) => selectedIds.contains(p.id))
                            .map((p) => (
                                  url: p.originalUrl ?? p.thumbnailUrl ?? '',
                                  photoId: p.id,
                                ))
                            .where((p) => p.url.isNotEmpty)
                            .toList();
                        _downloadSelected(selected);
                      },
              ),
          ],
        );
      },
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  final bool isSelecting;
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onEnterSelection;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onCancel;

  const _SelectionToolbar({
    required this.isSelecting,
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onEnterSelection,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSelecting) {
      // Show a subtle "Select" button when not in selection mode
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onEnterSelection,
              icon: Icon(Icons.checklist_rounded, size: 18, color: Colors.white.withValues(alpha: 0.6)),
              label: Text('Select', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }

    // Selection mode toolbar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF162033),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: allSelected ? onDeselectAll : onSelectAll,
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              size: 18,
              color: AppColors.electricAqua,
            ),
            label: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(fontSize: 13, color: AppColors.electricAqua),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$selectedCount selected',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          TextButton(
            onPressed: onCancel,
            child: Text('Cancel', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadActionBar extends StatelessWidget {
  final int selectedCount;
  final bool isDownloading;
  final double progress;
  final VoidCallback? onDownload;

  const _DownloadActionBar({
    required this.selectedCount,
    required this.isDownloading,
    required this.progress,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF162033),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDownloading)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
                    minHeight: 4,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onDownload,
                icon: isDownloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  isDownloading
                      ? 'Downloading...'
                      : 'Download $selectedCount Photo${selectedCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricAqua,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
