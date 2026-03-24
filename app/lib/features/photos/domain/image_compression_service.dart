import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';

class ImageCompressionService {
  Future<({File file, int width, int height})> compressImage(File sourceFile) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.absolute.path,
      targetPath,
      quality: AppConstants.jpegQuality,
      minWidth: AppConstants.maxImageDimension,
      minHeight: AppConstants.maxImageDimension,
      format: CompressFormat.jpeg,
      keepExif: false, // Strip EXIF data (GPS, device info)
    );

    if (result == null) {
      throw Exception('Image compression failed');
    }

    final compressedFile = File(result.path);
    final fileSize = await compressedFile.length();

    if (fileSize > AppConstants.maxFileSizeBytes) {
      await compressedFile.delete();
      throw Exception('Image too large after compression (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). Maximum is 10MB.');
    }

    // Get image dimensions
    final bytes = await compressedFile.readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);

    return (
      file: compressedFile,
      width: decodedImage.width,
      height: decodedImage.height,
    );
  }
}
