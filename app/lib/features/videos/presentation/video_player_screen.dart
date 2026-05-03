import 'dart:async' show TimeoutException;
import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/video_model.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/confirm_destructive_dialog.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../events/presentation/events_providers.dart';
import 'videos_providers.dart';

/// In-app video player screen.
///
/// Strategy:
///   1. Fetch playback metadata from the backend (HLS manifest text + MP4 fallback URL)
///   2. Materialize the manifest text into a temporary .m3u8 file
///   3. Try to play via HLS (video_player handles AVPlayer/ExoPlayer internally)
///   4. On HLS init failure, fall back to the MP4 progressive URL
class VideoPlayerScreen extends ConsumerStatefulWidget {
  /// Owning event — needed so the delete action can invalidate the feed
  /// provider (`eventVideosProvider(eventId)`) and pop cleanly.
  final String eventId;
  final String videoId;
  /// Local file path for uploader's just-captured/selected video. Highest
  /// priority playback source — zero network wait, guaranteed codec compat.
  final String? localFilePath;
  /// Instant-preview SAS URL for the original blob. If present, the player
  /// skips the /playback API call and opens the original MP4 directly.
  /// Only set when the uploader taps a card for their own processing video.
  final String? previewUrl;

  const VideoPlayerScreen({
    super.key,
    required this.eventId,
    required this.videoId,
    this.localFilePath,
    this.previewUrl,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  File? _tempManifestFile;
  VideoPlaybackInfo? _playbackInfo;
  bool _isLoading = true;
  bool _usedLocalFile = false;
  bool _usedFallback = false;
  bool _usedInstantPreview = false;
  /// iOS-only: cloud playback skipped HLS and used MP4 directly. Distinct
  /// from `_usedFallback` (which implies degraded service) — on iOS, MP4 IS
  /// the primary path because AVPlayer hangs on file:// HLS playlists with
  /// https:// segment URLs. v1 is single-rendition HLS, so MP4 progressive
  /// download with +faststart is functionally equivalent. Used to suppress
  /// the misleading "Playing standard quality" caption on iOS.
  bool _iosForcedMp4 = false;
  bool _isRecovering = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  /// Initializes a VideoPlayerController with a hard timeout. On any
  /// exception (including TimeoutException), disposes the controller before
  /// rethrowing — critical on iOS where an orphaned AVPlayerItem can wedge
  /// the next player attempt by holding the AVPlayer slot. [tier] is logged
  /// at the [VPS] tag for tier-by-tier diagnosis (Phase 1 of the iPhone
  /// playback hang investigation — see plan).
  Future<void> _initWithTimeout(
    VideoPlayerController controller,
    Duration timeout,
    String tier,
  ) async {
    debugPrint('[VPS] tier=$tier: about to await initialize() '
               '(timeout=${timeout.inSeconds}s)');
    final stopwatch = Stopwatch()..start();
    try {
      await controller.initialize().timeout(timeout);
      debugPrint('[VPS] tier=$tier: initialize() returned OK '
                 'after ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[VPS] tier=$tier: initialize() FAILED '
                 'after ${stopwatch.elapsedMilliseconds}ms (${e.runtimeType}): $e');
      try {
        await controller.dispose();
      } catch (disposeErr) {
        debugPrint('[VPS] tier=$tier: dispose() also failed: $disposeErr');
      }
      rethrow;
    }
  }

  Future<void> _initializePlayer() async {
    debugPrint('[VPS] enter _initializePlayer videoId=${widget.videoId} '
               'hasLocalPath=${widget.localFilePath != null} '
               'hasPreviewUrl=${widget.previewUrl != null}');
    try {
      // 1. LOCAL FILE — uploader's device has the original. Fastest path.
      // VideoPlayerController.file() is correct here — the formatHint
      // caveat in CLAUDE.md only applies to HLS manifests; local MP4/MOV
      // files are auto-detected correctly.
      if (widget.localFilePath != null) {
        debugPrint('[VPS] tier=local: path=${widget.localFilePath}');
        final file = File(widget.localFilePath!);
        final exists = await file.exists();
        debugPrint('[VPS] tier=local: file.exists()=$exists');
        if (exists) {
          _usedLocalFile = true;
          final controller = VideoPlayerController.file(file);
          await _initWithTimeout(
            controller, const Duration(seconds: 8), 'local');
          _controller = controller;
          _wireChewieFromController(controller);
          return;
        }
        debugPrint('[VPS] tier=local: file missing, falling through');
      }

      // 2. INSTANT PREVIEW — uploader fallback (SAS to original blob).
      // Instant-preview path: skip /playback entirely and play the original
      // MP4 directly via a pre-signed SAS URL. The uploader's device captured
      // this video so codec compatibility is tautologically safe. Transcoding
      // still runs in the background; when video_ready arrives via Web PubSub,
      // the feed refreshes and future playback goes through the normal HLS/MP4
      // pipeline.
      if (widget.previewUrl != null) {
        debugPrint('[VPS] tier=preview: url=${widget.previewUrl!.substring(0, widget.previewUrl!.length > 100 ? 100 : widget.previewUrl!.length)}...');
        _usedInstantPreview = true;
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.previewUrl!),
        );
        await _initWithTimeout(
          controller, const Duration(seconds: 15), 'preview');
        _controller = controller;
        _wireChewieFromController(controller);
        return;
      }

      debugPrint('[VPS] tier=cloud: fetching /playback');
      final repo = await ref.read(videosRepositoryProvider.future);
      final playback = await repo.getPlayback(widget.videoId);
      _playbackInfo = playback;

      // iOS bypasses HLS entirely. AVPlayer hangs indefinitely on a file://
      // HLS playlist whose segment lines are absolute https:// SAS URLs (the
      // shape produced by /playback rewriting). The 15s timeout in the safety
      // net catches it and falls through to MP4, but every iOS user would eat
      // the wait on every cloud playback. Going straight to MP4 keeps the UX
      // instant. v1 is single-rendition HLS so MP4 progressive download with
      // +faststart is functionally equivalent. Revisit when adaptive bitrate
      // ladders ship in v1.5 (would require backend raw-m3u8 endpoint to
      // serve the manifest via https:// instead of file:// — see Phase 2 of
      // iPhone playback hang plan).
      if (Platform.isIOS) {
        debugPrint('[VPS] tier=cloud: iOS — skipping HLS, going to MP4');
        _iosForcedMp4 = true;
        await _initWithMp4(playback);
        return;
      }

      debugPrint('[VPS] tier=cloud: got playback info, attempting HLS first');

      // Try HLS first
      try {
        await _initWithHls(playback);
        return;
      } catch (e, st) {
        debugPrint('[VPS] tier=cloud: HLS init failed (${e.runtimeType}): $e');
        debugPrint('[VPS] tier=cloud: HLS stack: $st');
        debugPrint('[VPS] tier=cloud: Falling back to MP4...');
      }

      // HLS failed — try MP4 fallback
      _usedFallback = true;
      try {
        await _initWithMp4(playback);
      } catch (e, st) {
        debugPrint('[VPS] tier=cloud: MP4 fallback init failed (${e.runtimeType}): $e');
        debugPrint('[VPS] tier=cloud: MP4 stack: $st');
        rethrow;
      }
    } catch (e, st) {
      debugPrint('[VPS] CAUGHT (${e.runtimeType}): $e');
      debugPrint('[VPS] stack: $st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = e is TimeoutException
              ? "Playback didn't start in time. Tap back and try again."
              : "We couldn't play this video. Please try again later.";
        });
      }
    }
  }

  /// Wires a ChewieController for the local-file or instant-preview path
  /// (no VideoPlaybackInfo available). Mirrors `_wireChewie` but takes just
  /// the controller. If the user navigated away during init, disposes the
  /// controller instead of leaking it (was a real bug pre-fix: ChewieController
  /// was constructed before the mounted check, then state mutation was skipped,
  /// leaving _chewieController == null which renders SizedBox.shrink — blank).
  void _wireChewieFromController(VideoPlayerController controller) {
    if (!mounted) {
      debugPrint('[VPS] _wireChewieFromController: !mounted, disposing');
      controller.dispose();
      return;
    }
    setState(() {
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.electricAqua,
          handleColor: AppColors.electricAqua,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );
      _isLoading = false;
    });
  }

  Future<void> _initWithHls(VideoPlaybackInfo playback) async {
    // Materialize the manifest text into a temp file. video_player can play
    // HLS from a file:// URL but not from raw text or a data URL.
    //
    // KNOWN iOS LIMITATION (under investigation — Phase 1 of iPhone playback
    // hang plan): AVPlayer may hang indefinitely on a file:// HLS playlist
    // whose segment lines are absolute https:// URLs. ExoPlayer (Android)
    // handles this fine. If Phase 1 device logs confirm the hypothesis, this
    // path will be Android-only with iOS forced to MP4 fallback.
    final tempDir = await getTemporaryDirectory();
    final manifestFile = File('${tempDir.path}/cliquepix_video_${widget.videoId}.m3u8');
    await manifestFile.writeAsString(playback.hlsManifest);
    _tempManifestFile = manifestFile;
    debugPrint('[VPS] tier=hls: manifest written to ${manifestFile.path} '
               '(${playback.hlsManifest.length} bytes)');

    // We use networkUrl with a file:// URI instead of .file() because only
    // the network constructors expose formatHint. formatHint is REQUIRED —
    // video_player does not auto-detect HLS from the .m3u8 extension when
    // loading via the file constructor. Without the hint, both AVFoundation
    // and ExoPlayer default to ProgressiveMediaSource and try to parse the
    // manifest text as a raw video stream, throwing during init.
    final controller = VideoPlayerController.networkUrl(
      Uri.file(manifestFile.path),
      formatHint: VideoFormat.hls,
    );
    await _initWithTimeout(controller, const Duration(seconds: 15), 'hls');
    _controller = controller;
    _wireChewie(controller, playback);
  }

  Future<void> _initWithMp4(VideoPlaybackInfo playback) async {
    debugPrint('[VPS] tier=mp4: url=${playback.mp4FallbackUrl.substring(0, playback.mp4FallbackUrl.length > 100 ? 100 : playback.mp4FallbackUrl.length)}...');
    final controller = VideoPlayerController.networkUrl(Uri.parse(playback.mp4FallbackUrl));
    await _initWithTimeout(controller, const Duration(seconds: 15), 'mp4');
    _controller = controller;
    _wireChewie(controller, playback);
  }

  void _wireChewie(VideoPlayerController controller, VideoPlaybackInfo playback) {
    if (!mounted) {
      debugPrint('[VPS] _wireChewie: !mounted, disposing');
      controller.dispose();
      return;
    }
    setState(() {
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.electricAqua,
          handleColor: AppColors.electricAqua,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );
      // Listen for playback errors (e.g. SAS token expiry after 15-min pause).
      // On error, re-fetch /playback for a fresh manifest and reload at the
      // current position. Only applies to cloud HLS/MP4 playback — local file
      // and instant-preview paths don't use SAS tokens.
      controller.addListener(_onPlaybackError);
      _isLoading = false;
    });
  }

  void _onPlaybackError() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.hasError || _isRecovering) return;
    if (_usedLocalFile || _usedInstantPreview) return; // no SAS tokens to expire
    debugPrint('[CliquePix Video] Playback error detected — attempting SAS recovery');
    _recoverFromSasExpiry(ctrl.value.position);
  }

  Future<void> _recoverFromSasExpiry(Duration position) async {
    if (_isRecovering || !mounted) return;
    _isRecovering = true;
    setState(() => _isLoading = true);

    try {
      // Dispose old controllers
      _controller?.removeListener(_onPlaybackError);
      _chewieController?.dispose();
      _controller?.dispose();
      _chewieController = null;
      _controller = null;

      // Re-fetch fresh playback manifest with new SAS URLs
      final repo = await ref.read(videosRepositoryProvider.future);
      final playback = await repo.getPlayback(widget.videoId);
      _playbackInfo = playback;

      // Try HLS first, fall back to MP4
      try {
        await _initWithHls(playback);
      } catch (_) {
        _usedFallback = true;
        await _initWithMp4(playback);
      }

      // Seek to the position where playback failed
      await _controller?.seekTo(position);
      debugPrint('[CliquePix Video] SAS recovery succeeded at ${position.inSeconds}s');
    } catch (e) {
      debugPrint('[CliquePix Video] SAS recovery failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = "Playback session expired. Please go back and try again.";
        });
      }
    } finally {
      _isRecovering = false;
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackError);
    _chewieController?.dispose();
    _controller?.dispose();
    if (_tempManifestFile != null) {
      _tempManifestFile!.delete().catchError((_) => _tempManifestFile!);
    }
    super.dispose();
  }

  Future<void> _saveVideo() async {
    try {
      final storageService = ref.read(storageServiceProvider);
      await storageService.saveVideoToGallery(
        _playbackInfo!.mp4FallbackUrl,
        widget.videoId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video saved to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _shareVideo() async {
    try {
      final storageService = ref.read(storageServiceProvider);
      final filePath = await storageService.downloadToTempFile(
        _playbackInfo!.mp4FallbackUrl,
        widget.videoId,
        extension: 'mp4',
      );
      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    }
  }

  /// Prompt for confirmation, delete the video via the repository, invalidate
  /// the feed provider so the card disappears immediately, then pop back to
  /// the event feed. Works even when the player failed to init (e.g., broken
  /// HDR blobs from pre-v0.1.5 transcodes) because the AppBar is rendered
  /// unconditionally — the menu stays reachable in the error state.
  ///
  /// [isOrganizerDeletingOthers] drives the moderation-flavored dialog copy
  /// (Remove vs Delete). Captured at call time from the build-method state.
  Future<void> _confirmAndDeleteVideo({
    required bool isOrganizerDeletingOthers,
  }) async {
    final copy = deleteDialogCopy(
      mediaLabel: 'Video',
      isOrganizerDeletingOthers: isOrganizerDeletingOthers,
    );
    final confirm = await confirmDestructive(
      context,
      title: copy.title,
      body: copy.body,
      confirmLabel: copy.confirmLabel,
    );
    if (!confirm) return;
    try {
      final repo = await ref.read(videosRepositoryProvider.future);
      await repo.deleteVideo(widget.videoId);
      ref.invalidate(eventVideosProvider(widget.eventId));

      // Retire any local-pending entry whose serverVideoId matches.
      // Without this, the feed merge in event_feed_screen would re-render
      // a ghost "Polishing your video" card after the server delete.
      final pending =
          ref.read(localPendingVideosProvider(widget.eventId));
      final notifier = ref
          .read(localPendingVideosProvider(widget.eventId).notifier);
      for (final item
          in pending.where((p) => p.serverVideoId == widget.videoId)) {
        notifier.remove(item.localTempId);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the video detail + event detail so we can gate the Delete
    // action on ownership (uploader OR event organizer). `.valueOrNull`
    // gives us null while loading / on error — in both cases we hide the
    // Delete item (the safer default; the menu still works for Save/Share
    // when the player has playback info).
    final videoAsync = ref.watch(videoDetailProvider(widget.videoId));
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final authState = ref.watch(authStateProvider);
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    final uploaderId = videoAsync.valueOrNull?.uploadedByUserId;
    final eventCreatedByUserId = eventAsync.valueOrNull?.createdByUserId;
    final isUploader =
        currentUserId != null && uploaderId == currentUserId;
    final isOrganizerDeletingOthers = currentUserId != null &&
        eventCreatedByUserId != null &&
        eventCreatedByUserId == currentUserId &&
        uploaderId != null &&
        uploaderId != currentUserId;
    final canDelete = isUploader || isOrganizerDeletingOthers;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              switch (value) {
                case 'save':
                  await _saveVideo();
                case 'share':
                  await _shareVideo();
                case 'delete':
                  await _confirmAndDeleteVideo(
                    isOrganizerDeletingOthers: isOrganizerDeletingOthers,
                  );
              }
            },
            itemBuilder: (_) => [
              // Save/Share only available when we have playback info
              // (video is active, not preview/local mode)
              if (_playbackInfo != null && !_usedInstantPreview) ...[
                const PopupMenuItem(
                  value: 'save',
                  child: Row(
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text('Save to Device'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share),
                      SizedBox(width: 8),
                      Text('Share'),
                    ],
                  ),
                ),
              ],
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
          ),
        ],
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
      );
    }
    if (_errorText != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white60),
            const SizedBox(height: 12),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }
    if (_chewieController == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: Chewie(controller: _chewieController!)),
        if (_usedLocalFile)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Playing from your device',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          )
        else if (_usedInstantPreview)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Playing preview while we finish processing...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          )
        else if (_usedFallback && !_iosForcedMp4)
          // Suppressed on iOS-forced-MP4 path: MP4 is the primary cloud
          // playback on iOS (HLS hangs on AVPlayer with file:// playlists),
          // not a degraded fallback — showing the caption would mislead.
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Playing standard quality',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ),
      ],
    );
  }
}
