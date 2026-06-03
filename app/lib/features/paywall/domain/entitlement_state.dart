import 'package:flutter/foundation.dart';

/// Mirrors the backend `entitlement` object emitted by buildAuthUserResponse.
/// `effectiveActive` is the value the router gate keys off: subscribed OR in trial.
@immutable
class EntitlementState {
  final bool active;
  final String? productId;
  final String? periodType;
  final bool? willRenew;
  final DateTime? expiresAt;
  final String? store;
  final bool inTrial;
  final DateTime? trialEndsAt;
  final bool effectiveActive;

  const EntitlementState({
    required this.active,
    required this.effectiveActive,
    required this.inTrial,
    this.productId,
    this.periodType,
    this.willRenew,
    this.expiresAt,
    this.store,
    this.trialEndsAt,
  });

  /// Default for an old backend that doesn't send the entitlement object, or a
  /// brand-new unsubscribed/expired user. Gate fails closed.
  static const EntitlementState none = EntitlementState(
    active: false,
    effectiveActive: false,
    inTrial: false,
  );

  factory EntitlementState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return EntitlementState(
      active: (json['active'] as bool?) ?? false,
      productId: json['product_id'] as String?,
      periodType: json['period_type'] as String?,
      willRenew: json['will_renew'] as bool?,
      expiresAt: parseDate(json['expires_at']),
      store: json['store'] as String?,
      inTrial: (json['in_trial'] as bool?) ?? false,
      trialEndsAt: parseDate(json['trial_ends_at']),
      effectiveActive: (json['effective_active'] as bool?) ?? false,
    );
  }

  /// Emits the same snake_case shape it parses, so a cached `UserModel` can
  /// round-trip the entitlement and avoid a paywall flash on cold start.
  Map<String, dynamic> toJson() => {
        'active': active,
        'product_id': productId,
        'period_type': periodType,
        'will_renew': willRenew,
        'expires_at': expiresAt?.toIso8601String(),
        'store': store,
        'in_trial': inTrial,
        'trial_ends_at': trialEndsAt?.toIso8601String(),
        'effective_active': effectiveActive,
      };
}
