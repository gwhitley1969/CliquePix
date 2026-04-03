import 'dart:io';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  Future<void> savePhotoToGallery(String url, String photoId) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/cliquepix_$photoId.jpg';

    await dio.download(url, filePath);
    await Gal.putImage(filePath);

    // Clean up temp file
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> downloadToTempFile(String url, String photoId) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/cliquepix_share_$photoId.jpg';
    await dio.download(url, filePath);
    return filePath;
  }

  Future<int> savePhotosToGallery(
    List<({String url, String photoId})> photos,
    void Function(int completed, int total)? onProgress,
  ) async {
    int saved = 0;
    for (final photo in photos) {
      try {
        await savePhotoToGallery(photo.url, photo.photoId);
        saved++;
        onProgress?.call(saved, photos.length);
      } catch (_) {
        // Continue with remaining photos on failure
      }
    }
    return saved;
  }
}
