import 'package:flutter/widgets.dart';
import '../../../services/token_storage_service.dart';

/// Layer 3: Foreground Refresh on App Resume (most reliable on both platforms)
/// Checks token age on every app resume. If > 6 hours, proactively refreshes.
/// This is the primary iOS defense since iOS lacks reliable background tasks.
class AppLifecycleService with WidgetsBindingObserver {
  final TokenStorageService _tokenStorage;
  final Future<bool> Function() _refreshCallback;
  final Future<void> Function() _reloginCallback;
  final Future<void> Function() _rescheduleAlarm;

  bool _isRefreshing = false;

  AppLifecycleService({
    required TokenStorageService tokenStorage,
    required Future<bool> Function() refreshCallback,
    required Future<void> Function() reloginCallback,
    required Future<void> Function() rescheduleAlarm,
  })  : _tokenStorage = tokenStorage,
        _refreshCallback = refreshCallback,
        _reloginCallback = reloginCallback,
        _rescheduleAlarm = rescheduleAlarm;

  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final isStale = await _tokenStorage.isTokenStale();
      if (!isStale) return;

      final success = await _refreshCallback();
      if (success) {
        await _rescheduleAlarm();
      } else {
        // Layer 5: Trigger graceful re-login
        await _reloginCallback();
      }
    } catch (_) {
      // Silently fail — next resume will try again
    } finally {
      _isRefreshing = false;
    }
  }
}
