import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Offering;
import 'package:clique_pix/features/auth/presentation/auth_providers.dart';
import 'package:clique_pix/features/auth/domain/auth_state.dart';
import 'package:clique_pix/services/revenuecat_service.dart';
import 'package:clique_pix/services/telemetry_service.dart';

/// Owns the optimistic post-purchase flag AND the detached backend-reconcile
/// loop. Lives in the ProviderScope (not in the paywall widget) so it survives
/// the paywall route being popped the instant the flag flips — which is exactly
/// what happens, since flipping the flag makes [hasAppAccessProvider] true and
/// the router redirects /paywall → /events.
class OptimisticEntitlementNotifier extends StateNotifier<bool> {
  OptimisticEntitlementNotifier(this._ref) : super(false);

  final Ref _ref;
  bool _running = false;

  /// Called when a purchase/restore grants the `plus` entitlement. Sets the
  /// optimistic flag (router dismisses the paywall immediately), then reconciles
  /// with the backend up to ~30s, clearing the flag once the backend confirms
  /// effective access. If the webhook is still slow after 30s the flag stays
  /// set — the user paid, so they stay OUT of the paywall; the next normal auth
  /// verify reconciles. No user-facing error after a successful charge.
  Future<void> onEntitlementGranted() async {
    state = true;
    if (_running) return;
    _running = true;
    try {
      for (final delay in [
        Duration.zero,
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]) {
        if (delay > Duration.zero) await Future.delayed(delay);
        await _ref.read(authStateProvider.notifier).refreshEntitlement();
        final s = _ref.read(authStateProvider);
        if (s is AuthAuthenticated && s.user.entitlement.effectiveActive) {
          state = false; // gate now keys off the authoritative backend state
          return;
        }
      }
    } finally {
      _running = false;
    }
  }
}

final optimisticEntitlementProvider =
    StateNotifierProvider<OptimisticEntitlementNotifier, bool>(
  (ref) => OptimisticEntitlementNotifier(ref),
);

/// THE gate value. True when the backend says effective_active (subscribed OR
/// in trial) OR we're in the optimistic post-purchase window.
final hasAppAccessProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  final optimistic = ref.watch(optimisticEntitlementProvider);
  final backend =
      auth is AuthAuthenticated && auth.user.entitlement.effectiveActive;
  return backend || optimistic;
}, name: 'hasAppAccessProvider');

/// Thrown by [paywallOfferingProvider] with a machine-readable reason — used
/// as the telemetry errorCode and the fallback UI's `reason` dimension.
class PaywallUnavailableException implements Exception {
  const PaywallUnavailableException(this.reason);

  /// placeholder_key | not_configured | configure-exception runtimeType |
  /// no_current_offering | timeout | offerings_error
  final String reason;

  @override
  String toString() => 'PaywallUnavailableException($reason)';
}

/// Pre-flight gate for the hosted PaywallView. PaywallView is a bare platform
/// view with NO load-failure callback — if the SDK is unconfigured (e.g. a
/// placeholder Android key) or offerings can't load, it renders NOTHING and
/// the user sees a blank screen (the 2026-06-11 Android lockout incident).
/// So: configure (idempotent) → verify configured → fetch offerings (10s cap)
/// → require a current offering with at least one package. autoDispose so
/// re-entering /paywall (or "Try Again") retries fresh.
final paywallOfferingProvider =
    FutureProvider.autoDispose<Offering>((ref) async {
  final rc = ref.watch(revenueCatServiceProvider);
  final telemetry = ref.read(telemetryServiceProvider);
  try {
    return await () async {
      await rc.configure();
      if (!rc.isConfigured) {
        throw PaywallUnavailableException(
            rc.configureError ?? 'not_configured');
      }
      final offerings = await rc.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) {
        throw const PaywallUnavailableException('no_current_offering');
      }
      return current;
    }()
        .timeout(const Duration(seconds: 10));
  } on PaywallUnavailableException catch (e) {
    telemetry.record('paywall_offerings_load_failed', errorCode: e.reason);
    rethrow;
  } on TimeoutException {
    telemetry.record('paywall_offerings_load_failed', errorCode: 'timeout');
    throw const PaywallUnavailableException('timeout');
  } catch (e) {
    telemetry.record('paywall_offerings_load_failed',
        errorCode: 'offerings_error');
    throw const PaywallUnavailableException('offerings_error');
  }
}, name: 'paywallOfferingProvider');
