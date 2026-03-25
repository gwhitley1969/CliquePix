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

  // Initialize Firebase (FCM push transport)
  await Firebase.initializeApp();

  // Initialize timezone for scheduled notifications
  tz.initializeTimeZones();

  // Initialize WorkManager for background token refresh (Layer 4)
  await Workmanager().initialize(callbackDispatcher);

  // Initialize local notifications for AlarmManager (Layer 2)
  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings =
      InitializationSettings(android: androidInit, iOS: iosInit);
  await notificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      // Filter out TOKEN_REFRESH_TRIGGER payloads to prevent navigation errors
      if (response.payload == 'TOKEN_REFRESH_TRIGGER') return;
    },
  );

  runApp(
    const ProviderScope(
      child: CliquePix(),
    ),
  );
}
