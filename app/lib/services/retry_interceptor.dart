import 'dart:math';
import 'package:dio/dio.dart';

/// Retries transient failures with exponential backoff. Designed to be
/// conservative — never retries:
///   - 429 Too Many Requests (rate limit; client should respect Retry-After)
///   - 4xx errors that aren't 408 (client-side, retrying won't help)
///
/// Retries:
///   - DioException with no response (connection drops, TLS hiccups, DNS)
///   - 5xx server errors
///   - 408 Request Timeout
///   - Connection / receive timeouts
///
/// If the upstream supplies a `Retry-After` header (in seconds), the next
/// retry waits *that long* (capped at 30s) instead of exponential backoff.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  /// `maxRetries: 1` means: original attempt + 1 retry = 2 total attempts.
  /// Bumped down from 3 (= 4 total attempts) on 2026-04-27 because retry
  /// amplification was contributing to APIM rate-limit pressure during
  /// transient network blips.
  RetryInterceptor({required this.dio, this.maxRetries = 1});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;

    // NEVER retry rate-limit responses. The client must respect Retry-After
    // and propagate the 429 to the caller so UX can show a cooldown.
    if (statusCode == 429) {
      handler.next(err);
      return;
    }

    final isRetryable = statusCode == null ||
        statusCode == 408 ||
        statusCode >= 500 ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError;

    if (!isRetryable) {
      handler.next(err);
      return;
    }

    final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;
    if (retryCount >= maxRetries) {
      handler.next(err);
      return;
    }

    // Honor Retry-After if the upstream supplied one (seconds, integer).
    // Caps at 30s — no point waiting longer than the user's patience.
    final retryAfterDelay = _parseRetryAfter(err.response?.headers);
    final delay = retryAfterDelay ??
        Duration(milliseconds: pow(2, retryCount).toInt() * 500);

    await Future.delayed(delay);

    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Reads the `Retry-After` header (RFC 7231 §7.1.3) as seconds. Returns
  /// null if absent, malformed, or > 30s. We don't honor HTTP-date format
  /// here — APIM and Azure services emit seconds.
  Duration? _parseRetryAfter(Headers? headers) {
    if (headers == null) return null;
    final raw = headers.value('retry-after');
    if (raw == null) return null;
    final n = int.tryParse(raw.trim());
    if (n == null || n <= 0) return null;
    return Duration(seconds: n.clamp(1, 30));
  }
}
