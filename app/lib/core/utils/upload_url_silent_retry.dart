import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the per-device 429-silenced cooldown timestamp.
/// Used to prevent an infinite-retry loop if a buggy state somehow resets
/// per-call flags.
const _silenceFlagKey = 'upload_url_429_last_silenced_at_ms';

/// 5-minute per-device cooldown between silent retries.
const _silenceCooldownMs = 5 * 60 * 1000;

/// Hard ceiling on how long we'll silently wait before retrying.
/// APIM rate-limit windows are typically 60s — anything longer than that
/// would feel frozen to the user (the screen still shows
/// "Getting upload URL..." with a spinner during the wait).
const _maxSilentWaitSeconds = 60;

/// Wraps a Future-returning function with a one-shot silent retry on a
/// single 429 from APIM. The user never sees a "Tap to Retry" banner; they
/// just see the existing "Getting upload URL..." progress phase last a few
/// seconds longer before the upload proceeds normally.
///
/// On a SECOND 429 (or any other error), rethrows so the caller's existing
/// error UI takes over. This is intentional — repeated 429s from the same
/// device are a real problem worth surfacing.
///
/// The per-device 5-minute cooldown via SharedPreferences caps how often we
/// silence a 429 globally, so a buggy state can't spin retries forever.
///
/// Telemetry hooks are passed in as callbacks so this helper stays
/// decoupled from TelemetryService and Riverpod context. Pass null to skip.
Future<T> silentRetryOn429<T>(
  Future<T> Function() call, {
  void Function(int retryAfterSeconds)? onSilenced,
  void Function()? onSilentRetrySucceeded,
  void Function(int? finalStatus)? onSilentRetryFailed,
}) async {
  try {
    return await call();
  } on DioException catch (e) {
    if (e.response?.statusCode != 429) rethrow;

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_silenceFlagKey) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - lastMs < _silenceCooldownMs) {
      debugPrint('[silentRetryOn429] cooldown active; skipping silent retry');
      rethrow;
    }
    await prefs.setInt(_silenceFlagKey, nowMs);

    final waitSec = _parseRetryAfter(e).clamp(1, _maxSilentWaitSeconds);
    debugPrint('[silentRetryOn429] caught 429; waiting ${waitSec}s then retrying once');
    onSilenced?.call(waitSec);

    await Future<void>.delayed(Duration(seconds: waitSec));

    try {
      final result = await call();
      debugPrint('[silentRetryOn429] silent retry succeeded');
      onSilentRetrySucceeded?.call();
      return result;
    } on DioException catch (e2) {
      final status = e2.response?.statusCode;
      debugPrint('[silentRetryOn429] silent retry failed; status=$status');
      onSilentRetryFailed?.call(status);
      rethrow;
    }
  }
}

/// Pull the Retry-After hint from a 429 response. APIM emits both an
/// HTTP `Retry-After` header (seconds) and a body like
/// `{"statusCode":429,"message":"Rate limit is exceeded. Try again in 37 seconds."}`.
/// Trust the header first, fall back to body parsing, default 60s.
int _parseRetryAfter(DioException e) {
  final headers = e.response?.headers;
  final headerVal = headers?.value('retry-after');
  if (headerVal != null) {
    final n = int.tryParse(headerVal.trim());
    if (n != null && n > 0) return n;
  }
  final body = e.response?.data;
  if (body is Map) {
    final msg = body['message']?.toString() ?? '';
    final m = RegExp(r'(\d+)\s*second').firstMatch(msg);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null && n > 0) return n;
    }
  }
  return 60;
}
