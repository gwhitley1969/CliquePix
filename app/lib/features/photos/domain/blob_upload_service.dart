import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Typed exception raised when a direct PUT to Azure Blob Storage fails.
///
/// Parses Azure's XML error envelope when present so callers can map the
/// `azureCode` (e.g., `AuthorizationFailure`, `AuthenticationFailed`,
/// `InvalidHeaderValue`) to user-facing messages.
class BlobUploadFailure implements Exception {
  final int? statusCode;
  final String? azureCode;
  final String? azureMessage;
  final Object cause;

  BlobUploadFailure(
    this.cause, {
    this.statusCode,
    this.azureCode,
    this.azureMessage,
  });

  @override
  String toString() =>
      'BlobUploadFailure($statusCode $azureCode: $azureMessage)';
}

class BlobUploadService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  Future<void> uploadToBlob(String sasUrl, File file) async {
    final bytes = await file.readAsBytes();
    debugPrint('[CliquePix] uploadToBlob: ${bytes.length} bytes to Azure');

    try {
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
    } on DioException catch (e) {
      final parsed = _parseAzureError(e.response?.data);
      debugPrint(
        '[CliquePix] uploadToBlob: failed status=${e.response?.statusCode} '
        'azureCode=${parsed.code} message=${parsed.message}',
      );
      throw BlobUploadFailure(
        e,
        statusCode: e.response?.statusCode,
        azureCode: parsed.code,
        azureMessage: parsed.message,
      );
    }
  }

  static _AzureError _parseAzureError(Object? body) {
    String? text;
    if (body is List<int>) {
      try {
        text = utf8.decode(body, allowMalformed: true);
      } catch (_) {
        text = null;
      }
    } else if (body is String) {
      text = body;
    }
    if (text == null) return const _AzureError(null, null);
    final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(text)?.group(1);
    final msg = RegExp(r'<Message>([^<]+)</Message>').firstMatch(text)?.group(1);
    return _AzureError(code, msg);
  }
}

class _AzureError {
  final String? code;
  final String? message;
  const _AzureError(this.code, this.message);
}
