import { HttpRequest } from '@azure/functions';
import { UnauthorizedError } from '../utils/errors';

// ============================================================================
// RevenueCat webhook authentication
// ============================================================================
// RevenueCat lets you configure an arbitrary value for the `Authorization`
// header that it sends on every webhook POST. We use this as a shared secret
// stored in Key Vault (`revenuecat-webhook-secret`) and surfaced to the
// Function App as env var `REVENUECAT_WEBHOOK_SECRET`.
//
// This is a shared-secret bearer-token scheme, NOT a JWT — RC does not sign
// the webhook body with a private key (as of API v1). The shared-secret is
// what we have.
//
// Constant-time string compare prevents timing attacks (negligible attack
// surface given the secret is long + random, but free defense-in-depth).

function getExpectedHeader(): string {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) {
    throw new Error('REVENUECAT_WEBHOOK_SECRET is not configured');
  }
  return `Bearer ${secret}`;
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/**
 * Throws UnauthorizedError if the request's Authorization header does not
 * match the configured RevenueCat webhook shared secret. Constant-time
 * comparison.
 */
export function authenticateRevenueCatWebhook(req: HttpRequest): void {
  const provided = req.headers.get('authorization');
  if (!provided) {
    throw new UnauthorizedError();
  }
  if (!constantTimeEqual(provided, getExpectedHeader())) {
    throw new UnauthorizedError();
  }
}
