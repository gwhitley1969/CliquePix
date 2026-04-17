import '../../../models/photo_model.dart';
import '../data/photos_api.dart';

class PhotosRepository {
  final PhotosApi api;
  PhotosRepository(this.api);

  Future<({String photoId, String uploadUrl})> getUploadUrl(String eventId) async {
    final data = await api.getUploadUrl(eventId);
    return (
      photoId: data['photo_id'] as String,
      uploadUrl: data['upload_url'] as String,
    );
  }

  Future<PhotoModel> confirmUpload(String eventId, {
    required String photoId,
    required String mimeType,
    int? width,
    int? height,
    String? originalFilename,
  }) async {
    final data = await api.confirmUpload(
      eventId,
      photoId: photoId,
      mimeType: mimeType,
      width: width,
      height: height,
      originalFilename: originalFilename,
    );
    return PhotoModel.fromJson(data);
  }

  Future<({List<PhotoModel> photos, String? nextCursor})> listPhotos(
    String eventId, {String? cursor, int limit = 20}
  ) async {
    final data = await api.listPhotos(eventId, cursor: cursor, limit: limit);
    final photos = (data['photos'] as List<dynamic>)
        .map((e) => PhotoModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      photos: photos,
      nextCursor: data['next_cursor'] as String?,
    );
  }

  Future<PhotoModel> getPhoto(String photoId) async {
    final data = await api.getPhoto(photoId);
    return PhotoModel.fromJson(data);
  }

  Future<void> deletePhoto(String photoId) async {
    await api.deletePhoto(photoId);
  }

  Future<({String id, String type})> addReaction(String photoId, String reactionType) async {
    final data = await api.addReaction(photoId, reactionType);
    return (
      id: data['id'] as String,
      type: data['reaction_type'] as String,
    );
  }

  Future<void> removeReaction(String photoId, String reactionId) async {
    await api.removeReaction(photoId, reactionId);
  }
}
