import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Offering;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:clique_pix/core/theme/app_colors.dart';
import 'package:clique_pix/core/theme/app_gradients.dart';
import 'package:clique_pix/features/auth/presentation/auth_providers.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/core/constants/revenuecat_constants.dart';
import 'package:clique_pix/services/telemetry_service.dart';

/// Hosted Paywalls v2 paywall, in two modes:
///
/// - Mandatory (`/paywall`, the default): shown by the router when the user
///   lacks access (no subscription and trial lapsed). On a successful
///   purchase/restore the optimistic flag dismisses it instantly; the detached
///   reconcile loop in [OptimisticEntitlementNotifier] folds in the
///   authoritative backend state.
/// - Dismissible (`/subscribe`, [dismissible] = true): opened on purpose by a
///   trial user (Home banner, Profile, trial-ending push). Has a Close button
///   and closes itself after a purchase/restore — the router can't, because a
///   trial user already had access before buying.
///
/// HARD RULE: PaywallView is only ever mounted behind the
/// [paywallOfferingProvider] pre-flight. It is a bare platform view with no
/// load-failure callback — mounting it with an unconfigured SDK or unloadable
/// offerings renders a BLANK SCREEN (the 2026-06-11 Android lockout incident).
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.dismissible = false, this.entry = 'gate'});

  /// True for the voluntary `/subscribe` route.
  final bool dismissible;

  /// Where the user came from, for telemetry:
  /// gate | home_banner | profile | push.
  final String entry;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _closing = false;

  void _onEntitlementGranted(String source) {
    ref.read(telemetryServiceProvider).record('purchase_succeeded',
        extra: {'source': source, 'entry': widget.entry});
    unawaited(
      ref.read(optimisticEntitlementProvider.notifier).onEntitlementGranted(),
    );
    if (widget.dismissible) _close();
  }

  /// Leaves the dismissible paywall. Idempotent: after a purchase the SDK
  /// fires both onPurchaseCompleted and onDismiss.
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/events');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preflight = ref.watch(paywallOfferingProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // HARD RULE: the paywall renders full-bleed under this bar
        // (extendBodyBehindAppBar). Without transparency-type Material the
        // bar absorbs every tap in the status-bar + toolbar strip, making any
        // template control there (e.g. Restore Purchases) untappable.
        forceMaterialTransparency: true,
        // PaywallView's own close button is ignored for V2 paywalls, so the
        // dismissible mode supplies one here. The RevenueCat template must
        // not draw its own close button or controls in this strip.
        leading: widget.dismissible
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Close',
                onPressed: _close,
              )
            : null,
        actions: [
          if (!widget.dismissible)
            IconButton(
              icon: const Icon(Icons.account_circle_outlined,
                  color: Colors.white),
              tooltip: 'Account',
              onPressed: () => context.push('/profile'),
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: preflight.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        data: _buildPaywall,
        error: (e, _) => _PaywallFallback(
          reason: e is PaywallUnavailableException ? e.reason : 'unknown',
          onRetry: () => ref.invalidate(paywallOfferingProvider),
        ),
      ),
    );
  }

  Widget _buildPaywall(Offering offering) {
    return PaywallView(
      offering: offering,
      onPurchaseCompleted: (customerInfo, storeTransaction) =>
          _onEntitlementGranted('purchase'),
      onRestoreCompleted: (customerInfo) {
        if (customerInfo.entitlements.active
            .containsKey(RevenueCatConstants.entitlementId)) {
          _onEntitlementGranted('restore');
        }
      },
      onDismiss: widget.dismissible ? _close : null,
    );
  }
}

/// Branded fallback rendered when the paywall pre-flight fails. Never blank:
/// always offers Try Again, a backend entitlement refresh (the escape path
/// for users granted a promo entitlement server-side — refresh flips
/// hasAppAccessProvider and the router releases them into the app), and the
/// Profile escape hatch.
class _PaywallFallback extends ConsumerStatefulWidget {
  const _PaywallFallback({required this.reason, required this.onRetry});

  final String reason;
  final VoidCallback onRetry;

  @override
  ConsumerState<_PaywallFallback> createState() => _PaywallFallbackState();
}

class _PaywallFallbackState extends ConsumerState<_PaywallFallback> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(telemetryServiceProvider)
        .record('paywall_fallback_shown', extra: {'reason': widget.reason});
  }

  Future<void> _refreshEntitlement() async {
    setState(() => _refreshing = true);
    await ref.read(authStateProvider.notifier).refreshEntitlement();
    if (!mounted) return;
    setState(() => _refreshing = false);
    // If the backend now reports access, hasAppAccessProvider flips and the
    // router redirect leaves /paywall automatically — no navigation needed.
    if (!ref.read(hasAppAccessProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active subscription found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppGradients.primary.createShader(bounds),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 72,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'CLIQUE Pix',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "We couldn't load subscription options right now. "
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              _gradientPill(label: 'Try Again', onTap: widget.onRetry),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _refreshing ? null : _refreshEntitlement,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Refresh subscription status'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/profile'),
                child: Text(
                  'Manage account',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mirrors the established gradient-pill CTA pattern
  /// (home_screen.dart `_buildCreateEventCTA`).
  Widget _gradientPill({required String label, required VoidCallback onTap}) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
