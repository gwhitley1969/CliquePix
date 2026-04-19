import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'token_storage_service.dart';

/// Thin Dio wrapper for POST /api/telemetry/auth. Fire-and-forget — never
/// blocks the auth flow. Also persists a ring buffer of the last 50 events
/// to SharedPreferences so the hidden Token Diagnostics screen can render
/// them, and drains any events the WorkManager isolate (Layer 4) or the
/// FCM background isolate (Layer 2) queued while the app was backgrounded.
class TelemetryService {
  TelemetryService({required this.dio, required this.tokenStorage});

  final Dio dio;
  final TokenStorageService tokenStorage;

  static const _bufferKey = 'auth_telemetry_ring_buffer';
  static const _pendingKey = 'auth_telemetry_pending'; // written by isolates

  /// Fire-and-forget. Safe to call from any isolate; silently swallows all
  /// errors since telemetry must never affect user-facing behavior.
  void record(String event,
      {String? errorCode, Map<String, String>? extra}) {
    unawaited(_recordImpl(event, errorCode: errorCode, extra: extra));
  }

  Future<void> _recordImpl(
    String event, {
    String? errorCode,
    Map<String, String>? extra,
  }) async {
    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');

    debugPrint('[AUTH-TELEMETRY] $event errorCode=$errorCode');
    await _appendToBuffer(event, errorCode: errorCode);

    try {
      final token = await tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) return;
      await dio.post(
        '/api/telemetry/auth',
        data: {
          'event': event,
          if (errorCode != null) 'errorCode': errorCode,
          'platform': platform,
          if (extra != null && extra.isNotEmpty) 'extra': extra,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // Best-effort — never re-throw from telemetry.
    }
  }

  Future<void> _appendToBuffer(String event, {String? errorCode}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_bufferKey) ?? const [];
      final entry = jsonEncode({
        't': DateTime.now().toIso8601String(),
        'e': event,
        if (errorCode != null) 'c': errorCode,
      });
      final next = [...existing, entry];
      if (next.length > 50) {
        next.removeRange(0, next.length - 50);
      }
      await prefs.setStringList(_bufferKey, next);
    } catch (_) {
      // ignore
    }
  }

  /// Drain events recorded by isolates (WorkManager / FCM background handler)
  /// and forward to App Insights via the HTTP endpoint. Call on app resume.
  Future<void> drainPendingIsolateEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingKey) ?? const [];
      if (pending.isEmpty) return;
      await prefs.remove(_pendingKey);

      for (final entry in pending) {
        // entry format: "ISO8601|event|errorCode"
        final parts = entry.split('|');
        if (parts.length < 2) continue;
        final event = parts[1];
        final code = parts.length >= 3 && parts[2].isNotEmpty ? parts[2] : null;
        record(event, errorCode: code);
      }
    } catch (_) {
      // ignore — will retry next resume
    }
  }

  /// Read the in-memory/persistent buffer for the Token Diagnostics screen.
  Future<List<Map<String, dynamic>>> readBuffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_bufferKey) ?? const [];
      return entries
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearBuffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bufferKey);
      await prefs.remove(_pendingKey);
    } catch (_) {}
  }
}

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService(
    dio: ref.watch(apiClientProvider).dio,
    tokenStorage: ref.watch(tokenStorageServiceProvider),
  );
});
