// ============================================================================
// RevenueCat REST API client (server-side only)
// ============================================================================
// Two endpoints used:
//   1. GET  /v1/subscribers/{app_user_id} — force-sync entitlement state when
//      the webhook never arrived (manual "Refresh Subscription" path).
//   2. DELETE /v1/subscribers/{app_user_id} — GDPR/CCPA "right to be forgotten"
//      called from deleteMe on account deletion.
//
// Auth: Authorization: Bearer <RC Secret API Key>. The key is stored in Key
// Vault as 'revenuecat-secret-api-key' and surfaced to the Function App via
// the env var REVENUECAT_SECRET_API_KEY. We never log the key.
//
// Errors are best-effort: if RC's API is down the calling path (force-sync
// or account-delete) logs and continues. We do NOT throw so account deletion
// can never fail because of an external dependency.

const RC_API_BASE = 'https://api.revenuecat.com/v1';
const RC_TIMEOUT_MS = 10_000;

function getSecretKey(): string {
  const key = process.env.REVENUECAT_SECRET_API_KEY;
  if (!key) {
    throw new Error('REVENUECAT_SECRET_API_KEY is not configured');
  }
  return key;
}

// ============================================================================
// Subscriber response shape (the subset we actually use)
// ============================================================================
// Full schema: https://www.revenuecat.com/docs/api-v1#tag/customers
//
// We only care about the entitlements + subscriptions blocks. Everything
// else (aliases, non-subscriptions, etc.) is intentionally ignored.
export interface RcSubscriberEntitlement {
  expires_date: string | null; // ISO 8601
  product_identifier?: string;
  purchase_date?: string;
}

export interface RcSubscriberSubscription {
  expires_date: string | null;
  purchase_date?: string;
  period_type?: string; // 'normal' | 'trial' | 'intro' | 'promotional'
  store?: string; // 'app_store' | 'play_store' | 'promotional'
  unsubscribe_detected_at: string | null;
  billing_issues_detected_at?: string | null;
}

export interface RcSubscriberResponse {
  subscriber: {
    original_app_user_id: string;
    entitlements?: Record<string, RcSubscriberEntitlement | undefined>;
    subscriptions?: Record<string, RcSubscriberSubscription | undefined>;
  };
}

/**
 * GET the subscriber from RC. Returns null on any error (404, network, 5xx)
 * so the caller can fall back gracefully — this is best-effort sync.
 */
export async function fetchSubscriberFromRc(
  appUserId: string,
): Promise<RcSubscriberResponse | null> {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), RC_TIMEOUT_MS);
    const res = await fetch(`${RC_API_BASE}/subscribers/${encodeURIComponent(appUserId)}`, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${getSecretKey()}`,
        'X-Platform': 'server',
      },
      signal: ctl.signal,
    }).finally(() => clearTimeout(timer));

    if (!res.ok) {
      console.warn(`RC fetchSubscriber ${appUserId} returned ${res.status}`);
      return null;
    }
    return (await res.json()) as RcSubscriberResponse;
  } catch (err) {
    console.warn('RC fetchSubscriber error:', (err as Error).message);
    return null;
  }
}

/**
 * DELETE the subscriber from RC. Used by deleteMe for GDPR/CCPA "right to
 * be forgotten" compliance. Best-effort — returns true on success or 404
 * (already gone). False on any other error; caller logs but does not abort.
 */
export async function deleteSubscriberFromRc(appUserId: string): Promise<boolean> {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), RC_TIMEOUT_MS);
    const res = await fetch(`${RC_API_BASE}/subscribers/${encodeURIComponent(appUserId)}`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${getSecretKey()}`,
        'X-Platform': 'server',
      },
      signal: ctl.signal,
    }).finally(() => clearTimeout(timer));

    if (res.ok || res.status === 404) return true;
    console.warn(`RC deleteSubscriber ${appUserId} returned ${res.status}`);
    return false;
  } catch (err) {
    console.warn('RC deleteSubscriber error:', (err as Error).message);
    return false;
  }
}
