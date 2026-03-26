import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class BlobUploadService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  Future<void> uploadToBlob(String sasUrl, File file) async {
    final bytes = await file.readAsBytes();
    debugPrint('[CliquePix] uploadToBlob: ${bytes.length} bytes to Azure');

    await _dio.put(
      sasUrl,
      data: bytes,
      options: Options(
        contentType: 'image/jpeg',
        responseType: ResponseType.bytes,
        headers: {
          'x-ms-blob-type': 'BlockBlob',
        },
      ),
    );
    debugPrint('[CliquePix] uploadToBlob: success');
  }
}
