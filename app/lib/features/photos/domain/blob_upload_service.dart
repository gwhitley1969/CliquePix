import 'dart:io';
import 'package:dio/dio.dart';

class BlobUploadService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  Future<void> uploadToBlob(String sasUrl, File file) async {
    final bytes = await file.readAsBytes();

    await _dio.put(
      sasUrl,
      data: bytes,
      options: Options(
        headers: {
          'x-ms-blob-type': 'BlockBlob',
          'Content-Type': 'image/jpeg',
          'Content-Length': bytes.length,
        },
      ),
    );
  }
}
