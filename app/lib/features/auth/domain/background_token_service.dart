import 'package:flutter/widgets.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/msal_constants.dart';
import '../../../services/token_storage_service.dart';

/// Layer 4: WorkManager Background Task (Android best-effort backup).
///
/// Fires roughly every 8 hours with a network constraint. Less reliable than
/// either the foreground-resume path (Layer 3) or the server-triggered silent
/// push (Layer 2, new), but an additional safety net for the case where the
/// app is backgrounded, silent push is throttled, and the user hasn't opened
/// the app. iOS's BGAppRefreshTask backing is best-effort; Apple decides when
/// to actually run the task.
const backgroundTokenRefreshTask = 'com.cliquepix.tokenRefresh';

/// WorkManager callback. Runs in a separate Dart isolate, so everything
/// (Flutter bindings, MSAL, shared prefs, secure storage) must be reinitialized.
/// MSAL's underlying cache is process-wide (Android EncryptedSharedPreferences,
/// iOS Keychain) so a fresh `SingleAccountPca` in this isolate picks up the
/// signed-in account from the main-isolate's previous login.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundTokenRefreshTask) return true;

    try {
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('[AUTH-LAYER-4] WorkManager task fired');

      final pca = await SingleAccountPca.create(
        clientId: MsalConstants.clientId,
        androidConfig: AndroidConfig(
          configFilePath: MsalConstants.androidConfigFilePath,
          redirectUri: MsalConstants.androidRedirectUri,
        ),
        appleConfig: AppleConfig(
          authority: MsalConstants.authority,
          authorityType: AuthorityType.b2c,
          broker: Broker.safariBrowser,
        ),
      );

      final result = await pca.acquireTokenSilent(scopes: MsalConstants.scopes);
      await TokenStorageService().saveTokens(
        accessToken: result.accessToken,
        refreshToken: '',
      );
      debugPrint('[AUTH-LAYER-4] WorkManager refresh success');
      // Telemetry is recorded from the main isolate on next foreground; the
      // isolate's Dio + Riverpod aren't available here.
      await _recordIsolateEvent('wm_refresh_success');
      return true;
    } catch (e) {
      debugPrint('[AUTH-LAYER-4] WorkManager refresh failed: $e');
      await _recordIsolateEvent('wm_refresh_failed', errorCode: _briefError(e));
      // Return true so WorkManager doesn't retry aggressively — the next
      // foreground resume will handle Layer 3 / Layer 5 recovery.
      return true;
    }
  });
}

/// Records a layer event into a SharedPreferences ring buffer. The main
/// isolate's `TelemetryService` drains this buffer to App Insights on next
/// foreground. Best-effort: silent on any error.
Future<void> _recordIsolateEvent(String event, {String? errorCode}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('auth_telemetry_pending') ?? const [];
    final entry =
        '${DateTime.now().toIso8601String()}|$event|${errorCode ?? ""}';
    final next = [...existing, entry];
    if (next.length > 50) {
      next.removeRange(0, next.length - 50);
    }
    await prefs.setStringList('auth_telemetry_pending', next);
  } catch (_) {
    // ignore — telemetry is best-effort
  }
}

String _briefError(Object e) {
  final s = e.toString();
  final match = RegExp(r'AADSTS\d{5,6}').firstMatch(s);
  if (match != null) return match.group(0)!;
  return s.split('\n').first.substring(0, s.length > 64 ? 64 : s.length);
}

class BackgroundTokenService {
  Future<void> register() async {
    await Workmanager().registerPeriodicTask(
      backgroundTokenRefreshTask,
      backgroundTokenRefreshTask,
      frequency: const Duration(hours: AppConstants.workManagerIntervalHours),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    debugPrint(
        '[AUTH-LAYER-4] WorkManager periodic task registered (${AppConstants.workManagerIntervalHours}h)');
  }

  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(backgroundTokenRefreshTask);
    debugPrint('[AUTH-LAYER-4] WorkManager periodic task cancelled');
  }
}
