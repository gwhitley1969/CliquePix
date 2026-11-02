import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/core/routing/subscription_gate.dart';

String? _gate(
  String location, {
  required bool hasAccess,
  bool isSubscribed = false,
}) =>
    subscriptionGateRedirect(
      location: location,
      hasAccess: hasAccess,
      isSubscribed: isSubscribed,
    );

void main() {
  group('lapsed user (no access)', () {
    test('is sent to the paywall from app screens', () {
      expect(_gate('/events', hasAccess: false), '/paywall');
      expect(_gate('/events/abc', hasAccess: false), '/paywall');
      expect(_gate('/cliques', hasAccess: false), '/paywall');
    });

    test('keeps the allowlisted escape routes', () {
      expect(_gate('/paywall', hasAccess: false), isNull);
      expect(_gate('/profile', hasAccess: false), isNull);
      expect(_gate('/login', hasAccess: false), isNull);
      expect(_gate('/invite/abc123', hasAccess: false), isNull);
      expect(_gate('/diagnostics/tokens', hasAccess: false), isNull);
    });

    test('asking for the voluntary subscribe screen lands on the paywall', () {
      expect(_gate('/subscribe', hasAccess: false), '/paywall');
    });
  });

  group('user with access', () {
    test('is let into app screens', () {
      expect(_gate('/events', hasAccess: true), isNull);
    });

    test('is moved off the mandatory paywall', () {
      expect(_gate('/paywall', hasAccess: true), '/events');
    });

    test('in trial can open the voluntary subscribe screen', () {
      expect(_gate('/subscribe', hasAccess: true), isNull);
    });

    test('already subscribed is moved off the subscribe screen', () {
      expect(
        _gate('/subscribe', hasAccess: true, isSubscribed: true),
        '/events',
      );
    });
  });
}
