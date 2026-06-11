// Locks in the paywall pre-flight behavior added after the 2026-06-11 Android
// blank-paywall incident: PaywallView must never be mounted unless the
// RevenueCat SDK is configured AND a current offering with packages loaded.
// Every failure path must surface a machine-readable
// PaywallUnavailableException + a `paywall_offerings_load_failed` telemetry
// event (so blank-paywall classes of bug are visible in App Insights).

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Offering, Offerings;

import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/services/revenuecat_service.dart';
import 'package:clique_pix/services/telemetry_service.dart';

class _FakeRevenueCat implements RevenueCatService {
  _FakeRevenueCat({
    required this.configured,
    this.configError,
    this.offerings,
    this.offeringsError,
  });

  final bool configured;
  final String? configError;
  final Offerings? offerings;
  final Object? offeringsError;

  @override
  bool get isConfigured => configured;

  @override
  String? get configureError => configError;

  @override
  Future<void> configure() async {}

  @override
  Future<Offerings> getOfferings() async {
    if (offeringsError != null) throw offeringsError!;
    return offerings!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTelemetry implements TelemetryService {
  final List<({String event, String? errorCode})> calls = [];

  @override
  void record(String event, {String? errorCode, Map<String, String>? extra}) {
    calls.add((event: event, errorCode: errorCode));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeTelemetry telemetry;

  ProviderContainer makeContainer(_FakeRevenueCat rc) {
    telemetry = _FakeTelemetry();
    final container = ProviderContainer(overrides: [
      revenueCatServiceProvider.overrideWithValue(rc),
      telemetryServiceProvider.overrideWithValue(telemetry),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> expectUnavailable(
      ProviderContainer container, String reason) async {
    await expectLater(
      container.read(paywallOfferingProvider.future),
      throwsA(isA<PaywallUnavailableException>()
          .having((e) => e.reason, 'reason', reason)),
    );
    expect(
      telemetry.calls,
      contains((event: 'paywall_offerings_load_failed', errorCode: reason)),
    );
  }

  test('unconfigured SDK (placeholder key) → placeholder_key', () async {
    final container = makeContainer(
      _FakeRevenueCat(configured: false, configError: 'placeholder_key'),
    );
    await expectUnavailable(container, 'placeholder_key');
  });

  test('unconfigured SDK with no recorded error → not_configured', () async {
    final container = makeContainer(_FakeRevenueCat(configured: false));
    await expectUnavailable(container, 'not_configured');
  });

  test('getOfferings throws → offerings_error', () async {
    final container = makeContainer(_FakeRevenueCat(
      configured: true,
      offeringsError: PlatformException(code: 'ConfigurationError'),
    ));
    await expectUnavailable(container, 'offerings_error');
  });

  test('no current offering → no_current_offering', () async {
    final container = makeContainer(_FakeRevenueCat(
      configured: true,
      offerings: const Offerings({}),
    ));
    await expectUnavailable(container, 'no_current_offering');
  });

  test('current offering with zero packages → no_current_offering', () async {
    const empty = Offering('default', '', {}, []);
    final container = makeContainer(_FakeRevenueCat(
      configured: true,
      offerings: const Offerings({'default': empty}, current: empty),
    ));
    await expectUnavailable(container, 'no_current_offering');
  });
}
