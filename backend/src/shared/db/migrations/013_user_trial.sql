-- App-granted free trial (no payment info required).
--
-- Layers on top of migration 012's RevenueCat entitlement columns. Effective
-- access = entitlement_active OR (trial_ends_at > NOW()). The trial is purely
-- time-based and computed live on every request (buildAuthUserResponse +
-- requireActiveEntitlement) — there is no stored boolean and therefore no
-- reconciliation timer for trial expiry.
--
-- Lifecycle:
--   * New users: auth.ts authVerify stamps trial_ends_at = NOW() + 7 days on
--     INSERT, and COALESCE-preserves it on every returning sign-in so re-auth
--     can never reset the window.
--   * Existing users at deploy time: backfilled to NOW() + 7 days below, so
--     nobody currently signed up is locked out the instant the gate goes live.
--     (Current beta testers + the reviewer also carry RevenueCat promotional
--     grants, which set entitlement_active = TRUE and trump trial state.)
--
-- Additive + nullable: safe for a rolling deploy. Old backend ignores the
-- column; new backend starts emitting in_trial / effective_active.

ALTER TABLE users ADD COLUMN trial_ends_at TIMESTAMPTZ;

UPDATE users SET trial_ends_at = NOW() + INTERVAL '7 days' WHERE trial_ends_at IS NULL;
