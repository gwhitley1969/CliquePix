import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class PhotosApi {
  final Dio dio;
  PhotosApi(this.dio);

  Future<Map<String, dynamic>> getUploadUrl(String eventId) async {
    final response = await dio.post(ApiEndpoints.photoUploadUrl(eventId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmUpload(String eventId, {
    required String photoId,
    required String mimeType,
    int? width,
    int? height,
    String? originalFilename,
  }) async {
    final response = await dio.post(
      ApiEndpoints.eventPhotos(eventId),
      data: {
        'photo_id': photoId,
        'mime_type': mimeType,
        'width': width,
        'height': height,
        'original_filename': originalFilename,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listPhotos(String eventId, {String? cursor, int limit = 20}) async {
    final queryParams = <String, dynamic>{'limit': limit};
    if (cursor != null) queryParams['cursor'] = cursor;
    final response = await dio.get(ApiEndpoints.eventPhotos(eventId), queryParameters: queryParams);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPhoto(String photoId) async {
    final response = await dio.get(ApiEndpoints.photo(photoId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> deletePhoto(String photoId) async {
    await dio.delete(ApiEndpoints.photo(photoId));
  }

  Future<Map<String, dynamic>> addReaction(String photoId, String reactionType) async {
    final response = await dio.post(
      ApiEndpoints.photoReactions(photoId),
      data: {'reaction_type': reactionType},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> removeReaction(String photoId, String reactionId) async {
    await dio.delete(ApiEndpoints.reaction(photoId, reactionId));
  }

  /// GET /api/photos/{photoId}/reactions — full reactor list for the
  /// "who reacted?" sheet. Returns the raw envelope payload; the repo
  /// layer parses into a [ReactorList].
  Future<Map<String, dynamic>> listReactions(String photoId) async {
    final response = await dio.get(ApiEndpoints.photoReactions(photoId));
    return response.data['data'] as Map<String, dynamic>;
  }
}
