import 'dart:io';
import 'dart:typed_data';
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
}
