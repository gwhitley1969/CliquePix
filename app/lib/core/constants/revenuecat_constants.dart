import 'dart:io' show Platform;

/// RevenueCat public SDK keys. These are NOT secrets (they're shipped in the
/// app binary) — the Secret API Key + webhook bearer live in Key Vault on the
/// backend only. Captured from RevenueCat dashboard → Project settings → API Keys.
class RevenueCatConstants {
  RevenueCatConstants._();

  // iOS public SDK key (production) — captured 2026-06-02 from the RC dashboard.
  static const String _appleKey = 'appl_OvhNypnojnQSEebpQtBikJYTHBa';

  // Android public SDK key — not yet available (Google Play app blocked on
  // payments/tax verification). Replace once the Play app is created in RC.
  static const String _googleKey = 'goog_REPLACE_WITH_ANDROID_PUBLIC_KEY';

  /// Platform-correct public key for Purchases.configure.
  static String get publicSdkKey => Platform.isIOS ? _appleKey : _googleKey;

  /// True when [key] is a scaffold placeholder (e.g. the Android key before
  /// the Play app exists in RevenueCat). configure() must skip the SDK
  /// entirely for placeholder keys — passing one to Purchases.configure
  /// leaves the SDK broken and PaywallView renders a blank screen.
  static bool isPlaceholderKey(String key) => key.contains('_REPLACE_WITH');

  /// The offering identifier configured in the RevenueCat dashboard.
  static const String offeringId = 'default';

  /// The entitlement identifier gating the CLIQUE Pix subscription.
  static const String entitlementId = 'plus';
}
