-- User avatars (profile pictures / headshots).
--
-- Adds the schema backing the avatar upload feature. Additive migration —
-- existing users.avatar_url column is intentionally preserved (unused since
-- migration 001 and never populated) so a rolling deploy is safe; dropping it
-- in the same migration as new columns would 500 the still-running old
-- backend in the gap between migration and deploy completion. A future
-- migration 011 can drop avatar_url once every deployment is post-feature.
--
-- avatar_blob_path / avatar_thumb_blob_path: relative paths inside the
-- 'photos' container (container name is historical). Example values:
--   avatar_blob_path       = 'avatars/{userId}/original.jpg'
--   avatar_thumb_blob_path = 'avatars/{userId}/thumb.jpg'
-- Client-facing API responses carry signed SAS URLs derived from these
-- paths; the raw blob path never leaves the backend.
--
-- avatar_updated_at: seeds client-side cache keys so CachedNetworkImage
-- (Flutter) and <img src> (web) don't serve stale avatars after a change.
-- Pattern: cacheKey: 'avatar_${userId}_v${avatar_updated_at.ms}'.
--
-- avatar_frame_preset: 0..4. 0 = auto-gradient hashed from display_name
-- (current behavior). 1..4 = user-chosen palette index. Honored on both
-- uploaded-photo frames AND initials fallback rings.
--
-- avatar_prompt_dismissed: user tapped "No Thanks" on the first-sign-in
-- welcome prompt — never re-prompt.
--
-- avatar_prompt_snoozed_until: user tapped "Maybe Later" — re-prompt
-- eligible after this timestamp. Snooze duration: 7 days.
--
-- Derived flag should_prompt_for_avatar (computed in authVerify + getMe):
--   avatar_blob_path IS NULL
--   AND NOT avatar_prompt_dismissed
--   AND (avatar_prompt_snoozed_until IS NULL OR avatar_prompt_snoozed_until < NOW())

ALTER TABLE users
  ADD COLUMN avatar_blob_path TEXT,
  ADD COLUMN avatar_thumb_blob_path TEXT,
  ADD COLUMN avatar_updated_at TIMESTAMPTZ,
  ADD COLUMN avatar_frame_preset SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN avatar_prompt_dismissed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN avatar_prompt_snoozed_until TIMESTAMPTZ;

-- Sanity bound on the frame preset. Keeps bad writes from bypassing the
-- API layer. 5 colors total (0 auto, 1..4 chosen).
ALTER TABLE users
  ADD CONSTRAINT users_avatar_frame_preset_range
  CHECK (avatar_frame_preset BETWEEN 0 AND 4);
