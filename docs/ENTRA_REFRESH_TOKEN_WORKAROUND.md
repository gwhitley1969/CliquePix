# Microsoft Entra External ID Refresh Token Workaround

**Last Updated:** January 2026
**Status:** Enhanced with 5-Layer Defense System + Token Refresh Notification Fix
**Issue Type:** Known Microsoft Bug - No Official Fix Available

## Problem Summary

My AI Bartender uses Microsoft Entra External ID (CIAM) for user authentication with Google, Facebook, and email sign-in options. Users were being forced to re-authenticate after approximately 12 hours of app inactivity, which is a poor user experience for a consumer mobile app.

## Root Cause Analysis

### The Error

When the app attempted to silently refresh tokens after 12 hours of inactivity, it received:

```
AADSTS700082: The refresh token has expired due to inactivity.
The token was issued on 2025-12-08T21:19:36.7279000Z and was
inactive for 12:00:00.
```

### Investigation Timeline

1. **Initial Report:** Users reported needing to re-login every ~24 hours
2. **Diagnostic Build:** Created APK with detailed `[AUTH-DIAG]` logging
3. **Root Cause Captured:** Test device captured the actual `AADSTS700082` error with "inactive for 12:00:00"
4. **Research:** Confirmed this is a known Microsoft bug with no portal-based fix
5. **Second Report (Dec 2025):** WorkManager background tasks not running reliably on Samsung/Xiaomi devices
6. **Enhanced Solution:** Implemented 5-layer defense with battery optimization and AlarmManager

### Microsoft Bug Details

- **Affected Service:** Microsoft Entra External ID (CIAM) tenants only
- **Standard Behavior:** Regular Entra ID tenants have 90-day refresh token lifetime
- **Bug Behavior:** Entra External ID tenants have a hardcoded 12-hour inactivity timeout
- **Configuration Options:** None available - the token lifetime settings visible in standard Entra ID are not available in Entra External ID tenants
- **Microsoft Status:** Acknowledged as a bug, no timeline for fix provided

### Why WorkManager Alone Failed

The initial WorkManager-based solution (every 8 hours) was NOT running reliably:

| Issue | Impact |
|-------|--------|
| **Android Doze Mode** | Delays WorkManager tasks for hours |
| **App Standby Buckets** (Android 9+) | Infrequently used apps get restricted |
| **OEM Battery Optimization** | Samsung/Xiaomi/Huawei aggressively kill background processes |
| **WorkManager is deferrable** | The 8-hour "frequency" is a minimum, not guaranteed |
| **Battery exemption declared but not requested** | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` in manifest was useless without runtime request |

## Solution: 5-Layer Token Refresh Defense

Since the 12-hour inactivity timeout cannot be configured, we implemented a multi-layer defense strategy that prevents the refresh token from ever becoming "inactive."

### Layer Architecture

| Layer | Mechanism | Interval/Trigger | Reliability | Purpose |
|-------|-----------|------------------|-------------|---------|
| **1** | Battery Optimization Exemption | On first login | **Critical** | Allows background tasks to run on Samsung/Xiaomi/Huawei |
| **2** | AlarmManager Token Refresh | Every 6 hours | **Very High** | Fires even in Doze mode (`exactAllowWhileIdle`) |
| **3** | Foreground Refresh on App Resume | Every app open | **Very High** | Catches all background failures |
| **4** | WorkManager Background Task | Every 8 hours | Medium | Additional backup |
| **5** | Graceful Re-Login UX | When all else fails | N/A | One-tap "Welcome Back" dialog |

### Layer 1: Battery Optimization Exemption (CRITICAL)

**File:** `mobile/app/lib/src/services/battery_optimization_service.dart` (NEW)

**Why This Matters:**
The `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission was declared in AndroidManifest but **never requested at runtime**. This was the primary reason background tasks didn't run on Samsung/Xiaomi devices.

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationService {
  static final BatteryOptimizationService _instance = BatteryOptimizationService._internal();
  factory BatteryOptimizationService() => _instance;
  BatteryOptimizationService._internal();

  static BatteryOptimizationService get instance => _instance;

  static const String _hasShownDialogKey = 'battery_optimization_dialog_shown';

  /// Check if battery optimization is already disabled for this app
  Future<bool> isOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  /// Request battery optimization exemption
  Future<bool> requestOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// Show the exemption dialog if not already shown and request permission
  Future<bool> showExemptionDialogIfNeeded(BuildContext context) async {
    if (!Platform.isAndroid) return true;
    if (await isOptimizationDisabled()) return true;

    // Check if we've already shown the dialog
    final prefs = await SharedPreferences.getInstance();
    final hasShown = prefs.getBool(_hasShownDialogKey) ?? false;
    if (hasShown) return false;

    // Mark as shown
    await prefs.setBool(_hasShownDialogKey, true);

    // Show dialog
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Stay Signed In'),
        content: const Text(
          'To keep you signed in automatically, My AI Bartender needs '
          'permission to run in the background.\n\n'
          'This uses minimal battery and only runs when needed to keep '
          'your session active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      return await requestOptimizationExemption();
    }
    return false;
  }
}
```

**Integration in Home Screen:**

```dart
// In home_screen.dart - show dialog after first login
class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hasCheckedBatteryOptimization = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBatteryOptimization();
    });
  }

  Future<void> _checkBatteryOptimization() async {
    if (_hasCheckedBatteryOptimization) return;
    _hasCheckedBatteryOptimization = true;

    final isAuthenticated = ref.read(isAuthenticatedProvider);
    if (!isAuthenticated) return;

    if (mounted) {
      await BatteryOptimizationService.instance.showExemptionDialogIfNeeded(context);
    }
  }
}
```

### Layer 2: AlarmManager Token Refresh (HIGH RELIABILITY)

**File:** `mobile/app/lib/src/services/notification_service.dart` (EXTENDED)

**Why AlarmManager?**
AlarmManager with `setExactAndAllowWhileIdle` can fire during Doze mode, unlike WorkManager which is deferrable.

**Bug Fix (January 2026):** The "silent" token refresh notification was visible on some Android versions/OEMs (showing as "My AI Bartender" in the notification shade). When tapped, the `TOKEN_REFRESH_TRIGGER` payload was being treated as a cocktail ID, navigating to "Cocktail not found". Fixed by:
1. Adding `silent: true` and `Priority.min` to notification settings
2. Filtering `TOKEN_REFRESH_TRIGGER` payload in `main.dart` before navigation

```dart
// New constants in NotificationService
static const int _tokenRefreshNotificationId = 9000;
static const String _tokenRefreshChannelId = 'token_refresh_background';
static const String _tokenRefreshPayload = 'TOKEN_REFRESH_TRIGGER';

/// Callback when token refresh alarm fires
Future<void> Function()? onTokenRefreshNeeded;

/// Handle notification response - check for token refresh trigger
void _onNotificationTap(NotificationResponse response) {
  if (response.payload == _tokenRefreshPayload) {
    developer.log('[ALARM-REFRESH] Token refresh alarm triggered', name: 'NotificationService');
    if (onTokenRefreshNeeded != null) {
      onTokenRefreshNeeded!().then((_) {
        // Reschedule for next interval after successful refresh
        scheduleTokenRefreshAlarm();
      });
    }
    return;
  }
  // Handle other notifications...
  onNotificationTap?.call(response.payload);
}

/// Schedule a silent alarm to refresh token
/// Uses exactAllowWhileIdle to fire even in Doze mode
Future<void> scheduleTokenRefreshAlarm({Duration delay = const Duration(hours: 6)}) async {
  await initialize();

  // Cancel any existing alarm
  await _plugin.cancel(_tokenRefreshNotificationId);

  final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);

  developer.log(
    '[ALARM-REFRESH] Scheduling token refresh for: ${scheduledTime.toIso8601String()}',
    name: 'NotificationService',
  );

  // Use truly silent notification that won't disturb the user
  // Note: Even with these settings, some Android versions may show a notification
  // The main.dart filter handles this by ignoring TOKEN_REFRESH_TRIGGER payloads
  final androidDetails = AndroidNotificationDetails(
    _tokenRefreshChannelId,
    'Background Sync',
    channelDescription: 'Keeps you signed in automatically',
    importance: Importance.min,
    priority: Priority.min, // Lowest priority
    playSound: false,
    enableVibration: false,
    showWhen: false,
    visibility: NotificationVisibility.secret,
    silent: true, // Make notification completely silent
  );

  await _plugin.zonedSchedule(
    _tokenRefreshNotificationId,
    '', // Empty title - silent notification
    '', // Empty body - silent notification
    scheduledTime,
    NotificationDetails(android: androidDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: _tokenRefreshPayload,
  );

  developer.log('[ALARM-REFRESH] Token refresh alarm scheduled successfully', name: 'NotificationService');
}

/// Cancel the token refresh alarm (on logout)
Future<void> cancelTokenRefreshAlarm() async {
  await _plugin.cancel(_tokenRefreshNotificationId);
  developer.log('[ALARM-REFRESH] Token refresh alarm cancelled', name: 'NotificationService');
}
```

### Layer 3: Foreground Token Refresh (SAFETY NET)

**File:** `mobile/app/lib/src/services/app_lifecycle_service.dart`

This is the **critical safety net**. When the user opens the app:
1. AppLifecycleService observes `AppLifecycleState.resumed`
2. Checks how old the current token is (via `lastRefreshTime` in storage)
3. If token is > 6 hours old, proactively refreshes before it expires
4. If refresh fails, triggers graceful re-login flow
5. **NEW:** Reschedules AlarmManager after successful refresh

**Why 6 hours?**
- Microsoft's inactivity timeout: 12 hours
- Proactive refresh threshold: 6 hours old
- Safety margin: 6 hours
- This catches ALL failures of background tasks

```dart
Future<void> _performProactiveRefresh() async {
  _isRefreshing = true;
  _log('Starting proactive token refresh...');

  try {
    final user = await _authService!.refreshToken();

    if (user != null) {
      _log('SUCCESS! Token refreshed proactively');
      _log('User: ${user.email}');

      // Reschedule the AlarmManager token refresh for the next interval
      try {
        await NotificationService.instance.scheduleTokenRefreshAlarm();
        _log('AlarmManager token refresh rescheduled (next in 6 hours)');
      } catch (e) {
        _log('Failed to reschedule AlarmManager token refresh: $e');
      }

      _log('=== APP RESUMED CHECK COMPLETE - Token Refreshed ===');
    } else {
      _log('!!! REFRESH FAILED - Token could not be refreshed');
      _log('This likely means the refresh token has expired (12-hour timeout)');
      _log('User will need to re-authenticate');
      _log('=== APP RESUMED CHECK COMPLETE - RE-LOGIN REQUIRED ===');

      // Notify that re-login is required
      if (onReloginRequired != null) {
        _log('Triggering re-login callback');
        onReloginRequired!();
      }
    }
  } catch (e, stackTrace) {
    _log('!!! REFRESH EXCEPTION: $e', error: e);

    // On error, also trigger re-login
    if (onReloginRequired != null) {
      _log('Triggering re-login callback due to error');
      onReloginRequired!();
    }
  } finally {
    _isRefreshing = false;
  }
}
```

### Layer 4: WorkManager Background Task (BACKUP)

**File:** `mobile/app/lib/src/services/background_token_service.dart`

This is now a BACKUP mechanism. Android OEMs may delay or kill these tasks, but with battery optimization exempted (Layer 1), reliability improves.

```dart
/// Schedule periodic refresh every 8 hours (backup to AlarmManager and foreground refresh)
Future<void> scheduleTokenRefresh() async {
  await Workmanager().registerPeriodicTask(
    tokenRefreshTaskUniqueName,
    tokenRefreshTaskName,
    frequency: const Duration(hours: 8),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}
```

### Layer 5: Graceful Re-Login UX (FALLBACK)

**File:** `mobile/app/lib/src/widgets/welcome_back_dialog.dart` (NEW)

When all background mechanisms fail, make re-authentication seamless with a friendly "Welcome back" dialog.

```dart
class WelcomeBackDialog extends StatelessWidget {
  final User? lastKnownUser;
  final VoidCallback onContinue;
  final VoidCallback? onSwitchAccount;

  const WelcomeBackDialog({
    super.key,
    this.lastKnownUser,
    required this.onContinue,
    this.onSwitchAccount,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = _buildGreeting();
    final initial = lastKnownUser?.displayName?.substring(0, 1).toUpperCase() ??
        lastKnownUser?.givenName?.substring(0, 1).toUpperCase() ??
        'M';

    return Dialog(
      // Shows user avatar with initial
      // "Welcome back, [Name]!" greeting
      // User's email as hint
      // Continue button (prominent)
      // "Use a different account" link (subtle)
    );
  }

  String _buildGreeting() {
    final name = lastKnownUser?.givenName ?? lastKnownUser?.displayName;
    if (name != null && name.isNotEmpty) {
      return 'Welcome back, $name!';
    }
    return 'Welcome back!';
  }
}
```

**Quick Re-Login in AuthService:**

```dart
/// Perform quick re-login with stored user's email as hint.
/// This provides a smoother re-authentication experience when the
/// refresh token has expired. The user's email is pre-filled.
Future<User?> quickRelogin() async {
  _diagLog('[QUICK-RELOGIN] Starting quick re-login...');

  final storedUser = await _tokenStorage.getUserProfile();
  final loginHint = storedUser?.email;

  _diagLog('[QUICK-RELOGIN] Login hint: $loginHint');

  // Try silent first (may work if session valid server-side)
  try {
    _diagLog('[QUICK-RELOGIN] Attempting silent token acquisition first...');
    final result = await _msalAuth!.acquireTokenSilent(scopes: scopes);
    if (result != null) {
      _diagLog('[QUICK-RELOGIN] Silent acquisition succeeded!');
      return await _handleAuthResult(result);
    }
  } catch (e) {
    _diagLog('[QUICK-RELOGIN] Silent acquisition failed (expected): $e');
  }

  // Interactive with loginHint for smoother UX
  _diagLog('[QUICK-RELOGIN] Falling back to interactive login with hint...');
  final result = await _msalAuth!.acquireToken(
    scopes: scopes,
    loginHint: loginHint,
    prompt: Prompt.selectAccount,
  );

  if (result != null) {
    _diagLog('[QUICK-RELOGIN] Interactive login succeeded');
    return await _handleAuthResult(result);
  }

  _diagLog('[QUICK-RELOGIN] Login cancelled or failed');
  return null;
}
```

**AuthProvider Integration:**

```dart
class AuthNotifier extends StateNotifier<AuthState> {
  /// Last known user info (stored when re-login is required)
  /// Used to show "Welcome back, [Name]!" in the re-login dialog
  User? _lastKnownUser;
  User? get lastKnownUser => _lastKnownUser;

  /// Handle when token refresh fails and re-login is required
  void _handleReloginRequired() {
    developer.log('Re-login required - token refresh failed', name: 'AuthNotifier');

    // Store the current user info before clearing state
    final currentState = state;
    if (currentState is AuthStateAuthenticated) {
      _lastKnownUser = currentState.user;
      developer.log('Stored last known user: ${_lastKnownUser?.email}', name: 'AuthNotifier');
    }

    state = const AuthState.unauthenticated();
  }

  /// Perform quick re-login with stored user's email as hint.
  Future<void> quickRelogin() async {
    developer.log('Starting quick re-login...', name: 'AuthNotifier');
    state = const AuthState.loading();

    try {
      final user = await _authService.quickRelogin();

      if (user != null) {
        developer.log('Quick re-login successful: ${user.email}', name: 'AuthNotifier');
        await _initializeSubscription(user.id);
        state = AuthState.authenticated(user);
        _lastKnownUser = null; // Clear since we're now logged in
      } else {
        developer.log('Quick re-login cancelled or failed', name: 'AuthNotifier');
        state = const AuthState.unauthenticated();
      }
    } catch (e) {
      developer.log('Quick re-login error', name: 'AuthNotifier', error: e);
      state = AuthState.error(e.toString());
    }
  }
}
```

## Implementation Details

### Files Modified/Created

| File | Purpose | Status |
|------|---------|--------|
| `mobile/app/lib/src/services/battery_optimization_service.dart` | **New** - Request battery optimization exemption | NEW |
| `mobile/app/lib/src/widgets/welcome_back_dialog.dart` | **New** - Graceful re-login UI | NEW |
| `mobile/app/lib/src/services/notification_service.dart` | Added AlarmManager-based token refresh, silent notification fix | MODIFIED |
| `mobile/app/lib/src/services/auth_service.dart` | Added quickRelogin(), alarm scheduling | MODIFIED |
| `mobile/app/lib/src/services/app_lifecycle_service.dart` | Reschedule alarm after refresh | MODIFIED |
| `mobile/app/lib/src/providers/auth_provider.dart` | lastKnownUser, quickRelogin() method | MODIFIED |
| `mobile/app/lib/src/features/home/home_screen.dart` | Trigger battery dialog on first login | MODIFIED |
| `mobile/app/lib/src/widgets/widgets.dart` | Export welcome_back_dialog | MODIFIED |
| `mobile/app/lib/main.dart` | Filter TOKEN_REFRESH_TRIGGER from notification navigation | MODIFIED |
| `mobile/app/lib/src/services/background_token_service.dart` | WorkManager background refresh (backup) | UNCHANGED |
| `mobile/app/lib/src/services/token_storage_service.dart` | lastRefreshTime tracking | UNCHANGED |
| `mobile/app/android/app/src/main/AndroidManifest.xml` | Required Android permissions | UNCHANGED |
| `mobile/app/pubspec.yaml` | Dependencies | UNCHANGED |

### Android Permissions Required

```xml
<!-- WorkManager permissions for background token refresh -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

<!-- Exact alarms for AlarmManager token refresh -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

### Lifecycle Integration

**On User Login (in `auth_service.dart`):**

```dart
// After successful authentication in _handleAuthResult()
NotificationService.instance.onTokenRefreshNeeded = () async {
  _diagLog('[ALARM-REFRESH] AlarmManager token refresh triggered');
  await refreshToken();
};
await NotificationService.instance.scheduleTokenRefreshAlarm();
await BackgroundTokenService.instance.scheduleTokenRefresh();
```

**On User Logout (in `auth_service.dart`):**

```dart
// Cancel all background refresh mechanisms
await NotificationService.instance.cancelTokenRefreshAlarm();
NotificationService.instance.onTokenRefreshNeeded = null;
await BackgroundTokenService.instance.cancelTokenRefresh();
```

**On App Startup (in `bootstrap.dart`):**

```dart
// Initialize WorkManager
await BackgroundTokenService.instance.initialize();
```

**On App Resume (in `app_lifecycle_service.dart`):**

```dart
// Check if token is stale and refresh if needed
// Reschedule AlarmManager after successful refresh
```

**On Home Screen Load (in `home_screen.dart`):**

```dart
// Show battery optimization dialog if needed (first time only)
await BatteryOptimizationService.instance.showExemptionDialogIfNeeded(context);
```

## Testing

### Test Setup

1. Built debug APK with all layers enabled
2. Installed on Samsung test device (known for aggressive battery optimization)
3. Signed in with test account
4. Granted battery optimization exemption when prompted
5. Left device idle for 12+ hours

### Expected Behavior

1. **Battery dialog appears** after first login
2. **AlarmManager fires** every 6 hours (visible in logs)
3. **Foreground refresh** catches any missed background refreshes
4. **If all fails**, user sees "Welcome back, [Name]!" dialog instead of full login screen

### Before vs After (Enhanced)

| Scenario | Original | WorkManager Only | 5-Layer Defense |
|----------|----------|------------------|-----------------|
| App idle for 12+ hours | Forced re-login | Often forced re-login | Session persists |
| Samsung/Xiaomi devices | Forced re-login | Usually forced re-login | Session persists |
| Background refresh runs | N/A | Unreliable | Very reliable |
| Re-login experience | Full login screen | Full login screen | One-tap "Welcome back" |
| User experience | Frustrating | Inconsistent | Seamless |

## Debugging

### Log Tags

| Tag | Source | Purpose |
|-----|--------|---------|
| `[APP-LIFECYCLE]` | AppLifecycleService | Foreground resume and refresh |
| `[ALARM-REFRESH]` | NotificationService | AlarmManager token refresh |
| `[TOKEN-ALARM]` | NotificationService | Token refresh alarm scheduling/firing |
| `[BG-TOKEN]` | BackgroundTokenService | WorkManager background refresh |
| `[QUICK-RELOGIN]` | AuthService | Quick re-login flow |
| `[AUTH-DIAG]` | AuthService | General authentication diagnostics |

### Example Log Sequence (Successful Background Refresh)

```
[ALARM-REFRESH] Token refresh alarm triggered
[ALARM-REFRESH] Calling onTokenRefreshNeeded callback...
[AUTH-DIAG] refreshToken() called
[AUTH-DIAG] Attempting acquireTokenSilent...
[AUTH-DIAG] Silent token acquisition successful
[ALARM-REFRESH] Token refresh completed, rescheduling alarm
[ALARM-REFRESH] Scheduling token refresh for: 2025-12-20T09:30:00.000Z
[ALARM-REFRESH] Token refresh alarm scheduled successfully
```

### Example Log Sequence (Foreground Recovery)

```
[APP-LIFECYCLE] App lifecycle changed: AppLifecycleState.resumed
[APP-LIFECYCLE] === APP RESUMED - Checking token freshness ===
[APP-LIFECYCLE] User authenticated: user@example.com
[APP-LIFECYCLE] Last token refresh: 2025-12-19T21:30:00.000Z
[APP-LIFECYCLE] Token age: 8 hours (480 minutes)
[APP-LIFECYCLE] >>> PROACTIVE REFRESH TRIGGERED: Token is 8 hours old (threshold: 6 hours)
[APP-LIFECYCLE] Starting proactive token refresh...
[APP-LIFECYCLE] SUCCESS! Token refreshed proactively
[APP-LIFECYCLE] AlarmManager token refresh rescheduled (next in 6 hours)
[APP-LIFECYCLE] === APP RESUMED CHECK COMPLETE - Token Refreshed ===
```

## Limitations and Considerations

### Android-Specific

- All layers except graceful re-login are Android-only
- iOS implementation will need different approaches (see iOS Considerations section)
- Even with battery optimization exemption, some extreme OEM devices may still restrict
- AlarmManager with exact alarms may require user permission on Android 12+
- Token refresh notification may still be visible on some Android versions despite `Importance.min` and `silent: true` settings - the `main.dart` filter ensures tapping it doesn't cause navigation errors

### Network Dependency

- All refresh mechanisms require network connectivity
- If no network is available, refresh will fail and retry on next opportunity
- Foreground refresh will catch failures when user opens app

### Not a "True" Fix

- This is a workaround, not a fix for the underlying Microsoft bug
- If Microsoft ever fixes the 12-hour timeout, this code could be simplified
- Monitor Microsoft announcements for any updates to External ID token policies

## iOS Considerations

When porting to iOS, background task execution works differently than Android. See the iOS-specific sections below.

### iOS Background Task APIs

iOS 13+ provides **BGTaskScheduler** with two task types:
1. **BGAppRefreshTask** - Short tasks for refreshing content
2. **BGProcessingTask** - Longer tasks, runs when device is idle/charging

The `workmanager` Flutter package supports iOS via BGTaskScheduler, but iOS has stricter timing control.

### Expected iOS Behavior

| Scenario | Expected Outcome |
|----------|------------------|
| User opens app daily | Background refresh likely runs, no re-login |
| User opens app every few days | May occasionally need to re-login |
| Background App Refresh disabled | Will need to re-login after 12 hours |
| Device in Low Power Mode | Background tasks deprioritized |

### iOS Mitigation Strategies

1. **Foreground refresh** (Layer 3) is the most reliable on iOS
2. Request shorter intervals (6 hours) hoping system runs within 12 hours
3. Consider silent push notifications from server (requires APNs setup)
4. User education about enabling Background App Refresh

## Future Considerations

1. **iOS Implementation:** Test and tune background refresh for iOS
2. **Telemetry:** Add analytics to track refresh success/failure rates per device manufacturer
3. **Silent Push:** Evaluate server-side silent push notifications for additional reliability
4. **User Settings:** Consider adding "Stay signed in" toggle in settings
5. **Microsoft Updates:** Monitor for any fixes to the 12-hour timeout bug

## Related Documentation

- [AUTHENTICATION_SETUP.md](./AUTHENTICATION_SETUP.md) - Entra External ID configuration
- [AUTHENTICATION_IMPLEMENTATION.md](./AUTHENTICATION_IMPLEMENTATION.md) - MSAL Flutter implementation
- [Microsoft Entra External ID Docs](https://learn.microsoft.com/en-us/entra/external-id/)

## Appendix: Full Error Log

Captured from test device showing the exact error before the fix:

```
[AUTH-DIAG] ==================================================
[AUTH-DIAG] MSAL acquireTokenSilent Exception:
[AUTH-DIAG] Type: MsalException
[AUTH-DIAG] Message: AADSTS700082: The refresh token has expired
due to inactivity. The token was issued on
2025-12-08T21:19:36.7279000Z and was inactive for 12:00:00.
[AUTH-DIAG] ==================================================
```
