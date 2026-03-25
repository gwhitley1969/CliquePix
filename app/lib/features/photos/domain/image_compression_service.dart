import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';

class ImageCompressionService {
  Future<({File file, int width, int height})> compressImage(File sourceFile) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Get source image dimensions to avoid upscaling small images
    final sourceBytes = await sourceFile.readAsBytes();
    final sourceImage = await ui.decodeImageFromList(sourceBytes);
    final srcWidth = sourceImage.width;
    final srcHeight = sourceImage.height;

    // Only constrain if image exceeds max dimension on longest edge
    final maxDim = AppConstants.maxImageDimension;
    int targetWidth = srcWidth;
    int targetHeight = srcHeight;
    if (srcWidth > maxDim || srcHeight > maxDim) {
      if (srcWidth >= srcHeight) {
        targetWidth = maxDim;
        targetHeight = (srcHeight * maxDim / srcWidth).round();
      } else {
        targetHeight = maxDim;
        targetWidth = (srcWidth * maxDim / srcHeight).round();
      }
    }

    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.absolute.path,
      targetPath,
      quality: AppConstants.jpegQuality,
      minWidth: targetWidth,
      minHeight: targetHeight,
      format: CompressFormat.jpeg,
      keepExif: false,
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

    return (
      file: compressedFile,
      width: targetWidth,
      height: targetHeight,
    );
  }
}
