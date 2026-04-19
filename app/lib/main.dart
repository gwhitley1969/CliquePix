import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/constants/msal_constants.dart';
import 'features/auth/domain/app_lifecycle_service.dart'
    show pendingRefreshFlagKey;
import 'features/auth/domain/background_token_service.dart';
import 'services/push_notification_service.dart';
import 'services/token_storage_service.dart';
import 'app/app.dart';

/// Top-level plugin instance — shared with PushNotificationService.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Notification details for FCM foreground display.
const _fcmNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'cliquepix_default',
    'Clique Pix',
    channelDescription: 'Photo sharing notifications',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  ),
  iOS: DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  ),
);

/// Top-level background message handler (must be top-level for Dart isolate).
///
/// Layer 2: handles `type: 'token_refresh'` silent pushes by performing
/// `acquireTokenSilent` in this background isolate. If MSAL can't run here
/// (notably iOS plugin-channel limits in a backgrounded isolate), we set a
/// flag that `AppLifecycleService` picks up on next foreground and triggers
/// a Layer-3 foreground refresh immediately.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data['type'] != 'token_refresh') return;

  await _recordIsolateEvent('silent_push_received');

  try {
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
    await _recordIsolateEvent('silent_push_refresh_success');
  } catch (e) {
    // iOS background isolate may not support the msal_auth plugin channel.
    // Fall back: flag the next foreground resume to refresh immediately.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pendingRefreshFlagKey, true);
    await _recordIsolateEvent('silent_push_fallback_flag_set',
        errorCode: _briefError(e));
  }
}

/// Records an event into the pending SharedPreferences queue that the main
/// isolate drains on next foreground. See `TelemetryService.drainPendingIsolateEvents`.
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
    // ignore — best-effort
  }
}

String _briefError(Object e) {
  final s = e.toString();
  final match = RegExp(r'AADSTS\d{5,6}').firstMatch(s);
  if (match != null) return match.group(0)!;
  return s.split('\n').first.substring(0, s.length > 64 ? 64 : s.length);
}

/// Called when an FCM message arrives while the app is in the foreground.
/// Shows a local notification since Android does NOT auto-display foreground FCM messages.
void _handleForegroundFcmMessage(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;

  debugPrint('[CliquePix] FCM foreground message: ${notification.title}');

  flutterLocalNotificationsPlugin.show(
    notification.hashCode,
    notification.title,
    notification.body,
    _fcmNotificationDetails,
    payload: jsonEncode(message.data),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Register background message handler (must be before runApp)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  tz.initializeTimeZones();

  try {
    await Workmanager().initialize(callbackDispatcher);
  } catch (e) {
    debugPrint('WorkManager init failed: $e');
  }

  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);
    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          PushNotificationService.onNotificationTap?.call(response.payload!);
        }
      },
    );

    // Create the FCM notification channel (referenced in AndroidManifest)
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'cliquepix_default',
          'Clique Pix',
          description: 'Photo sharing notifications',
          importance: Importance.high,
        ),
      );
      debugPrint('[CliquePix] Notification channel created');

      // Request Android 13+ notification permission explicitly
      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('[CliquePix] Notification permission granted: $granted');
    }
  } catch (e) {
    debugPrint('Notifications init failed: $e');
  }

  // Listen for foreground FCM messages — set up HERE, right after plugin init,
  // so the plugin is guaranteed to be ready when show() is called.
  FirebaseMessaging.onMessage.listen(_handleForegroundFcmMessage);
  debugPrint('[CliquePix] FCM onMessage listener registered');

  runApp(
    const ProviderScope(
      child: CliquePix(),
    ),
  );
}
