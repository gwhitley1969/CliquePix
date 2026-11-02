/// The paywall half of the router redirect, for a signed-in user. Returns
/// where to send them, or null to stay put. Kept free of providers so every
/// branch is unit-testable (test/subscription_gate_test.dart).
///
/// - [hasAccess]: effective access — subscribed OR in trial OR the optimistic
///   post-purchase window (hasAppAccessProvider).
/// - [isSubscribed]: an actual subscription (backend `entitlement.active`) or
///   a purchase still confirming. Trial alone is NOT subscribed.
String? subscriptionGateRedirect({
  required String location,
  required bool hasAccess,
  required bool isSubscribed,
}) {
  // Paywall gate: no access (trial lapsed + unsubscribed) → paywall, except
  // the allowlist. Trial/subscribed users (effective access) pass through,
  // preserving the invite loop during the trial.
  //
  // /invite/* is allowlisted so a lapsed user tapping an invite link (or
  // the Play install-referrer auto-join) reaches JoinCliqueScreen instead
  // of silently losing the invite code to a paywall bounce — the join
  // POST itself is still backend-gated by requireActiveEntitlement.
  // /diagnostics is allowlisted because Token Diagnostics matters most
  // exactly when a user is locked out. (Security audit 2026-06-04,
  // "Remaining" items.)
  //
  // /subscribe is deliberately NOT allowlisted: a lapsed user asking for the
  // voluntary paywall gets the mandatory one instead.
  final paywallExempt = location == '/paywall' ||
      location == '/profile' ||
      location == '/login' ||
      location.startsWith('/invite/') ||
      location.startsWith('/diagnostics');
  if (!hasAccess && !paywallExempt) return '/paywall';

  // Access regained while sitting on the paywall → into the app.
  if (hasAccess && location == '/paywall') return '/events';

  // /subscribe is the dismissible paywall trial users open on purpose (Home
  // banner, Profile, trial-ending push). Nothing to sell a subscriber — e.g.
  // a stale reminder tapped after subscribing.
  if (isSubscribed && location == '/subscribe') return '/events';

  return null;
}
