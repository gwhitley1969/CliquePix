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
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // 1. LOCAL FILE — uploader's device has the original. Fastest path.
      // VideoPlayerController.file() is correct here — the formatHint
      // caveat in CLAUDE.md only applies to HLS manifests; local MP4/MOV
      // files are auto-detected correctly.
      if (widget.localFilePath != null) {
        final file = File(widget.localFilePath!);
        if (await file.exists()) {
          debugPrint('[CliquePix Video] Local file path: ${widget.localFilePath}');
          _usedLocalFile = true;
          final controller = VideoPlayerController.file(file);
          await controller.initialize();
          _controller = controller;
          _wireChewieFromController(controller);
          return;
        }
        debugPrint('[CliquePix Video] Local file missing, falling through...');
      }

      // 2. INSTANT PREVIEW — uploader fallback (SAS to original blob).
      // Instant-preview path: skip /playback entirely and play the original
      // MP4 directly via a pre-signed SAS URL. The uploader's device captured
      // this video so codec compatibility is tautologically safe. Transcoding
      // still runs in the background; when video_ready arrives via Web PubSub,
      // the feed refreshes and future playback goes through the normal HLS/MP4
      // pipeline.
      if (widget.previewUrl != null) {
        debugPrint('[CliquePix Video] Instant-preview path: ${widget.previewUrl}');
        _usedInstantPreview = true;
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.previewUrl!),
        );
        await controller.initialize();
        _controller = controller;
        _wireChewieFromController(controller);
        return;
      }

      final repo = await ref.read(videosRepositoryProvider.future);
      final playback = await repo.getPlayback(widget.videoId);
      _playbackInfo = playback;

      // Try HLS first
      try {
        await _initWithHls(playback);
        return;
      } catch (e, st) {
        debugPrint('[CliquePix Video] HLS init failed (${e.runtimeType}): $e');
        debugPrint('[CliquePix Video] HLS stack: $st');
        debugPrint('[CliquePix Video] Falling back to MP4...');
      }

      // HLS failed — try MP4 fallback
      _usedFallback = true;
      try {
        await _initWithMp4(playback);
      } catch (e, st) {
        debugPrint('[CliquePix Video] MP4 fallback init failed (${e.runtimeType}): $e');
        debugPrint('[CliquePix Video] MP4 stack: $st');
        rethrow;
      }
    } catch (e) {
      debugPrint('[CliquePix Video] Player init failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = "We couldn't play this video. Please try again later.";
        });
      }
    }
  }

  /// Wires a ChewieController for the instant-preview path (no
  /// VideoPlaybackInfo available). Mirrors `_wireChewie` but takes just
  /// the controller.
  void _wireChewieFromController(VideoPlayerController controller) {
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
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initWithHls(VideoPlaybackInfo playback) async {
    // Materialize the manifest text into a temp file. video_player can play
    // HLS from a file:// URL but not from raw text or a data URL.
    final tempDir = await getTemporaryDirectory();
    final manifestFile = File('${tempDir.path}/cliquepix_video_${widget.videoId}.m3u8');
    await manifestFile.writeAsString(playback.hlsManifest);
    _tempManifestFile = manifestFile;

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
    await controller.initialize();
    _controller = controller;
    _wireChewie(controller, playback);
  }

  Future<void> _initWithMp4(VideoPlaybackInfo playback) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(playback.mp4FallbackUrl));
    await controller.initialize();
    _controller = controller;
    _wireChewie(controller, playback);
  }

  void _wireChewie(VideoPlayerController controller, VideoPlaybackInfo playback) {
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
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
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
  Future<void> _confirmAndDeleteVideo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text('This video will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final repo = await ref.read(videosRepositoryProvider.future);
      await repo.deleteVideo(widget.videoId);
      ref.invalidate(eventVideosProvider(widget.eventId));
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
                  await _confirmAndDeleteVideo();
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
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppColors.error)),
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
        else if (_usedFallback)
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
