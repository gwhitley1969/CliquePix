import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../main.dart' show flutterLocalNotificationsPlugin;

typedef ReminderTelemetry = void Function(
  String event, {
  String? errorCode,
  Map<String, String>? extra,
});

/// Weekly Friday 5:00 PM local-time reminder.
///
/// Client-only, scheduled via `flutter_local_notifications.zonedSchedule` —
/// no FCM, no backend coupling. The plugin auto-recurs forever via
/// `DateTimeComponents.dayOfWeekAndTime` after the first scheduled fire.
///
/// `scheduleOrReschedule()` is idempotent and self-gates on the cached IANA
/// name + the plugin's `pendingNotificationRequests()` truth, so it's safe
/// to call on every cold start AND every `AppLifecycleState.resumed` for
/// timezone-change recovery (SFO→NYC traveler scenario).
class FridayReminderService {
  /// Stable, non-colliding ID. The only other ID space in use is
  /// `notification.hashCode` from FCM foreground display (main.dart:121),
  /// which is astronomically unlikely to collide with a literal 9001.
  static const int notificationId = 9001;
  static const String _kCachedTzKey = 'friday_reminder_iana_tz';

  /// IANA timezone resolver. Overridable for tests.
  @visibleForTesting
  static Future<String> Function() getLocalTimezoneFn =
      FlutterTimezone.getLocalTimezone;

  /// Plugin-pending lookup. Overridable for tests.
  @visibleForTesting
  static Future<List<PendingNotificationRequest>> Function() pendingRequestsFn =
      () => flutterLocalNotificationsPlugin.pendingNotificationRequests();

  /// Idempotent. Safe to call on every cold start AND every
  /// `AppLifecycleState.resumed`. No-ops when the cached IANA name matches
  /// the device's current IANA name AND the plugin still has a pending
  /// schedule for `notificationId`.
  static Future<void> scheduleOrReschedule({
    ReminderTelemetry? telemetry,
  }) async {
    String iana;
    try {
      iana = await getLocalTimezoneFn();
    } catch (e) {
      debugPrint(
          '[CliquePix] flutter_timezone lookup failed: $e — falling back to UTC');
      telemetry?.call('friday_reminder_tz_lookup_failed',
          errorCode: e.toString().split('\n').first);
      iana = 'UTC';
    }
    if (iana.isEmpty) iana = 'UTC';

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kCachedTzKey);

    final pending = await pendingRequestsFn();
    final hasFridayReminder = pending.any((p) => p.id == notificationId);

    final reason = computeReason(
      iana: iana,
      cached: cached,
      hasFridayReminder: hasFridayReminder,
    );
    if (reason == null) {
      telemetry?.call('friday_reminder_skipped_tz_unchanged');
      return;
    }

    tz.Location loc;
    try {
      loc = tz.getLocation(iana);
    } catch (_) {
      loc = tz.UTC;
    }
    tz.setLocalLocation(loc);

    final next = computeNextFriday5pm(loc);

    await flutterLocalNotificationsPlugin.cancel(notificationId);
    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Evening or weekend plans?',
      "Don't forget to create an Event and assign a Clique!",
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cliquepix_reminders',
          'Reminders',
          channelDescription:
              'Weekly Friday-evening nudge to create an Event',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: jsonEncode({'type': 'friday_reminder'}),
    );

    await prefs.setString(_kCachedTzKey, iana);

    telemetry?.call('friday_reminder_scheduled', extra: {
      'iana': iana,
      'next_fire_at': next.toIso8601String(),
      'reason': reason,
    });
  }

  /// Cancels the schedule and clears the IANA cache. Called from sign-out
  /// and account deletion paths so the device stops firing once the user is
  /// signed out.
  static Future<void> cancel() async {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedTzKey);
  }

  /// Pure state-machine: which reschedule reason (if any) applies?
  /// Returns `null` when nothing needs to be done.
  @visibleForTesting
  static String? computeReason({
    required String iana,
    required String? cached,
    required bool hasFridayReminder,
  }) {
    if (cached == null) return 'cold_start';
    if (cached != iana) return 'tz_changed';
    if (!hasFridayReminder) return 'os_purged';
    return null;
  }

  /// Next Friday 17:00 in [loc]. If today is Friday before 17:00, returns
  /// today at 17:00. If today is Friday at or after 17:00 (or any
  /// weekend/weekday past Friday), returns next week's Friday 17:00.
  ///
  /// `now` is optional — production callers omit it (defaults to
  /// `tz.TZDateTime.now(loc)`); tests inject a fixed instant.
  ///
  /// Uses calendar-day arithmetic via the `TZDateTime` constructor (which
  /// accepts overflow `day` values). This is DST-correct — adding 7 to the
  /// `day` field always produces the same wall-clock time one week later,
  /// even across DST transitions, whereas `TZDateTime.add(Duration(days: 7))`
  /// would add 168 absolute hours and silently shift by ±1 hour across DST.
  @visibleForTesting
  static tz.TZDateTime computeNextFriday5pm(tz.Location loc,
      {tz.TZDateTime? now}) {
    final n = now ?? tz.TZDateTime.now(loc);
    final daysUntilFriday = (DateTime.friday - n.weekday + 7) % 7;
    var candidate = tz.TZDateTime(
      loc,
      n.year,
      n.month,
      n.day + daysUntilFriday,
      17,
    );
    if (!candidate.isAfter(n)) {
      candidate = tz.TZDateTime(
        loc,
        n.year,
        n.month,
        n.day + daysUntilFriday + 7,
        17,
      );
    }
    return candidate;
  }
}
