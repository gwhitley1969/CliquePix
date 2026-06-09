-- RevenueCat subscription entitlements.
--
-- Backs the CLIQUE Pix Plus hard paywall introduced post-v1. Every install
-- must subscribe immediately after sign-in to use the app; the backend is
-- the authoritative source for entitlement state, fed by RevenueCat
-- webhooks at POST /api/internal/revenuecat-webhook and reconciled every
-- 6h by entitlementReconciliationTimer.
--
-- Additive only — every column is nullable (except entitlement_active which
-- defaults FALSE), so a rolling deploy is safe: the still-running old
-- backend continues to function while the new schema is in place; once the
-- new backend ships, buildAuthUserResponse starts emitting the entitlement
-- object.
--
-- ---------------------------------------------------------------------------
-- Column-on-existing-table chosen over a separate `subscriptions` table:
-- v1 only cares about CURRENT entitlement state per user, not history. The
-- full audit trail is in RevenueCat's dashboard + the webhook event log
-- (App Insights). A future migration can introduce a history table if we
-- need per-period analytics that the RC dashboard can't answer.
--
-- App User ID strategy: users.id (UUID) is the RevenueCat App User ID. The
-- Flutter SDK calls Purchases.logIn(user.id) on AuthAuthenticated; webhook
-- payloads echo the same UUID in app_user_id, which we use to find the row.
-- ---------------------------------------------------------------------------
--
-- revenuecat_customer_id: typically identical to users.id (we pass user.id
-- as the App User ID to Purchases.logIn). RevenueCat may alias / merge
-- customers in edge cases (e.g., one device reused across users); when
-- that happens this column records the canonical RC-side identifier.
-- Usually equal to users.id.
--
-- entitlement_active: the bool the API check actually reads.
-- requireActiveEntitlement middleware: 402 if !entitlement_active.
--
-- entitlement_product_id: 'plus_monthly' / 'plus_annual'.
--
-- entitlement_period_type: 'trial' | 'intro' | 'normal' | 'promotional'.
-- Matches RevenueCat's period_type enum. 'promotional' covers manual
-- dashboard grants used for beta testers + the App Store reviewer account.
--
-- entitlement_will_renew: false after a user cancels (sub stays active
-- through entitlement_expires_at; reconciliation timer flips _active on
-- expiry). Surfaced to the client so the paywall can offer a "Resubscribe"
-- prompt before the access cliff.
--
-- entitlement_expires_at: end of the current billing period. After this
-- timestamp, entitlement_active is expected to be FALSE — either set by
-- the EXPIRATION webhook event or by entitlementReconciliationTimer's 6h
-- sweep if the webhook never lands.
--
-- entitlement_store: 'APP_STORE' | 'PLAY_STORE' | 'PROMOTIONAL'. Used by
-- the client to point the "Manage Subscription" button at the correct
-- platform sheet via Purchases.showManageSubscriptions().
--
-- entitlement_last_event_id: webhook idempotency. upsertEntitlement only
-- applies an update when (event_id is new) AND (event_timestamp is newer
-- than entitlement_updated_at). Protects against duplicate deliveries and
-- out-of-order concurrent webhooks.
--
-- entitlement_updated_at: stamped on every successful upsert. Used in the
-- ordering predicate above so a late-arriving older event can't overwrite
-- newer state.

ALTER TABLE users
  ADD COLUMN revenuecat_customer_id TEXT,
  ADD COLUMN entitlement_active BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN entitlement_product_id TEXT,
  ADD COLUMN entitlement_period_type TEXT,
  ADD COLUMN entitlement_will_renew BOOLEAN,
  ADD COLUMN entitlement_expires_at TIMESTAMPTZ,
  ADD COLUMN entitlement_store TEXT,
  ADD COLUMN entitlement_last_event_id TEXT,
  ADD COLUMN entitlement_updated_at TIMESTAMPTZ;

-- Sanity bound on store. Matches RevenueCat's stores enum + our manual
-- promotional grant value. Permissive on text so a future RC store add
-- (e.g., AMAZON, STRIPE if we ever ship web billing) doesn't break the
-- existing column — the CHECK constraint is intentionally NOT enforced
-- so we don't pin ourselves to a closed enum that RC controls.

-- Partial index for the reconciliation timer. Most rows are inactive
-- (free users / never-subscribed), so a partial index keeps it tiny and
-- the timer scan cheap. Indexed only when active so we can find expired-
-- but-still-flagged-active rows in O(matches) instead of O(users).
CREATE INDEX idx_users_entitlement_expires
  ON users(entitlement_expires_at)
  WHERE entitlement_active = TRUE;
