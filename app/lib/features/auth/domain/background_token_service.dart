import 'package:workmanager/workmanager.dart';
import '../../../core/constants/app_constants.dart';

/// Layer 4: WorkManager Background Task (backup mechanism)
/// Fires every 8 hours with network connectivity constraint.
/// Less reliable than AlarmManager but provides another safety net.
const backgroundTokenRefreshTask = 'com.cliquepix.tokenRefresh';

/// Called by Workmanager from a background isolate.
/// Must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundTokenRefreshTask) {
      try {
        // TODO: Perform token refresh via MSAL in background isolate
        // Note: This runs in an isolate, so we need to re-initialize
        // secure storage and MSAL here.
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  });
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
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(backgroundTokenRefreshTask);
  }
}
