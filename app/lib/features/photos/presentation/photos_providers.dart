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

// Photo selection state for multi-select download
class PhotoSelectionState {
  final bool isSelecting;
  final Set<String> selectedIds;
  const PhotoSelectionState({this.isSelecting = false, this.selectedIds = const {}});
}

class PhotoSelectionNotifier extends StateNotifier<PhotoSelectionState> {
  PhotoSelectionNotifier() : super(const PhotoSelectionState());

  void enterSelectionMode() {
    state = const PhotoSelectionState(isSelecting: true);
  }

  void exitSelectionMode() {
    state = const PhotoSelectionState();
  }

  void togglePhoto(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = PhotoSelectionState(isSelecting: true, selectedIds: updated);
  }

  void selectAll(List<String> ids) {
    state = PhotoSelectionState(isSelecting: true, selectedIds: Set<String>.from(ids));
  }

  void deselectAll() {
    state = const PhotoSelectionState(isSelecting: true);
  }
}

final photoSelectionProvider = StateNotifierProvider.family<PhotoSelectionNotifier, PhotoSelectionState, String>(
  (ref, eventId) => PhotoSelectionNotifier(),
);
