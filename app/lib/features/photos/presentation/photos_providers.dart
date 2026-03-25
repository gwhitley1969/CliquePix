import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/photo_model.dart';
import '../domain/photos_repository.dart';
import '../domain/image_compression_service.dart';
import '../domain/blob_upload_service.dart';
import '../data/photos_api.dart';
import '../../../services/api_client.dart';

final photosApiProvider = Provider<PhotosApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PhotosApi(apiClient.dio);
});

final photosRepositoryProvider = Provider<PhotosRepository>((ref) {
  return PhotosRepository(ref.watch(photosApiProvider));
});

final imageCompressionProvider = Provider<ImageCompressionService>((ref) {
  return ImageCompressionService();
});

final blobUploadProvider = Provider<BlobUploadService>((ref) {
  return BlobUploadService();
});

final eventPhotosProvider = FutureProvider.family<List<PhotoModel>, String>((ref, eventId) async {
  final repo = ref.watch(photosRepositoryProvider);
  final result = await repo.listPhotos(eventId);
  return result.photos;
});

final photoDetailProvider = FutureProvider.family<PhotoModel, String>((ref, photoId) async {
  final repo = ref.watch(photosRepositoryProvider);
  return repo.getPhoto(photoId);
});
