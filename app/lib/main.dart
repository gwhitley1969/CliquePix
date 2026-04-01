import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/auth/domain/background_token_service.dart';
import 'services/push_notification_service.dart';
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
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
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
        if (response.payload == 'TOKEN_REFRESH_TRIGGER') return;
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
