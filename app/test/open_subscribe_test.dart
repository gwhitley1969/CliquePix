import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:clique_pix/features/paywall/presentation/open_subscribe.dart';
import 'package:clique_pix/services/telemetry_service.dart';

class _FakeTelemetry implements TelemetryService {
  final List<({String event, Map<String, String>? extra})> calls = [];

  @override
  void record(String event, {String? errorCode, Map<String, String>? extra}) {
    calls.add((event: event, extra: extra));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _router() => GoRouter(
      initialLocation: '/events',
      routes: [
        GoRoute(path: '/events', builder: (_, __) => const Text('events')),
        GoRoute(path: '/paywall', builder: (_, __) => const Text('paywall')),
        GoRoute(
          path: '/subscribe',
          builder: (_, state) =>
              Text('subscribe:${state.uri.queryParameters['source']}'),
        ),
      ],
    );

void main() {
  testWidgets('in trial: pushes the dismissible paywall over the current screen',
      (tester) async {
    final router = _router();
    final telemetry = _FakeTelemetry();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    openSubscribe(router,
        hasAccess: true, source: 'home_banner', telemetry: telemetry);
    await tester.pumpAndSettle();

    expect(find.text('subscribe:home_banner'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('trial over: goes straight to the mandatory paywall',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    openSubscribe(router,
        hasAccess: false, source: 'push', telemetry: _FakeTelemetry());
    await tester.pumpAndSettle();

    expect(find.text('paywall'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('records the entry point', (tester) async {
    final router = _router();
    final telemetry = _FakeTelemetry();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    openSubscribe(router,
        hasAccess: true, source: 'profile', telemetry: telemetry);

    final call = telemetry.calls.single;
    expect(call.event, 'subscribe_entry_tapped');
    expect(call.extra?['source'], 'profile');
    expect(call.extra?['has_access'], 'true');
  });
}
