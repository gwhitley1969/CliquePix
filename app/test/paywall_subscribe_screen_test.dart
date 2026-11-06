// Widget tests for the dismissible paywall at /subscribe — the one trial users
// open on purpose from the Home banner, Profile, or the trial-ending push.
// Pre-flight is forced to fail so the branded fallback renders: the
// PaywallView success branch is a platform view that cannot run under
// flutter_test (see paywall_screen_fallback_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_screen.dart';
import 'package:clique_pix/services/telemetry_service.dart';

class _FakeTelemetry implements TelemetryService {
  @override
  void record(String event, {String? errorCode, Map<String, String>? extra}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(GoRouter router) => ProviderScope(
      overrides: [
        paywallOfferingProvider.overrideWith(
          (ref) => throw const PaywallUnavailableException('offerings_error'),
        ),
        telemetryServiceProvider.overrideWithValue(_FakeTelemetry()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );

GoRouter _router({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('home')),
        GoRoute(path: '/events', builder: (_, __) => const Text('events')),
        GoRoute(
          path: '/subscribe',
          builder: (_, __) =>
              const PaywallScreen(dismissible: true, entry: 'test'),
        ),
      ],
    );

void main() {
  testWidgets('dismissible paywall shows Close and no Account shortcut',
      (tester) async {
    await tester.pumpWidget(_app(_router(initialLocation: '/subscribe')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Account'), findsNothing);
  });

  testWidgets('Close returns to the screen the paywall was opened from',
      (tester) async {
    final router = _router(initialLocation: '/');
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    router.push('/subscribe');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('Close with nothing to go back to lands on Events',
      (tester) async {
    await tester.pumpWidget(_app(_router(initialLocation: '/subscribe')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('events'), findsOneWidget);
  });

  testWidgets('mandatory paywall keeps Account and has no Close',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paywallOfferingProvider.overrideWith(
          (ref) => throw const PaywallUnavailableException('offerings_error'),
        ),
        telemetryServiceProvider.overrideWithValue(_FakeTelemetry()),
      ],
      child: const MaterialApp(home: PaywallScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
  });

  // The RevenueCat template draws full-bleed under the AppBar; a canvas-type
  // AppBar would swallow taps on template controls in the top strip
  // (Restore Purchases sat there when 1.0.4 was reviewed).
  testWidgets('AppBar lets taps pass through in both paywall modes',
      (tester) async {
    for (final dismissible in [true, false]) {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          paywallOfferingProvider.overrideWith(
            (ref) => throw const PaywallUnavailableException('offerings_error'),
          ),
          telemetryServiceProvider.overrideWithValue(_FakeTelemetry()),
        ],
        child: MaterialApp(home: PaywallScreen(dismissible: dismissible)),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.forceMaterialTransparency, isTrue,
          reason: 'dismissible=$dismissible');
    }
  });
}
