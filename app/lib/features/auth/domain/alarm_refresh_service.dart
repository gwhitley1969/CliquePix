import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/constants/app_constants.dart';

/// Layer 2: AlarmManager Token Refresh (Android primary, iOS BGTaskScheduler)
/// Fires every 6 hours to refresh the token before the 12-hour Entra timeout.
/// Uses exactAllowWhileIdle to fire even in Doze mode.
class AlarmRefreshService {
  static const _notificationId = 9999;
  static const _channelId = AppConstants.tokenRefreshChannel;
  static const _channelName = 'Token Refresh';

  final FlutterLocalNotificationsPlugin _notifications;

  AlarmRefreshService(this._notifications);

  Future<void> initialize() async {
    // Create a silent notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.min,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> scheduleNextRefresh() async {
    await cancelRefresh();

    final scheduledTime = tz.TZDateTime.now(tz.local).add(
      const Duration(hours: AppConstants.tokenRefreshIntervalHours),
    );

    await _notifications.zonedSchedule(
      _notificationId,
      null, // No visible title
      null, // No visible body
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.min,
          priority: Priority.min,
          silent: true,
          ongoing: false,
          autoCancel: true,
          category: AndroidNotificationCategory.service,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'TOKEN_REFRESH_TRIGGER',
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  Future<void> cancelRefresh() async {
    await _notifications.cancel(_notificationId);
  }
}
