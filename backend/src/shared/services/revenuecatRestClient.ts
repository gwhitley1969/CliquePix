// ============================================================================
// RevenueCat REST API client (server-side only) — API v2
// ============================================================================
// Two operations used:
//   1. fetchPlusStateFromRc — force-sync entitlement state when the webhook
//      never arrived (manual "Refresh Subscription" + 30s post-purchase
//      auto-recovery paths).
//   2. deleteSubscriberFromRc — GDPR/CCPA "right to be forgotten" called from
//      deleteMe on account deletion.
//
// ⚠️ API VERSION (2026-06-11): this client MUST use API v2. The secret key in
// Key Vault ('revenuecat-secret-api-key' → env REVENUECAT_SECRET_API_KEY) is a
// v2 project key — RC's v1 endpoints reject it with error 7723 ("secret API
// key incompatible with RevenueCat API V1"). The original v1 implementation
// of this client therefore failed on EVERY call in production; the failures
// were invisible because both operations are best-effort and swallow errors.
// Verified live against /v2/projects/{p}/customers/{id}/subscriptions before
// the rewrite.
//
// Auth: Authorization: Bearer <RC Secret API Key>. We never log the key.
//
// Errors are best-effort: if RC's API is down the calling path (force-sync
// or account-delete) logs and continues. We do NOT throw so account deletion
// can never fail because of an external dependency.

const RC_API_V2_BASE = 'https://api.revenuecat.com/v2';
const RC_TIMEOUT_MS = 10_000;

// The RC project id is not a secret (it appears in dashboard URLs). Env
// override provided for hygiene; the default is the production project.
const RC_PROJECT_ID = process.env.REVENUECAT_PROJECT_ID ?? 'proj04f5314d';

function getSecretKey(): string {
  const key = process.env.REVENUECAT_SECRET_API_KEY;
  if (!key) {
    throw new Error('REVENUECAT_SECRET_API_KEY is not configured');
  }
  return key;
}

// ============================================================================
// v2 response shapes (the subset we actually use)
// ============================================================================
// Full schema: https://www.revenuecat.com/docs/api-v2
interface RcV2Entitlement {
  id: string;
  lookup_key: string; // 'plus'
}

interface RcV2Subscription {
  gives_access: boolean;
  status: string; // 'active' | 'trialing' | 'expired' | ...
  store: string | null; // 'app_store' | 'play_store' | 'promotional' | ...
  product_id: string | null; // null for dashboard promotional grants
  ends_at: number | null; // ms epoch; null = no end date
  entitlements?: { items?: RcV2Entitlement[] };
}

interface RcV2List<T> {
  items?: T[];
  next_page?: string | null;
}

/** Distilled 'plus' entitlement state for one customer, as RC sees it. */
export interface RcPlusState {
  active: boolean;
  /** ms epoch of the access end; null = RC reports no end date (lifetime). */
  expiresAtMs: number | null;
  productId: string | null;
  store: string | null; // RC v2 lowercase store identifier
}

/**
 * Read the customer's 'plus' state from RC's v2 subscriptions endpoint
 * (covers store purchases AND dashboard promotional grants — RC models a
 * promo grant as a `store: 'promotional'` subscription).
 *
 * Returns:
 *   - RcPlusState        — RC answered (a 404 = customer unknown to RC =
 *                          definitively not active, NOT an API error)
 *   - null               — RC API error / timeout; caller falls back to the
 *                          stored DB state (best-effort semantics)
 */
export async function fetchPlusStateFromRc(
  appUserId: string,
): Promise<RcPlusState | null> {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), RC_TIMEOUT_MS);
    const res = await fetch(
      `${RC_API_V2_BASE}/projects/${RC_PROJECT_ID}/customers/${encodeURIComponent(appUserId)}/subscriptions?limit=20`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${getSecretKey()}`,
          'X-Platform': 'server',
        },
        signal: ctl.signal,
      },
    ).finally(() => clearTimeout(timer));

    if (res.status === 404) {
      // Customer never seen by RC (e.g. the SDK never ran on their device).
      return { active: false, expiresAtMs: null, productId: null, store: null };
    }
    if (!res.ok) {
      console.warn(`RC fetchPlusState ${appUserId} returned ${res.status}`);
      return null;
    }

    const body = (await res.json()) as RcV2List<RcV2Subscription>;
    const plusSubs = (body.items ?? []).filter(
      (s) =>
        s.gives_access &&
        (s.entitlements?.items ?? []).some((e) => e.lookup_key === 'plus'),
    );
    if (plusSubs.length === 0) {
      return { active: false, expiresAtMs: null, productId: null, store: null };
    }

    // Multiple access-giving subscriptions: take the one reaching furthest
    // into the future (null ends_at = no end = wins outright).
    const best = plusSubs.reduce((a, b) => {
      if (a.ends_at === null) return a;
      if (b.ends_at === null) return b;
      return b.ends_at > a.ends_at ? b : a;
    });

    return {
      active: true,
      expiresAtMs: best.ends_at,
      productId: best.product_id,
      store: best.store,
    };
  } catch (err) {
    console.warn('RC fetchPlusState error:', (err as Error).message);
    return null;
  }
}

/**
 * DELETE the customer from RC. Used by deleteMe for GDPR/CCPA "right to
 * be forgotten" compliance. Best-effort — returns true on success or 404
 * (already gone). False on any other error; caller logs but does not abort.
 */
export async function deleteSubscriberFromRc(appUserId: string): Promise<boolean> {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), RC_TIMEOUT_MS);
    const res = await fetch(
      `${RC_API_V2_BASE}/projects/${RC_PROJECT_ID}/customers/${encodeURIComponent(appUserId)}`,
      {
        method: 'DELETE',
        headers: {
          Authorization: `Bearer ${getSecretKey()}`,
          'X-Platform': 'server',
        },
        signal: ctl.signal,
      },
    ).finally(() => clearTimeout(timer));

    if (res.ok || res.status === 404) return true;
    console.warn(`RC deleteSubscriber ${appUserId} returned ${res.status}`);
    return false;
  } catch (err) {
    console.warn('RC deleteSubscriber error:', (err as Error).message);
    return false;
  }
}
