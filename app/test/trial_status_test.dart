import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/paywall/domain/entitlement_state.dart';
import 'package:clique_pix/features/paywall/domain/trial_status.dart';

final _now = DateTime.utc(2026, 11, 2, 12);

EntitlementState _trialEndingIn(Duration d, {bool active = false}) =>
    EntitlementState(
      active: active,
      effectiveActive: true,
      inTrial: true,
      trialEndsAt: _now.add(d),
    );

TrialStatus? _status(EntitlementState e, {bool purchasePending = false}) =>
    computeTrialStatus(e, purchasePending: purchasePending, now: _now);

void main() {
  group('computeTrialStatus — when to prompt', () {
    test('prompts during an unexpired trial', () {
      expect(_status(_trialEndingIn(const Duration(days: 3))), isNotNull);
    });

    test('never prompts a subscriber, even with trial time left', () {
      expect(
        _status(_trialEndingIn(const Duration(days: 3), active: true)),
        isNull,
      );
    });

    test('hides while a purchase is confirming', () {
      expect(
        _status(_trialEndingIn(const Duration(days: 3)), purchasePending: true),
        isNull,
      );
    });

    test('hides once the trial end has passed', () {
      expect(_status(_trialEndingIn(const Duration(minutes: -1))), isNull);
    });

    test('hides at the exact moment the trial ends', () {
      expect(_status(_trialEndingIn(Duration.zero)), isNull);
    });

    test('hides when there is no trial date', () {
      expect(_status(EntitlementState.none), isNull);
    });
  });

  group('TrialStatus text', () {
    String headline(Duration d) => _status(_trialEndingIn(d))!.headline;
    String short(Duration d) => _status(_trialEndingIn(d))!.shortLabel;

    test('a fresh 7-day trial reads 7 days', () {
      expect(headline(const Duration(days: 7)), '7 days left in your free trial');
      expect(
        headline(const Duration(days: 7) - const Duration(seconds: 1)),
        '7 days left in your free trial',
      );
    });

    test('partial days round up', () {
      expect(headline(const Duration(hours: 36)), '2 days left in your free trial');
    });

    test('exactly one day reads singular', () {
      expect(headline(const Duration(days: 1)), '1 day left in your free trial');
      expect(short(const Duration(days: 1)), 'Free trial: 1 day left');
    });

    test('under a day switches to hours', () {
      expect(
        headline(const Duration(hours: 23, minutes: 59)),
        'Your free trial ends in 23 hours',
      );
      expect(short(const Duration(hours: 5)), 'Free trial: 5 hours left');
    });

    test('one hour reads singular', () {
      expect(
        headline(const Duration(hours: 1, minutes: 30)),
        'Your free trial ends in 1 hour',
      );
      expect(short(const Duration(hours: 1)), 'Free trial: 1 hour left');
    });

    test('under an hour', () {
      expect(
        headline(const Duration(minutes: 59)),
        'Your free trial ends in less than an hour',
      );
      expect(short(const Duration(minutes: 5)),
          'Free trial: less than an hour left');
    });

    test('several days, short label', () {
      expect(short(const Duration(days: 5)), 'Free trial: 5 days left');
    });
  });
}
