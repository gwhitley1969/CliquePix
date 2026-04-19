-- Track user activity so a timer function can detect users approaching the
-- 12-hour Entra External ID refresh-token inactivity cliff and wake them
-- with a silent FCM push before the refresh token becomes unusable.
--
-- last_activity_at:         Updated fire-and-forget by authMiddleware on
--                           every authenticated API call, capped to one
--                           write per minute per user via the middleware
--                           WHERE predicate. Null for users created before
--                           this migration (grandfathered).
--
-- last_refresh_push_sent_at: Set by refreshTokenPushTimer when it sends a
--                            silent-push wake-up to the user's device(s).
--                            Prevents duplicate pushes within a 6-hour
--                            window (one push per inactivity period).

ALTER TABLE users
  ADD COLUMN last_activity_at TIMESTAMPTZ,
  ADD COLUMN last_refresh_push_sent_at TIMESTAMPTZ;

CREATE INDEX idx_users_last_activity_at
  ON users(last_activity_at)
  WHERE last_activity_at IS NOT NULL;
