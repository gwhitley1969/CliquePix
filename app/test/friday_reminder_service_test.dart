import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:clique_pix/services/friday_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  group('computeNextFriday5pm', () {
    final ny = tz.getLocation('America/New_York');

    test('Monday returns same week Friday 17:00', () {
      // Monday 2026-04-27 12:00 ET → Friday 2026-05-01 17:00 ET
      final mon = tz.TZDateTime(ny, 2026, 4, 27, 12);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: mon);
      expect(next.year, 2026);
      expect(next.month, 5);
      expect(next.day, 1);
      expect(next.hour, 17);
      expect(next.weekday, DateTime.friday);
    });

    test('Friday before 17:00 returns same day 17:00', () {
      final fri = tz.TZDateTime(ny, 2026, 5, 1, 16, 59);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: fri);
      expect(next.day, 1);
      expect(next.hour, 17);
      expect(next.minute, 0);
    });

    test('Friday at exactly 17:00 returns next Friday', () {
      final fri = tz.TZDateTime(ny, 2026, 5, 1, 17);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: fri);
      expect(next.day, 8);
      expect(next.hour, 17);
    });

    test('Friday after 17:00 returns next Friday', () {
      final fri = tz.TZDateTime(ny, 2026, 5, 1, 18, 30);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: fri);
      expect(next.day, 8);
      expect(next.hour, 17);
    });

    test('Saturday returns next Friday', () {
      final sat = tz.TZDateTime(ny, 2026, 5, 2, 9);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: sat);
      expect(next.day, 8);
      expect(next.weekday, DateTime.friday);
      expect(next.hour, 17);
    });

    test('Sunday returns following Friday', () {
      final sun = tz.TZDateTime(ny, 2026, 5, 3, 23);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: sun);
      expect(next.day, 8);
      expect(next.weekday, DateTime.friday);
    });

    test('Thursday returns next-day Friday', () {
      final thu = tz.TZDateTime(ny, 2026, 4, 30, 8);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: thu);
      expect(next.day, 1);
      expect(next.month, 5);
      expect(next.weekday, DateTime.friday);
    });

    test('DST spring-forward: wall-clock 17:00 preserved across transition',
        () {
      // 2027-03-12 (Friday) is the last Friday before DST starts on
      // 2027-03-14 (Sunday). The next Friday is 2027-03-19, AFTER DST.
      // The fire should still be at 17:00 wall-clock in NY (now EDT, not EST).
      final preDstFri = tz.TZDateTime(ny, 2027, 3, 12, 18);
      final next =
          FridayReminderService.computeNextFriday5pm(ny, now: preDstFri);
      expect(next.year, 2027);
      expect(next.month, 3);
      expect(next.day, 19);
      expect(next.hour, 17);
      // EDT offset is -04:00. 17:00 EDT = 21:00 UTC. (EST would be 22:00 UTC.)
      expect(next.timeZoneOffset, const Duration(hours: -4));
    });

    test('crossing month boundary', () {
      // Wednesday 2026-04-29 → Friday 2026-05-01
      final wed = tz.TZDateTime(ny, 2026, 4, 29, 9);
      final next = FridayReminderService.computeNextFriday5pm(ny, now: wed);
      expect(next.month, 5);
      expect(next.day, 1);
    });
  });

  group('computeReason', () {
    test('no cache → cold_start', () {
      expect(
        FridayReminderService.computeReason(
            iana: 'America/New_York',
            cached: null,
            hasFridayReminder: false),
        'cold_start',
      );
    });

    test('cache differs from current → tz_changed', () {
      expect(
        FridayReminderService.computeReason(
            iana: 'America/New_York',
            cached: 'America/Los_Angeles',
            hasFridayReminder: true),
        'tz_changed',
      );
    });

    test('cache matches but no pending schedule → os_purged', () {
      expect(
        FridayReminderService.computeReason(
            iana: 'America/New_York',
            cached: 'America/New_York',
            hasFridayReminder: false),
        'os_purged',
      );
    });

    test('cache matches and pending exists → null (no-op)', () {
      expect(
        FridayReminderService.computeReason(
            iana: 'America/New_York',
            cached: 'America/New_York',
            hasFridayReminder: true),
        isNull,
      );
    });

    test('tz_changed takes precedence over os_purged', () {
      // If both cache != current AND no pending, the change is "tz_changed"
      // (more informative — explains the missing schedule too).
      expect(
        FridayReminderService.computeReason(
            iana: 'America/New_York',
            cached: 'America/Los_Angeles',
            hasFridayReminder: false),
        'tz_changed',
      );
    });
  });

  group('FlutterTimezone failure handling (telemetry)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Override the IANA resolver to throw.
      FridayReminderService.getLocalTimezoneFn =
          () async => throw Exception('platform channel failed');
      // Override pending lookup to return empty (so no-op short-circuit
      // doesn't fire).
      FridayReminderService.pendingRequestsFn =
          () async => <PendingNotificationRequest>[];
    });

    tearDown(() {
      // Reset to defaults to avoid bleeding into other tests.
      FridayReminderService.getLocalTimezoneFn = () async => 'UTC';
      FridayReminderService.pendingRequestsFn =
          () async => <PendingNotificationRequest>[];
    });

    test('emits friday_reminder_tz_lookup_failed and falls back to UTC',
        () async {
      final events = <String>[];
      // We can't actually invoke `zonedSchedule` in unit tests (no platform
      // channel), so the call will throw. We capture telemetry up to the
      // failure point — which is sufficient evidence that the lookup-fail
      // path was traversed.
      try {
        await FridayReminderService.scheduleOrReschedule(
          telemetry: (event, {errorCode, extra}) => events.add(event),
        );
      } catch (_) {
        // expected: zonedSchedule fails because the plugin has no platform
        // channel in unit-test mode
      }
      expect(events, contains('friday_reminder_tz_lookup_failed'));
    });
  });

  group('skipped_tz_unchanged path', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'friday_reminder_iana_tz': 'America/New_York',
      });
      FridayReminderService.getLocalTimezoneFn = () async => 'America/New_York';
      // Pending list contains id 9001.
      FridayReminderService.pendingRequestsFn = () async => [
            const PendingNotificationRequest(
              FridayReminderService.notificationId,
              null,
              null,
              null,
            ),
          ];
    });

    test('cache matches + pending exists → no-op + skip telemetry', () async {
      final events = <String>[];
      await FridayReminderService.scheduleOrReschedule(
        telemetry: (event, {errorCode, extra}) => events.add(event),
      );
      expect(events, ['friday_reminder_skipped_tz_unchanged']);
    });
  });
}
