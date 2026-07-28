package com.cliquepix.clique_pix

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (NOT FlutterActivity) is a HARD requirement of RevenueCat's
// purchases_ui_flutter PaywallView: its Android platform view throws
// "Implementation Error: PaywallView requires the MainActivity to extend
// FlutterFragmentActivity" at construction on any other host, which rendered the
// paywall as a BLANK dark screen for every lapsed-trial Android user (2026-07-27
// incident — the throw happens in the native view factory and has no error channel,
// so the Dart-side paywallOfferingProvider pre-flight and _PaywallFallback cannot
// catch it). Do NOT revert to FlutterActivity while PaywallView is the paywall
// mechanism. See docs/DEPLOYMENT_STATUS.md (2026-07-27 incident entry).
class MainActivity : FlutterFragmentActivity()
