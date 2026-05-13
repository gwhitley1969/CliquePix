import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the Play Install Referrer once per install on Android and persists any
/// `invite_code=...` value into SharedPreferences for the auth-state listener
/// in `app.dart` to consume. iOS is a no-op — no Apple equivalent of the Play
/// Install Referrer API exists; iOS deferred deep linking is handled by the
/// Smart App Banner meta tag in the webapp once the App Store listing is live.
class InstallReferrerService {
  static const _consumedKey = 'install_referrer_consumed';
  static const _pendingInviteCodeKey = 'install_referrer_pending_invite_code';
  static const _pendingTelemetryKey = 'auth_telemetry_pending';

  /// Reads the Play Install Referrer ONCE per install (gated by SharedPreferences
  /// flag). If `invite_code=...` is present in the referrer string, persists the
  /// code under [_pendingInviteCodeKey]. Records `install_referrer_read` to the
  /// pending-isolate telemetry queue. Fire-and-forget — safe to call without
  /// awaiting.
  static Future<void> readAndPersistOnce() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_consumedKey) == true) return;

    String? extractedCode;
    String? errorCode;
    try {
      final details = await PlayInstallReferrer.installReferrer;
      final referrer = details.installReferrer ?? '';
      extractedCode = _extractInviteCode(referrer);
      if (extractedCode != null && extractedCode.isNotEmpty) {
        await prefs.setString(_pendingInviteCodeKey, extractedCode);
      }
    } catch (e) {
      debugPrint('[CliquePix] install referrer read failed: $e');
      errorCode = e.toString().split('\n').first;
      if (errorCode.length > 64) errorCode = errorCode.substring(0, 64);
    }
    await prefs.setBool(_consumedKey, true);

    await _recordTelemetry(
      'install_referrer_read',
      errorCode: errorCode,
      hadInviteCode: extractedCode != null && extractedCode.isNotEmpty,
    );
  }

  static String? _extractInviteCode(String referrer) {
    if (referrer.isEmpty) return null;
    final decoded = Uri.decodeComponent(referrer);
    for (final pair in decoded.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (key == 'invite_code' && value.isNotEmpty) return value;
    }
    return null;
  }

  static Future<String?> readPendingInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingInviteCodeKey);
  }

  static Future<void> clearPendingInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInviteCodeKey);
  }

  /// Writes to the same pending-isolate telemetry queue that the Layer-2 FCM
  /// background handler uses. `TelemetryService.drainPendingIsolateEvents`
  /// will flush these to App Insights on next foreground.
  static Future<void> _recordTelemetry(
    String event, {
    String? errorCode,
    required bool hadInviteCode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingTelemetryKey) ?? const [];
      final marker = hadInviteCode ? 'had_invite_code=true' : 'had_invite_code=false';
      final code = errorCode != null && errorCode.isNotEmpty
          ? '$marker;$errorCode'
          : marker;
      final entry = '${DateTime.now().toIso8601String()}|$event|$code';
      final next = [...existing, entry];
      if (next.length > 50) next.removeRange(0, next.length - 50);
      await prefs.setStringList(_pendingTelemetryKey, next);
    } catch (_) {
      // best-effort; telemetry must never affect user-facing behavior
    }
  }
}
