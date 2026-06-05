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
    try {
      await Gal.putImage(filePath);
    } finally {
      // Delete the temp file whether or not the gallery write succeeded — a Gal
      // failure (permission denied, gallery full) used to leak a full-size copy.
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<String> downloadToTempFile(String url, String id, {String extension = 'jpg'}) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/cliquepix_share_$id.$extension';
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

  /// Save a video to the device's photo library / gallery.
  /// Used for the "Save to device" action on a video card or video player.
  /// Downloads the MP4 fallback URL (always H.264 — universally compatible)
  /// rather than the HLS manifest, which can't be saved as a single file.
  Future<void> saveVideoToGallery(String mp4Url, String videoId) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/cliquepix_$videoId.mp4';

    await dio.download(mp4Url, filePath);
    try {
      await Gal.putVideo(filePath);
    } finally {
      // Delete the temp file even if the gallery write throws (a video temp can
      // be up to ~500MB — a leaked copy per failed save adds up fast).
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
