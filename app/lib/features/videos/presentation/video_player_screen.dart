import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/video_model.dart';
import 'videos_providers.dart';

/// In-app video player screen.
///
/// Strategy:
///   1. Fetch playback metadata from the backend (HLS manifest text + MP4 fallback URL)
///   2. Materialize the manifest text into a temporary .m3u8 file
///   3. Try to play via HLS (video_player handles AVPlayer/ExoPlayer internally)
///   4. On HLS init failure, fall back to the MP4 progressive URL
class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String videoId;

  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  File? _tempManifestFile;
  bool _isLoading = true;
  bool _usedFallback = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final repo = await ref.read(videosRepositoryProvider.future);
      final playback = await repo.getPlayback(widget.videoId);

      // Try HLS first
      try {
        await _initWithHls(playback);
        return;
      } catch (e) {
        debugPrint('[CliquePix Video] HLS init failed: $e — falling back to MP4');
      }

      // HLS failed — try MP4 fallback
      _usedFallback = true;
      await _initWithMp4(playback);
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

  Future<void> _initWithHls(VideoPlaybackInfo playback) async {
    // Materialize the manifest text into a temp file. video_player can play
    // HLS from a file:// URL but not from raw text or a data URL.
    final tempDir = await getTemporaryDirectory();
    final manifestFile = File('${tempDir.path}/cliquepix_video_${widget.videoId}.m3u8');
    await manifestFile.writeAsString(playback.hlsManifest);
    _tempManifestFile = manifestFile;

    final controller = VideoPlayerController.file(manifestFile);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
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
        if (_usedFallback)
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
