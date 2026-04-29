import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/upload_url_silent_retry.dart';
import '../../../services/telemetry_service.dart';
import '../domain/local_pending_video.dart';
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
  final String localTempId;

  const VideoUploadScreen({
    super.key,
    required this.eventId,
    required this.videoFile,
    required this.durationSeconds,
    required this.localTempId,
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
    final localNotifier = ref.read(localPendingVideosProvider(widget.eventId).notifier);
    notifier.start('Preparing upload...');
    localNotifier.updateStage(widget.localTempId, UploadStage.uploading);

    try {
      final repo = await ref.read(videosRepositoryProvider.future);
      final telemetry = ref.read(telemetryServiceProvider);
      final result = await repo.uploadVideo(
        eventId: widget.eventId,
        file: widget.videoFile,
        durationSeconds: widget.durationSeconds,
        wrapGetUploadUrl: (call) => silentRetryOn429(
          call,
          onSilenced: (sec) => telemetry.record(
            'video_upload_url_429_silenced',
            extra: {
              'retryAfterSeconds': sec.toString(),
              'eventId': widget.eventId,
            },
          ),
          onSilentRetrySucceeded: () => telemetry.record(
            'video_upload_url_429_silent_retry_succeeded',
          ),
          onSilentRetryFailed: (status) => telemetry.record(
            'video_upload_url_429_silent_retry_failed',
            extra: {'finalStatus': (status ?? -1).toString()},
          ),
        ),
        onProgress: (p) {
          final percent = (p * 100).toInt();
          final statusText = p < 0.05
              ? 'Preparing upload...'
              : p < 0.95
                  ? 'Uploading $percent%'
                  : 'Finalizing...';
          notifier.updateProgress(p, statusText);
          localNotifier.updateStage(
            widget.localTempId,
            p < 0.95 ? UploadStage.uploading : UploadStage.committing,
            progress: p,
          );
        },
      );
      notifier.succeed(result.videoId, previewUrl: result.previewUrl);
      localNotifier.updateStage(
        widget.localTempId,
        UploadStage.processing,
        serverVideoId: result.videoId,
        previewUrl: result.previewUrl,
      );

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
      localNotifier.updateStage(
        widget.localTempId,
        UploadStage.failed,
        errorMessage: _friendlyError(e),
      );
    }
  }

  String _friendlyError(Object e) {
    // Prefer the structured backend error code from the response body.
    // Dio has no validateStatus override, so 4xx responses reject to the
    // error path with .response.data populated from the parsed JSON body
    // { data: null, error: { code, message } }. Reading .error.code here is
    // more robust than string-matching on e.toString() (which only includes
    // DioException.message, set to the user-facing text — not the code).
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final errorMap = data['error'] as Map;
        final code = errorMap['code'] as String?;
        final backendMessage = errorMap['message'] as String?;
        switch (code) {
          case 'VIDEO_LIMIT_REACHED':
            // Use the backend message directly — it includes the current
            // limit dynamically (PER_USER_VIDEO_LIMIT may change server-side).
            if (backendMessage != null && backendMessage.isNotEmpty) return backendMessage;
            return "You've reached the video limit for this event. Delete a video to upload another.";
          case 'DURATION_EXCEEDED':
            return "Videos must be 5 minutes or shorter.";
          case 'FILE_TOO_LARGE':
            return "This video is too large. Videos must be under 500MB.";
          case 'UNSUPPORTED_CONTAINER':
            return "We can't process this video format. Please use MP4 or MOV.";
          case 'UNSUPPORTED_CODEC':
            return "This video uses a format we can't process. Try re-recording or exporting as H.264 or HEVC.";
          case 'CORRUPT_MEDIA':
            return "We couldn't read this video file. It may be damaged. Try re-recording or selecting a different video.";
          case 'HDR_CONVERSION_FAILED':
            return "We couldn't convert this HDR video for playback. Try re-recording in standard (non-HDR) mode.";
        }
        // Unknown code: fall through to the backend's own message (already
        // user-friendly by design — see VIDEO_ERROR_CODES in videos.ts).
        if (backendMessage != null && backendMessage.isNotEmpty) {
          return backendMessage;
        }
      }
    }
    final s = e.toString();
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
