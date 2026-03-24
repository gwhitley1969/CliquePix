import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Initialize Firebase
  // await Firebase.initializeApp();

  // TODO: Initialize timezone
  // tz.initializeTimeZones();

  // TODO: Initialize WorkManager for background token refresh (Layer 4)
  // await Workmanager().initialize(callbackDispatcher);

  // TODO: Initialize local notifications for AlarmManager (Layer 2)
  // await FlutterLocalNotificationsPlugin().initialize(...);

  runApp(
    const ProviderScope(
      child: CliquePix(),
    ),
  );
}
