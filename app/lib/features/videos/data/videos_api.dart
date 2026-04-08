import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

/// Dio API client for the video endpoints. Mirrors PhotosApi structure.
/// All requests automatically pick up auth headers via the AuthInterceptor.
class VideosApi {
  final Dio dio;
  VideosApi(this.dio);

  /// POST /api/events/{eventId}/videos/upload-url
  /// Returns: { video_id, blob_path, block_size_bytes, block_count,
  ///            block_upload_urls: [{block_id, url}], commit_url }
  Future<Map<String, dynamic>> getUploadUrl(
    String eventId, {
    required String filename,
    required int sizeBytes,
    required int durationSeconds,
  }) async {
    final response = await dio.post(
      ApiEndpoints.videoUploadUrl(eventId),
      data: {
        'filename': filename,
        'size_bytes': sizeBytes,
        'duration_seconds': durationSeconds,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// POST /api/events/{eventId}/videos
  /// Commit the upload by submitting the ordered block list. Server stitches
  /// the blocks into the final blob and dispatches the transcoder job.
  /// Returns: { video_id, status, message }
  Future<Map<String, dynamic>> commitUpload(
    String eventId, {
    required String videoId,
    required List<String> blockIds,
  }) async {
    final response = await dio.post(
      ApiEndpoints.eventVideos(eventId),
      data: {
        'video_id': videoId,
        'block_ids': blockIds,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// GET /api/events/{eventId}/videos
  Future<Map<String, dynamic>> listVideos(String eventId) async {
    final response = await dio.get(ApiEndpoints.eventVideos(eventId));
    return response.data['data'] as Map<String, dynamic>;
  }

  /// GET /api/videos/{videoId}
  Future<Map<String, dynamic>> getVideo(String videoId) async {
    final response = await dio.get(ApiEndpoints.video(videoId));
    return response.data['data'] as Map<String, dynamic>;
  }

  /// GET /api/videos/{videoId}/playback
  /// Returns the rewritten HLS manifest text + fresh SAS URLs for fallback + poster.
  Future<Map<String, dynamic>> getPlayback(String videoId) async {
    final response = await dio.get(ApiEndpoints.videoPlayback(videoId));
    return response.data['data'] as Map<String, dynamic>;
  }

  /// DELETE /api/videos/{videoId}
  Future<void> deleteVideo(String videoId) async {
    await dio.delete(ApiEndpoints.video(videoId));
  }

  /// POST /api/videos/{videoId}/reactions
  Future<Map<String, dynamic>> addReaction(String videoId, String reactionType) async {
    final response = await dio.post(
      ApiEndpoints.videoReactions(videoId),
      data: {'reaction_type': reactionType},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// DELETE /api/videos/{videoId}/reactions/{reactionId}
  Future<void> removeReaction(String videoId, String reactionId) async {
    await dio.delete(ApiEndpoints.videoReaction(videoId, reactionId));
  }

  /// GET /api/events/{eventId}/media — unified mixed-media feed (photos + videos)
  Future<Map<String, dynamic>> listMedia(String eventId) async {
    final response = await dio.get(ApiEndpoints.eventMedia(eventId));
    return response.data['data'] as Map<String, dynamic>;
  }
}
