import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clique_pix/core/constants/revenuecat_constants.dart';
import 'package:clique_pix/services/telemetry_service.dart';

/// Thin wrapper over the RevenueCat SDK (v10). Lifecycle mirrors
/// DmRealtimeService: configure() once at deferred-init; logIn() on
/// AuthAuthenticated; logOut() on sign-out / resetSession. Never throws to
/// callers — failures are logged.
class RevenueCatService {
  RevenueCatService({this.onConfigureFailed});

  /// Telemetry hook — invoked with a machine-readable code when configure()
  /// cannot bring the SDK up. Injected (not a TelemetryService field) so this
  /// service stays decoupled from Riverpod and trivially fakeable in tests.
  final void Function(String errorCode)? onConfigureFailed;

  // Global SDK config state — static so configure() is idempotent even when a
  // throwaway instance (e.g. main.dart's deferred init) configures before the
  // provider's instance does. Mirrors the global `Purchases.configure` state.
  static bool _configured = false;
  static String? _configureError;

  /// True once Purchases.configure succeeded this process. The paywall
  /// pre-flight ([paywallOfferingProvider]) gates PaywallView on this —
  /// an unconfigured SDK makes PaywallView render NOTHING (blank screen).
  bool get isConfigured => _configured;

  /// Machine-readable reason the last configure() attempt failed
  /// ('placeholder_key' | exception runtimeType), or null.
  String? get configureError => _configureError;

  Future<void> configure() async {
    if (_configured) return;
    // A placeholder key (Android before the Play app exists in RC) can never
    // configure successfully — skip the SDK call entirely so the failure is
    // deterministic and instant instead of an opaque native error.
    if (RevenueCatConstants.isPlaceholderKey(RevenueCatConstants.publicSdkKey)) {
      _configureError = 'placeholder_key';
      debugPrint('[RC] configure skipped: placeholder SDK key');
      onConfigureFailed?.call('placeholder_key');
      return;
    }
    try {
      await Purchases.setLogLevel(LogLevel.warn);
      await Purchases.configure(
        PurchasesConfiguration(RevenueCatConstants.publicSdkKey),
      );
      _configured = true;
      _configureError = null;
    } catch (e) {
      _configureError = e.runtimeType.toString();
      debugPrint('[RC] configure failed: $e');
      onConfigureFailed?.call('configure_exception');
    }
  }

  /// Fetch current offerings. Unlike the rest of this service this THROWS on
  /// failure — the paywall pre-flight needs the error to pick its fallback UI.
  Future<Offerings> getOfferings() => Purchases.getOfferings();

  /// Alias the anonymous RC app-user id to our backend user id. Call AFTER
  /// sign-in. Do NOT call before auth.
  Future<void> logIn(String userId) async {
    if (!_configured) await configure();
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('[RC] logIn failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // RC throws if already anonymous — benign.
      debugPrint('[RC] logOut (benign if anonymous): $e');
    }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active
          .containsKey(RevenueCatConstants.entitlementId);
    } catch (e) {
      debugPrint('[RC] restore failed: $e');
      return false;
    }
  }

  /// Opens the platform subscription-management page. v10 has no
  /// `Purchases.showManageSubscriptions()`; we use `CustomerInfo.managementURL`
  /// (deep-links to the user's own subscription when present) with a
  /// store-settings fallback, launched via `url_launcher`.
  Future<void> openManageSubscriptions() async {
    try {
      String? url;
      try {
        url = (await Purchases.getCustomerInfo()).managementURL;
      } catch (_) {/* no active subscription yet — fall through to store page */}
      url ??= Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[RC] openManageSubscriptions failed: $e');
    }
  }

  Future<void> invalidateCache() async {
    try {
      await Purchases.invalidateCustomerInfoCache();
    } catch (e) {
      debugPrint('[RC] invalidateCache failed: $e');
    }
  }
}

/// Single shared RevenueCatService instance. Defined here (not in
/// paywall_providers) so `auth_providers` can inject it without creating a
/// circular import between the auth and paywall layers.
final revenueCatServiceProvider = Provider<RevenueCatService>(
  (ref) => RevenueCatService(
    onConfigureFailed: (code) => ref
        .read(telemetryServiceProvider)
        .record('revenuecat_configure_failed', errorCode: code),
  ),
);
