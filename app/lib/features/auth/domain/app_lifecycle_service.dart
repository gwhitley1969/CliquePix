import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/token_storage_service.dart';

/// Pending-refresh flag written by the FCM background isolate (Layer 2)
/// when an in-isolate MSAL silent refresh fails or isn't viable (e.g., iOS
/// background isolate plugin-channel limits). Consumed here so that the
/// refresh happens immediately on next foreground regardless of token age.
const pendingRefreshFlagKey = 'pending_refresh_on_next_resume';

/// Telemetry hook — a callback the wiring layer installs so this service
/// can log layer activity without importing Riverpod / Dio directly.
typedef AuthLayerTelemetry = void Function(String event,
    {String? errorCode, Map<String, String>? extra});

/// Layer 3: Foreground Refresh on App Resume (most reliable on both platforms).
///
/// Checks token age on every app resume. If > 6h stale, proactively refreshes.
/// Also handles the "silent push arrived but background isolate couldn't run
/// MSAL" fallback from Layer 2 by honoring the pendingRefreshFlagKey flag.
class AppLifecycleService with WidgetsBindingObserver {
  final TokenStorageService _tokenStorage;
  final Future<bool> Function() _refreshCallback;
  final Future<void> Function() _reloginCallback;
  final Future<void> Function()? _onRefreshSuccess;
  final Future<void> Function()? _onResumed;
  final AuthLayerTelemetry? _telemetry;

  bool _isRefreshing = false;

  AppLifecycleService({
    required TokenStorageService tokenStorage,
    required Future<bool> Function() refreshCallback,
    required Future<void> Function() reloginCallback,
    Future<void> Function()? onRefreshSuccess,
    Future<void> Function()? onResumed,
    AuthLayerTelemetry? telemetry,
  })  : _tokenStorage = tokenStorage,
        _refreshCallback = refreshCallback,
        _reloginCallback = reloginCallback,
        _onRefreshSuccess = onRefreshSuccess,
        _onResumed = onResumed,
        _telemetry = telemetry;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[AUTH-LAYER-3] lifecycle observer started');
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Auth-independent resume hook (e.g. FridayReminderService TZ-change
      // recovery). Runs concurrently with the token-refresh path; failures
      // are swallowed by the callback's own try/catch so they cannot break
      // auth recovery.
      final cb = _onResumed;
      if (cb != null) {
        cb().catchError((Object e) {
          debugPrint('[AppLifecycleService] onResumed callback failed: $e');
        });
      }
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingFlag = prefs.getBool(pendingRefreshFlagKey) ?? false;
      final isStale = await _tokenStorage.isTokenStale();

      _telemetry?.call('foreground_stale_check', extra: {
        'stale': isStale.toString(),
        'pending_flag': pendingFlag.toString(),
      });

      if (!pendingFlag && !isStale) return;

      // Clear the pending flag BEFORE the refresh await. If the refresh
      // hangs, the flag is already gone — a subsequent resume will not
      // re-trigger the same hang, which was the "force-quit doesn't fix it"
      // feedback loop users reported.
      if (pendingFlag) {
        await prefs.remove(pendingRefreshFlagKey);
      }

      debugPrint(
          '[AUTH-LAYER-3] triggering refresh (stale=$isStale pendingFlag=$pendingFlag)');
      final success = await _refreshCallback()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);

      if (success) {
        _telemetry?.call('foreground_refresh_success');
        final cb = _onRefreshSuccess;
        if (cb != null) {
          await cb();
        }
      } else {
        _telemetry?.call('foreground_refresh_failed');
        // Layer 5 — graceful re-login
        await _reloginCallback();
      }
    } catch (e) {
      debugPrint('[AUTH-LAYER-3] _onAppResumed exception: $e');
      // Silently fail — next resume will try again.
    } finally {
      _isRefreshing = false;
    }
  }
}
