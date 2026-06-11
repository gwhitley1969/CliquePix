import { execute, query, queryOne } from './dbService';
import { trackEvent } from './telemetryService';
import { fetchPlusStateFromRc } from './revenuecatRestClient';
import { isValidUUID } from '../utils/validators';

// ============================================================================
// RevenueCat webhook event payload shape (the subset we care about)
// ============================================================================
// RC webhooks wrap the event in { event: {...}, api_version: '1.0' }. We only
// need the inner event object here — the handler unwraps it before calling.
//
// Reference: https://www.revenuecat.com/docs/webhooks
//
// Several fields can be undefined depending on event type (e.g., expiration_
// at_ms is absent on EXPIRATION events that fire AT the expiry moment with
// no successor purchase). The service is tolerant of missing fields and
// derives the entitlement state from event type + product context.
export interface RcWebhookEvent {
  id: string; // RC's UUID for the event — idempotency key
  type: string; // INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, ...
  event_timestamp_ms: number;
  app_user_id: string; // == users.id (UUID we pass to Purchases.logIn)
  original_app_user_id?: string; // RC's canonical ID after any TRANSFER aliasing
  product_id?: string; // 'plus_monthly' / 'plus_annual'
  entitlement_ids?: string[]; // ['plus']
  period_type?: string; // 'TRIAL' | 'INTRO' | 'NORMAL' | 'PROMOTIONAL'
  expiration_at_ms?: number;
  purchased_at_ms?: number;
  store?: string; // 'APP_STORE' | 'PLAY_STORE' | 'PROMOTIONAL' | 'AMAZON' | ...
  aliases?: string[]; // every app user id RC knows for this customer
  cancel_reason?: string;
  expiration_reason?: string;
  // TRANSFER events carry these — the OLD owner of the entitlement
  transferred_from?: string[];
  transferred_to?: string[];
}

// Event types that activate or maintain entitlement.
const ACTIVATING_EVENTS = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
  'NON_RENEWING_PURCHASE',
  'SUBSCRIPTION_EXTENDED',
]);

// Event types that deactivate entitlement immediately.
const DEACTIVATING_EVENTS = new Set(['EXPIRATION']);

// CANCELLATION keeps the entitlement active until expires_at (will_renew flips
// false). BILLING_ISSUE is grace-period — we keep active and let the renewal
// or expiration event decide the fate. SUBSCRIPTION_PAUSED enters a paused
// state; for v1 we treat as inactive.
const PAUSING_EVENTS = new Set(['SUBSCRIPTION_PAUSED']);

export type EntitlementUpsertResult =
  | { applied: true; active: boolean }
  | {
      applied: false;
      reason: 'idempotent' | 'stale_timestamp' | 'not_plus_entitlement' | 'invalid_user_id';
    };

/**
 * Apply a RevenueCat webhook event to the user's entitlement state.
 *
 * Idempotency + concurrency safety: the UPDATE WHERE predicate gates on two
 * conditions:
 *   1. The incoming event_id is different from the last one we stored, AND
 *   2. EITHER there's no prior event for this user OR the incoming event's
 *      timestamp is newer than what we last stored.
 *
 * Together these protect against:
 *   - Duplicate webhook deliveries (RC retries on non-2xx) — same event_id
 *     skips with reason='idempotent'.
 *   - Out-of-order concurrent webhooks — a slow EXPIRATION event arriving
 *     after a fast RENEWAL would be rejected with 'stale_timestamp'.
 */
export async function upsertEntitlement(
  event: RcWebhookEvent,
): Promise<EntitlementUpsertResult> {
  // Reject events that don't carry the 'plus' entitlement. RC sends webhooks
  // per entitlement, but a future migration could add more entitlements and
  // we don't want stale ones bleeding into the plus state.
  const entitlementIds = event.entitlement_ids ?? [];
  if (entitlementIds.length > 0 && !entitlementIds.includes('plus')) {
    return { applied: false, reason: 'not_plus_entitlement' };
  }

  // Resolve the user row: the FIRST candidate that parses as our users.id
  // UUID, checking app_user_id → original_app_user_id → aliases.
  //
  // ORDER MATTERS (2026-06-11 fix). RC pins original_app_user_id to the FIRST
  // id the customer ever had — for SDK-created customers that is
  // `$RCAnonymousID:...` FOREVER, even after Purchases.logIn aliases in our
  // UUID; the identified id arrives in app_user_id (last-seen). The previous
  // `original_app_user_id ?? app_user_id` preference made EVERY webhook for an
  // anonymous-origin customer fail the UUID guard below and get dropped as
  // `invalid_user_id` — purchases self-healed via the client's 30s REST-API
  // force-sync, but dashboard promotional grants (the mandated reviewer/beta
  // mechanism) and server-driven renewals/expirations were silently lost.
  // Confirmed in App Insights: `entitlement_webhook_received` with a valid
  // UUID userId immediately followed by `entitlement_webhook_skipped
  // reason=invalid_user_id` for the reviewer's lifetime grant.
  //
  // A non-UUID-everywhere event (customer never aliased to a users.id) is
  // still a clean, logged no-op — feeding a non-UUID into the `WHERE id = $1`
  // UPDATE would raise a Postgres `invalid input syntax for type uuid` error
  // that (pre-fix) bubbled to a 500 and an RC retry-storm.
  const appUserId = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
  ].find((id): id is string => id != null && isValidUUID(id));

  if (!appUserId) {
    trackEvent('entitlement_webhook_invalid_user_id', { eventType: event.type });
    return { applied: false, reason: 'invalid_user_id' };
  }

  // Decide active flag based on event type.
  let nextActive: boolean;
  if (DEACTIVATING_EVENTS.has(event.type) || PAUSING_EVENTS.has(event.type)) {
    nextActive = false;
  } else if (ACTIVATING_EVENTS.has(event.type) || event.type === 'CANCELLATION') {
    // CANCELLATION = user canceled but access continues to expires_at.
    nextActive = true;
  } else if (event.type === 'BILLING_ISSUE') {
    // Grace period — keep active; subsequent RENEWAL or EXPIRATION wins.
    nextActive = true;
  } else if (event.type === 'TRANSFER') {
    // The user this webhook fires for is the LOSING side (transferred_from).
    // RC fires a separate event for the gaining side. Conservatively flip
    // to inactive for the losing side; the gaining side gets its activating
    // event independently.
    nextActive = false;
  } else {
    // Unknown event type. Don't change state but record receipt so we can
    // see in telemetry if RC adds an event type we should handle.
    trackEvent('entitlement_webhook_unknown_type', { type: event.type });
    return { applied: false, reason: 'idempotent' };
  }

  // will_renew = true UNLESS CANCELLATION (user opted out of renewal).
  let willRenew: boolean | null = null;
  if (event.type === 'CANCELLATION') willRenew = false;
  else if (ACTIVATING_EVENTS.has(event.type)) willRenew = true;

  const eventTimestamp = new Date(event.event_timestamp_ms);
  const expiresAt = event.expiration_at_ms ? new Date(event.expiration_at_ms) : null;
  const periodType = event.period_type
    ? mapPeriodType(event.period_type)
    : null;
  const store = event.store ?? null;

  const updated = await execute(
    `UPDATE users SET
        revenuecat_customer_id      = COALESCE($2, revenuecat_customer_id),
        entitlement_active          = $3,
        entitlement_product_id      = COALESCE($4, entitlement_product_id),
        entitlement_period_type     = COALESCE($5, entitlement_period_type),
        entitlement_will_renew      = COALESCE($6, entitlement_will_renew),
        entitlement_expires_at      = COALESCE($7, entitlement_expires_at),
        entitlement_store           = COALESCE($8, entitlement_store),
        entitlement_last_event_id   = $9,
        entitlement_updated_at      = $10,
        updated_at                  = NOW()
       WHERE id = $1
         AND (entitlement_last_event_id IS DISTINCT FROM $9)
         AND (entitlement_updated_at IS NULL OR entitlement_updated_at < $10)`,
    [
      appUserId,
      appUserId, // revenuecat_customer_id seeded with the same UUID
      nextActive,
      event.product_id ?? null,
      periodType,
      willRenew,
      expiresAt,
      store,
      event.id,
      eventTimestamp,
    ],
  );

  if (updated === 0) {
    // Find out which guard rejected so telemetry can distinguish.
    const existing = await queryOne<{ entitlement_last_event_id: string | null; entitlement_updated_at: Date | null }>(
      `SELECT entitlement_last_event_id, entitlement_updated_at FROM users WHERE id = $1`,
      [appUserId],
    );
    if (existing?.entitlement_last_event_id === event.id) {
      return { applied: false, reason: 'idempotent' };
    }
    return { applied: false, reason: 'stale_timestamp' };
  }

  return { applied: true, active: nextActive };
}

// Map RC's period_type to our column values (lowercase). RC emits uppercase.
function mapPeriodType(rcPeriodType: string): string {
  return rcPeriodType.toLowerCase();
}

/**
 * Read the current entitlement state for one user. Used by the manual
 * refresh endpoint to return the enriched user, and by tests to verify the
 * upsert side effects.
 */
export interface EntitlementRow {
  active: boolean;
  product_id: string | null;
  period_type: string | null;
  will_renew: boolean | null;
  expires_at: Date | null;
  store: string | null;
  last_event_id: string | null;
  updated_at: Date | null;
}

export async function getEntitlement(userId: string): Promise<EntitlementRow | null> {
  const row = await queryOne<{
    entitlement_active: boolean;
    entitlement_product_id: string | null;
    entitlement_period_type: string | null;
    entitlement_will_renew: boolean | null;
    entitlement_expires_at: Date | null;
    entitlement_store: string | null;
    entitlement_last_event_id: string | null;
    entitlement_updated_at: Date | null;
  }>(
    `SELECT entitlement_active, entitlement_product_id, entitlement_period_type,
            entitlement_will_renew, entitlement_expires_at, entitlement_store,
            entitlement_last_event_id, entitlement_updated_at
       FROM users WHERE id = $1`,
    [userId],
  );
  if (!row) return null;
  return {
    active: row.entitlement_active,
    product_id: row.entitlement_product_id,
    period_type: row.entitlement_period_type,
    will_renew: row.entitlement_will_renew,
    expires_at: row.entitlement_expires_at,
    store: row.entitlement_store,
    last_event_id: row.entitlement_last_event_id,
    updated_at: row.entitlement_updated_at,
  };
}

/**
 * Find users whose entitlement is marked active but whose expiration has
 * already passed. The reconciliation timer flips these to inactive — defensive
 * coverage for any EXPIRATION webhook RevenueCat dropped. Bounded LIMIT so
 * a one-time backlog can't blow up a single timer invocation.
 */
export async function findExpiredActive(limit = 500): Promise<{ id: string; last_event_id: string | null }[]> {
  return query<{ id: string; last_event_id: string | null }>(
    `SELECT id, entitlement_last_event_id AS last_event_id
       FROM users
      WHERE entitlement_active = TRUE
        AND entitlement_expires_at IS NOT NULL
        AND entitlement_expires_at < NOW()
      LIMIT $1`,
    [limit],
  );
}

export async function markExpired(userId: string): Promise<void> {
  // Self-validating to close a TOCTOU: the reconciliation timer snapshots
  // expired rows (findExpiredActive) then calls this per-row, and forceSync
  // calls it after its lag-guard. A RENEWAL webhook landing in that window
  // extends entitlement_expires_at into the future (active stays TRUE) — without
  // re-checking expiry HERE, we would deactivate a customer who just paid. The
  // IS NOT NULL clause also leaves lifetime/promotional grants (null expiry)
  // untouched. Only deactivate a row whose stored expiry has genuinely passed.
  await execute(
    `UPDATE users SET
        entitlement_active = FALSE,
        entitlement_updated_at = NOW(),
        updated_at = NOW()
       WHERE id = $1
         AND entitlement_active = TRUE
         AND entitlement_expires_at IS NOT NULL
         AND entitlement_expires_at < NOW()`,
    [userId],
  );
}

/**
 * Force-sync entitlement state from RC's REST API. Called by the manual
 * "Refresh Subscription" path in the Flutter Profile + the auto-recovery
 * path the client triggers 30s after a successful purchase if the backend
 * webhook hasn't landed. Returns the post-sync EntitlementRow.
 *
 * On RC API failure, the caller decides how to surface — typically as a
 * "We couldn't reach the subscription service; try again in a moment"
 * error rather than a hard 500.
 */
export async function forceSyncFromRcApi(userId: string): Promise<EntitlementRow | null> {
  const rcState = await fetchPlusStateFromRc(userId);
  if (!rcState) return getEntitlement(userId); // RC API error — keep stored state

  // A promotional / lifetime entitlement (the mechanism CLAUDE.md mandates for
  // the App Store reviewer + beta testers) has no end date (expiresAtMs null)
  // and never expires — treat it as active-forever. A non-null expiry is active
  // only when it's still in the future. Without the null-expiry case, a
  // reviewer/tester tapping "Refresh Subscription" would be force-deactivated
  // and hard-paywalled out of the entire app (App Store reviewer-rejection risk).
  const expiresAtMs = rcState.expiresAtMs;
  const isLifetime = rcState.active && expiresAtMs === null;
  const isActive =
    rcState.active && (isLifetime || (expiresAtMs !== null && expiresAtMs > Date.now()));

  if (!isActive) {
    // RC API says inactive. BUT RC's REST API is eventually-consistent and can
    // lag webhook events by seconds–minutes — exactly the window when the
    // client's 30s post-purchase auto-recovery calls this endpoint. Do NOT
    // deactivate off a stale/incomplete API read when our DB already shows an
    // active entitlement that should still be active:
    //   - a FUTURE expiry → a just-paid subscriber (the original H1 guard), or
    //   - a NULL expiry    → a lifetime/promotional grant (reviewer + testers;
    //                         the reconciliation timer already skips these).
    // A synthetic EXPIRATION would win the ordering guard AND make the real
    // RENEWAL webhook get rejected as stale — a sticky lockout of a legitimate
    // customer. Only deactivate when the stored expiry has genuinely passed.
    const current = await getEntitlement(userId);
    const dbExpiresMs = current?.expires_at ? new Date(current.expires_at).getTime() : null;
    if (current?.active && (dbExpiresMs == null || dbExpiresMs > Date.now())) {
      trackEvent('entitlement_force_sync_skipped_api_lag', { userId });
      return current;
    }
    await markExpired(userId);
    trackEvent('entitlement_force_sync_inactive', { userId });
    return getEntitlement(userId);
  }

  // Active per RC API — synthesize a RENEWAL below to reflect the real payment.
  const productId = rcState.productId; // null for dashboard promotional grants
  // RC v2 stores values lowercased (`app_store` / `play_store` /
  // `promotional`); webhook events use uppercased ones. Normalize to uppercase
  // to match webhook-driven rows.
  const store = rcState.store ? rcState.store.toUpperCase() : null;
  // v2 subscriptions don't expose period_type directly; a promotional store
  // IS the promotional period (matches the webhook's period_type semantics).
  const periodType = rcState.store === 'promotional' ? 'PROMOTIONAL' : null;
  // NOTE: RcWebhookEvent carries no will_renew field — upsertEntitlement
  // derives it from the event type (RENEWAL ⇒ true); a webhook is the source
  // of truth for will_renew.

  // Synthesize a force-sync RENEWAL so we can reuse the same upsert path.
  // event_id is unique per sync so it won't be idempotency-skipped. Only the
  // active case reaches here — the inactive case returned above with the
  // API-lag corroboration guard, so we never down-grade via a synthetic event.
  const syntheticEvent: RcWebhookEvent = {
    id: `force-sync-${userId}-${Date.now()}`,
    type: 'RENEWAL',
    event_timestamp_ms: Date.now(),
    app_user_id: userId,
    product_id: productId ?? undefined,
    entitlement_ids: ['plus'],
    period_type: periodType ?? undefined,
    expiration_at_ms: expiresAtMs ?? undefined,
    store: store ?? undefined,
  };

  await upsertEntitlement(syntheticEvent);
  trackEvent('entitlement_force_sync_complete', { userId, active: 'true' });
  return getEntitlement(userId);
}
