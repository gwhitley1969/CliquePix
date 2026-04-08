import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'videos_providers.dart';

/// Upload progress UI for a validated video file.
///
/// Receives the validated File via GoRouter `extra`, kicks off the upload
/// flow (get-upload-url → block uploads → commit), and shows progress with
/// the per-block update granularity from VideoBlockUploadService.
class VideoUploadScreen extends ConsumerStatefulWidget {
  final String eventId;
  final File videoFile;
  final int durationSeconds;

  const VideoUploadScreen({
    super.key,
    required this.eventId,
    required this.videoFile,
    required this.durationSeconds,
  });

  @override
  ConsumerState<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends ConsumerState<VideoUploadScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Kick off upload after the first frame so we have access to ref.read
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUpload());
  }

  Future<void> _startUpload() async {
    if (_started) return;
    _started = true;

    final notifier = ref.read(videoUploadProvider.notifier);
    notifier.start('Preparing upload...');

    try {
      final repo = await ref.read(videosRepositoryProvider.future);
      final videoId = await repo.uploadVideo(
        eventId: widget.eventId,
        file: widget.videoFile,
        durationSeconds: widget.durationSeconds,
        onProgress: (p) {
          final percent = (p * 100).toInt();
          final statusText = p < 0.05
              ? 'Preparing upload...'
              : p < 0.95
                  ? 'Uploading $percent%'
                  : 'Finalizing...';
          notifier.updateProgress(p, statusText);
        },
      );
      notifier.succeed(videoId);

      // Invalidate the feed so the placeholder card appears
      ref.invalidate(eventVideosProvider(widget.eventId));

      // Pop back to the event after a brief success display
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      debugPrint('[CliquePix Video] Upload failed: $e');
      notifier.fail(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('VIDEO_LIMIT_REACHED')) {
      return "You've reached the 5-video limit for this event. Delete a video to upload another.";
    }
    if (s.contains('DURATION_EXCEEDED')) {
      return "Videos must be 5 minutes or shorter.";
    }
    if (s.contains('FILE_TOO_LARGE')) {
      return "This video is too large. Videos must be under 500MB.";
    }
    if (s.contains('SocketException') || s.contains('connection')) {
      return "Network error. Please check your connection and try again.";
    }
    return "Upload failed. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoUploadProvider);

    return Scaffold(
      backgroundColor: AppColors.primaryText,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Uploading video'),
        leading: state.isUploading
            ? const SizedBox.shrink() // Don't allow back during upload
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.errorText != null) ...[
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                state.errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  ref.read(videoUploadProvider.notifier).reset();
                  context.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricAqua,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Back'),
              ),
            ] else ...[
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: state.progress > 0 ? state.progress : null,
                      strokeWidth: 4,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  if (state.progress > 0)
                    Text(
                      '${(state.progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                state.statusText.isEmpty ? 'Starting upload...' : state.statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                "Keep the app open until upload finishes",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
