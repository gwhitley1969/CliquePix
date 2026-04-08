import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';

/// Block-based resumable upload service for videos.
///
/// Splits a local video file into 4MB blocks, uploads each via individual
/// SAS URLs (one per block), and persists block-success state to
/// shared_preferences so an interrupted upload can resume on the next launch.
///
/// Used by VideosRepository.uploadVideo, called from the upload screen.
///
/// Resume semantics:
///   - On first call, all blocks are uploaded sequentially.
///   - If the app is killed mid-upload, completed block IDs are persisted
///     under the key `video_upload_progress_<videoId>`.
///   - On retry (same videoId, same blocks), already-uploaded blocks are
///     skipped — only the failed/missing blocks are re-uploaded.
///   - On success, the progress key is cleared.
class VideoBlockUploadService {
  final Dio _dio;
  final SharedPreferences _prefs;

  VideoBlockUploadService(this._prefs)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 120),
        ));

  static String _progressKey(String videoId) => 'video_upload_progress_$videoId';

  /// Upload a video file in 4MB blocks.
  ///
  /// [videoId] — used as the cache key for resume support
  /// [file] — the local video file to upload
  /// [blockUploadUrls] — ordered list of (block_id, url) returned by the
  ///                      backend's upload-url endpoint
  /// [onProgress] — called after each block uploads, with progress 0.0..1.0
  Future<void> uploadVideo({
    required String videoId,
    required File file,
    required List<({String blockId, String url})> blockUploadUrls,
    required void Function(double progress) onProgress,
  }) async {
    final completedBlocks = _loadProgress(videoId);
    final totalBlocks = blockUploadUrls.length;
    final blockSize = AppConstants.videoBlockSizeBytes;
    final fileLength = await file.length();

    debugPrint('[CliquePix Video] Starting upload: $videoId, $totalBlocks blocks, ${completedBlocks.length} already done');

    final raf = await file.open();
    try {
      for (int i = 0; i < totalBlocks; i++) {
        final blockId = blockUploadUrls[i].blockId;

        if (completedBlocks.contains(blockId)) {
          debugPrint('[CliquePix Video] Skipping block $i (already uploaded)');
          onProgress((i + 1) / totalBlocks);
          continue;
        }

        // Read this block from the file
        final start = i * blockSize;
        final end = min(start + blockSize, fileLength);
        await raf.setPosition(start);
        final chunk = await raf.read(end - start);

        // Upload the block with retry
        await _uploadBlockWithRetry(blockUploadUrls[i].url, chunk, i);

        completedBlocks.add(blockId);
        await _saveProgress(videoId, completedBlocks);
        onProgress((i + 1) / totalBlocks);
      }
    } finally {
      await raf.close();
    }

    // Success — clear the resume cache
    await _clearProgress(videoId);
    debugPrint('[CliquePix Video] Upload complete: $videoId');
  }

  /// ★ USER CONTRIBUTION POINT 6 — Block upload retry policy
  ///
  /// This method uploads a single block to its SAS URL with retry on failure.
  /// You decide the retry policy.
  ///
  /// Considerations:
  ///   - Max retries: 3 is the default in CliquePix's RetryInterceptor for
  ///     general API calls. Block uploads on flaky mobile data might benefit
  ///     from more (5? 10?). But too many retries can drain battery and
  ///     mask real connectivity problems.
  ///   - Backoff curve: linear, exponential, or constant?
  ///     - Exponential: 500ms, 1s, 2s, 4s — good for transient blips
  ///     - Linear: 1s, 2s, 3s, 4s — more aggressive
  ///     - Constant: 2s, 2s, 2s, 2s — predictable, simpler
  ///   - What constitutes a retryable failure: 5xx? Connection timeouts?
  ///     4xx never retryable? Specific Azure storage error codes?
  ///   - Permanent failure: throw and let the upload pause? Or skip the
  ///     block and try the next one (broken state)?
  ///
  /// Reference: see app/lib/services/retry_interceptor.dart for the existing
  /// pattern (max 3 retries, exponential backoff at 500ms * 2^n).
  ///
  /// TODO(gene): implement the retry policy. Use _dio.put(url, data: chunk,
  /// options: Options(headers: {'x-ms-blob-type': 'BlockBlob'}))
  Future<void> _uploadBlockWithRetry(
    String url,
    Uint8List chunk,
    int blockIndex,
  ) async {
    // Approved default (Gene 2026-04-07): exponential backoff matching the
    // existing RetryInterceptor pattern. 5 retries (more than the 3 used for
    // general API calls because mobile data can be very flaky during a long
    // multi-block upload). Permanent failure throws — the upload pauses and
    // can be resumed later from the last successful block.
    //
    // Retryable: any DioException that's a network/timeout/5xx error.
    // Non-retryable: 4xx responses (almost always client bugs).
    const maxRetries = 5;
    Object? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _dio.put(
          url,
          data: Stream.fromIterable([chunk]),
          options: Options(
            headers: {
              'x-ms-blob-type': 'BlockBlob',
              'Content-Length': chunk.length.toString(),
              'Content-Type': 'application/octet-stream',
            },
            // Don't auto-retry via the RetryInterceptor — we have our own loop
            extra: {'noRetry': true},
          ),
        );
        if (attempt > 0) {
          debugPrint('[CliquePix Video] Block $blockIndex succeeded on retry $attempt');
        }
        return;
      } on DioException catch (e) {
        lastError = e;
        final statusCode = e.response?.statusCode;
        final isRetryable = statusCode == null ||
            statusCode >= 500 ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;

        if (!isRetryable || attempt >= maxRetries) {
          debugPrint('[CliquePix Video] Block $blockIndex failed permanently: $e');
          rethrow;
        }

        // Exponential backoff: 500ms, 1s, 2s, 4s, 8s
        final delayMs = 500 * pow(2, attempt).toInt();
        debugPrint('[CliquePix Video] Block $blockIndex attempt ${attempt + 1} failed (status=$statusCode), retrying in ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      } catch (e) {
        // Non-Dio errors (file I/O, etc.) are not retried
        debugPrint('[CliquePix Video] Block $blockIndex non-retryable error: $e');
        rethrow;
      }
    }

    throw Exception('Block $blockIndex upload failed after $maxRetries retries: $lastError');
  }

  // ====================================================================================
  // Resume state persistence
  // ====================================================================================

  Set<String> _loadProgress(String videoId) {
    final list = _prefs.getStringList(_progressKey(videoId)) ?? [];
    return list.toSet();
  }

  Future<void> _saveProgress(String videoId, Set<String> blockIds) async {
    await _prefs.setStringList(_progressKey(videoId), blockIds.toList());
  }

  Future<void> _clearProgress(String videoId) async {
    await _prefs.remove(_progressKey(videoId));
  }

  /// Public method to clear progress for a video — used when the user
  /// cancels an upload or the upload times out beyond resume.
  Future<void> clearProgress(String videoId) => _clearProgress(videoId);
}
