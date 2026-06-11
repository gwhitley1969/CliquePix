// Widget tests for the never-blank paywall guarantee (2026-06-11 incident):
// the /paywall body must render a spinner while pre-flight runs and the
// branded fallback (Try Again / Refresh subscription status / Manage account)
// when pre-flight fails. The PaywallView success branch is intentionally NOT
// pumped — it builds a real platform view that cannot run under flutter_test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Offering;

import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_screen.dart';
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

void main() {
  late _FakeTelemetry telemetry;

  Widget makeApp(Override preflightOverride) {
    telemetry = _FakeTelemetry();
    return ProviderScope(
      overrides: [
        preflightOverride,
        telemetryServiceProvider.overrideWithValue(telemetry),
      ],
      child: const MaterialApp(home: PaywallScreen()),
    );
  }

  testWidgets('pre-flight failure renders the branded fallback, never blank',
      (tester) async {
    await tester.pumpWidget(makeApp(
      paywallOfferingProvider.overrideWith(
        (ref) => throw const PaywallUnavailableException('placeholder_key'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Refresh subscription status'), findsOneWidget);
    expect(find.text('Manage account'), findsOneWidget);
    final shown = telemetry.calls
        .singleWhere((c) => c.event == 'paywall_fallback_shown');
    expect(shown.extra?['reason'], 'placeholder_key');
  });

  testWidgets('pre-flight in progress renders a spinner', (tester) async {
    final never = Completer<Offering>();
    await tester.pumpWidget(makeApp(
      paywallOfferingProvider.overrideWith((ref) => never.future),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Try Again'), findsNothing);
  });
}
