class ImageHelpers {
  ImageHelpers._();

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static bool isValidImageType(String mimeType) {
    return mimeType == 'image/jpeg' || mimeType == 'image/png';
  }

  static bool isHeicFormat(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.heic') || lower.endsWith('.heif');
  }
}
