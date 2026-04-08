import 'dart:io';
import '../../../models/video_model.dart';
import '../data/videos_api.dart';
import '../data/video_block_upload_service.dart';

/// Domain-layer repository wrapping VideosApi + VideoBlockUploadService.
/// Hides the two-phase upload + transcoder dispatch from the UI layer.
class VideosRepository {
  final VideosApi api;
  final VideoBlockUploadService uploader;

  VideosRepository(this.api, this.uploader);

  /// Full upload flow: get upload URL → upload all blocks → commit.
  /// Returns the video_id once committed.
  ///
  /// On any failure mid-upload, the resume cache remains so the next call
  /// with the same file (and a new upload URL) can pick up where it left off.
  Future<String> uploadVideo({
    required String eventId,
    required File file,
    required int durationSeconds,
    required void Function(double progress) onProgress,
  }) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final sizeBytes = await file.length();

    // 1. Get upload URLs from the backend
    onProgress(0.05);
    final uploadInfo = await api.getUploadUrl(
      eventId,
      filename: filename,
      sizeBytes: sizeBytes,
      durationSeconds: durationSeconds,
    );
    final videoId = uploadInfo['video_id'] as String;
    final blockUrlsRaw = uploadInfo['block_upload_urls'] as List<dynamic>;
    final blockUrls = blockUrlsRaw
        .map((e) {
          final m = e as Map<String, dynamic>;
          return (
            blockId: m['block_id'] as String,
            url: m['url'] as String,
          );
        })
        .toList();

    // 2. Upload blocks (with resume support)
    await uploader.uploadVideo(
      videoId: videoId,
      file: file,
      blockUploadUrls: blockUrls,
      // Reserve 5% for the get-upload-url step and 5% for the commit step
      onProgress: (p) => onProgress(0.05 + p * 0.90),
    );

    // 3. Commit the upload — server commits the block list and dispatches
    onProgress(0.95);
    await api.commitUpload(
      eventId,
      videoId: videoId,
      blockIds: blockUrls.map((b) => b.blockId).toList(),
    );

    onProgress(1.0);
    return videoId;
  }

  Future<List<VideoModel>> listVideos(String eventId) async {
    final data = await api.listVideos(eventId);
    final videos = (data['videos'] as List<dynamic>?)
            ?.map((v) => VideoModel.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];
    return videos;
  }

  Future<VideoModel> getVideo(String videoId) async {
    final data = await api.getVideo(videoId);
    return VideoModel.fromJson(data);
  }

  Future<VideoPlaybackInfo> getPlayback(String videoId) async {
    final data = await api.getPlayback(videoId);
    return VideoPlaybackInfo.fromJson(data);
  }

  Future<void> deleteVideo(String videoId) async {
    await api.deleteVideo(videoId);
  }

  Future<({String id, String type})> addReaction(
      String videoId, String reactionType) async {
    final data = await api.addReaction(videoId, reactionType);
    return (
      id: data['id'] as String,
      type: data['reaction_type'] as String,
    );
  }

  Future<void> removeReaction(String videoId, String reactionId) async {
    await api.removeReaction(videoId, reactionId);
  }
}
