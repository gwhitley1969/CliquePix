import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/core/constants/revenuecat_constants.dart';
import 'package:clique_pix/services/telemetry_service.dart';

/// Hosted Paywalls v2 paywall. Shown by the router when the user lacks access
/// (no subscription and trial lapsed). On a successful purchase/restore the
/// optimistic flag dismisses it instantly; the detached reconcile loop in
/// [OptimisticEntitlementNotifier] folds in the authoritative backend state.
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
      body: PaywallView(
        onPurchaseCompleted: (customerInfo, storeTransaction) =>
            _onEntitlementGranted(ref, 'purchase'),
        onRestoreCompleted: (customerInfo) {
          if (customerInfo.entitlements.active
              .containsKey(RevenueCatConstants.entitlementId)) {
            _onEntitlementGranted(ref, 'restore');
          }
        },
      ),
    );
  }
}
