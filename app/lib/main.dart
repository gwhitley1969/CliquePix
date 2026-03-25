import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/auth/domain/background_token_service.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase (FCM push transport)
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Initialize timezone for scheduled notifications
  tz.initializeTimeZones();

  try {
    // Initialize WorkManager for background token refresh (Layer 4)
    await Workmanager().initialize(callbackDispatcher);
  } catch (e) {
    debugPrint('WorkManager init failed: $e');
  }

  try {
    // Initialize local notifications for AlarmManager (Layer 2)
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);
    await notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'TOKEN_REFRESH_TRIGGER') return;
      },
    );
  } catch (e) {
    debugPrint('Notifications init failed: $e');
  }

  runApp(
    const ProviderScope(
      child: CliquePix(),
    ),
  );
}
