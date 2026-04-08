import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/app_constants.dart';

/// Client-side video validation BEFORE upload starts.
/// Server-side ffprobe validation is the authoritative source of truth,
/// but client-side validation gives users a fast error response without
/// burning bandwidth on a doomed upload.
///
/// Uses video_player (already a dependency for playback) to extract
/// duration and dimensions. Initializing a player to read metadata is
/// slightly heavy (~200-500ms) but avoids adding another dependency
/// (video_compress) just for metadata extraction.

class VideoValidationResult {
  final bool isValid;
  final String? errorMessage;
  final Duration? duration;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final String? extension;

  const VideoValidationResult.valid({
    required this.duration,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.extension,
  })  : isValid = true,
        errorMessage = null;

  const VideoValidationResult.invalid(this.errorMessage)
      : isValid = false,
        duration = null,
        width = null,
        height = null,
        fileSizeBytes = null,
        extension = null;
}

class VideoValidationService {
  /// Validate a video file against CliquePix's hard limits:
  ///   - Extension must be mp4 or mov
  ///   - Duration must be ≤ 5 minutes
  ///   - File size must be ≤ 500MB
  ///   - File must be readable by video_player
  Future<VideoValidationResult> validate(File file) async {
    // Extension check
    final filename = file.path.split(Platform.pathSeparator).last;
    final extIdx = filename.lastIndexOf('.');
    if (extIdx < 0) {
      return const VideoValidationResult.invalid(
        "We can't tell what kind of file this is. Please use MP4 or MOV.",
      );
    }
    final ext = filename.substring(extIdx + 1).toLowerCase();
    if (!AppConstants.acceptedVideoExtensions.contains(ext)) {
      return const VideoValidationResult.invalid(
        "We can't process this video format. Please use MP4 or MOV.",
      );
    }

    // File size check
    final sizeBytes = await file.length();
    if (sizeBytes > AppConstants.maxVideoFileSizeBytes) {
      return const VideoValidationResult.invalid(
        "This video is too large. Videos must be under 500MB.",
      );
    }
    if (sizeBytes <= 0) {
      return const VideoValidationResult.invalid(
        "We couldn't read this video file. It may be damaged.",
      );
    }

    // Duration + dimensions via video_player
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();

      final duration = controller.value.duration;
      final size = controller.value.size;

      if (duration.inSeconds > AppConstants.maxVideoDurationSeconds) {
        return const VideoValidationResult.invalid(
          "Videos must be 5 minutes or shorter. Please trim your video and try again.",
        );
      }
      if (duration.inMilliseconds <= 0) {
        return const VideoValidationResult.invalid(
          "We couldn't read this video file. It may be damaged.",
        );
      }

      return VideoValidationResult.valid(
        duration: duration,
        width: size.width.toInt(),
        height: size.height.toInt(),
        fileSizeBytes: sizeBytes,
        extension: ext,
      );
    } catch (e) {
      debugPrint('[CliquePix Video] Validation failed: $e');
      return const VideoValidationResult.invalid(
        "We couldn't read this video file. It may be damaged or in an unsupported format.",
      );
    } finally {
      await controller?.dispose();
    }
  }
}
