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

/// Hosted Paywalls v2 paywall. Shown by the router when the user lacks access
/// (no subscription and trial lapsed). On a successful purchase/restore the
/// optimistic flag dismisses it instantly; the detached reconcile loop in
/// [OptimisticEntitlementNotifier] folds in the authoritative backend state.
///
/// HARD RULE: PaywallView is only ever mounted behind the
/// [paywallOfferingProvider] pre-flight. It is a bare platform view with no
/// load-failure callback — mounting it with an unconfigured SDK or unloadable
/// offerings renders a BLANK SCREEN (the 2026-06-11 Android lockout incident).
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  void _onEntitlementGranted(WidgetRef ref, String source) {
    ref
        .read(telemetryServiceProvider)
        .record('purchase_succeeded', extra: {'source': source});
    unawaited(
      ref.read(optimisticEntitlementProvider.notifier).onEntitlementGranted(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preflight = ref.watch(paywallOfferingProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.account_circle_outlined, color: Colors.white),
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
        data: (offering) => _buildPaywall(ref, offering),
        error: (e, _) => _PaywallFallback(
          reason: e is PaywallUnavailableException ? e.reason : 'unknown',
          onRetry: () => ref.invalidate(paywallOfferingProvider),
        ),
      ),
    );
  }

  Widget _buildPaywall(WidgetRef ref, Offering offering) {
    return PaywallView(
      offering: offering,
      onPurchaseCompleted: (customerInfo, storeTransaction) =>
          _onEntitlementGranted(ref, 'purchase'),
      onRestoreCompleted: (customerInfo) {
        if (customerInfo.entitlements.active
            .containsKey(RevenueCatConstants.entitlementId)) {
          _onEntitlementGranted(ref, 'restore');
        }
      },
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
