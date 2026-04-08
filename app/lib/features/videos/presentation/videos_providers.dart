import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video_model.dart';
import '../../../services/api_client.dart';
import '../data/videos_api.dart';
import '../data/video_block_upload_service.dart';
import '../domain/videos_repository.dart';
import '../domain/video_validation_service.dart';

// ====================================================================================
// Service / API / Repository providers
// ====================================================================================

final videosApiProvider = Provider<VideosApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return VideosApi(apiClient.dio);
});

/// SharedPreferences async provider — used by the block upload service for
/// resume state. Provided as a FutureProvider because SharedPreferences.getInstance
/// is async; consumers use `.future` or `.requireValue` after the first await.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

final videoBlockUploadServiceProvider = FutureProvider<VideoBlockUploadService>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return VideoBlockUploadService(prefs);
});

final videosRepositoryProvider = FutureProvider<VideosRepository>((ref) async {
  final api = ref.watch(videosApiProvider);
  final uploader = await ref.watch(videoBlockUploadServiceProvider.future);
  return VideosRepository(api, uploader);
});

final videoValidationServiceProvider = Provider<VideoValidationService>((ref) {
  return VideoValidationService();
});

// ====================================================================================
// Data providers (videos for an event, single video metadata, playback)
// ====================================================================================

final eventVideosProvider = FutureProvider.family<List<VideoModel>, String>((ref, eventId) async {
  final repo = await ref.watch(videosRepositoryProvider.future);
  return repo.listVideos(eventId);
});

final videoDetailProvider = FutureProvider.family<VideoModel, String>((ref, videoId) async {
  final repo = await ref.watch(videosRepositoryProvider.future);
  return repo.getVideo(videoId);
});

final videoPlaybackProvider = FutureProvider.family<VideoPlaybackInfo, String>((ref, videoId) async {
  final repo = await ref.watch(videosRepositoryProvider.future);
  return repo.getPlayback(videoId);
});

// ====================================================================================
// Upload state notifier — tracks per-upload progress for the upload screen
// ====================================================================================

class VideoUploadState {
  final bool isUploading;
  final double progress; // 0.0 .. 1.0
  final String statusText;
  final String? errorText;
  final String? videoId;

  const VideoUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.statusText = '',
    this.errorText,
    this.videoId,
  });

  VideoUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? statusText,
    String? errorText,
    String? videoId,
  }) {
    return VideoUploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      errorText: errorText, // intentionally allow null reset
      videoId: videoId ?? this.videoId,
    );
  }
}

class VideoUploadNotifier extends StateNotifier<VideoUploadState> {
  VideoUploadNotifier() : super(const VideoUploadState());

  void start(String statusText) {
    state = VideoUploadState(isUploading: true, progress: 0.0, statusText: statusText);
  }

  void updateProgress(double progress, [String? statusText]) {
    state = state.copyWith(progress: progress, statusText: statusText);
  }

  void succeed(String videoId) {
    state = VideoUploadState(
      isUploading: false,
      progress: 1.0,
      statusText: 'Upload complete',
      videoId: videoId,
    );
  }

  void fail(String errorText) {
    state = state.copyWith(isUploading: false, errorText: errorText);
  }

  void reset() {
    state = const VideoUploadState();
  }
}

final videoUploadProvider =
    StateNotifierProvider.autoDispose<VideoUploadNotifier, VideoUploadState>(
  (ref) => VideoUploadNotifier(),
);
