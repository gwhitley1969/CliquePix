import { AuthenticatedUser } from './authMiddleware';
import { SubscriptionRequiredError } from '../utils/errors';

// ============================================================================
// Entitlement gate
// ============================================================================
// Throws SubscriptionRequiredError (HTTP 402) if the authenticated user has
// no active Clique Pix subscription. Call immediately after
// authenticateRequest(req) on any handler that should be paywalled.
//
// Ungated endpoints (per docs/PAYWALL_ARCHITECTURE.md):
//   - POST /api/auth/verify              (sign-in / age gate happen here)
//   - GET  /api/users/me                 (account self-service)
//   - DELETE /api/users/me               (account deletion)
//   - POST /api/users/me/entitlement/refresh  (THE recovery path for stuck users)
//   - POST /api/users/me/avatar/*        (any avatar mutation)
//   - POST /api/push-tokens              (token registration even for non-subs)
//   - POST /api/telemetry/auth           (diagnostics for stuck-token cases)
//   - GET  /api/health                   (anonymous)
//   - POST /api/internal/*               (service-to-service)
//
// Everything else (events, photos, videos, cliques, DMs, reactions,
// notifications-list) must call requireActiveEntitlement.
export function requireActiveEntitlement(
  authUser: AuthenticatedUser,
  now: Date = new Date(),
): void {
  // strictly greater-than: a trial expiring at exactly `now` is closed (blocked).
  const inTrial = authUser.trialEndsAt != null && authUser.trialEndsAt > now;
  if (!authUser.entitlementActive && !inTrial) {
    throw new SubscriptionRequiredError();
  }
}
