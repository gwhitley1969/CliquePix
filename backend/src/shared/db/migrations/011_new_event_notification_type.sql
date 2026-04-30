-- Add 'new_event' to the notifications.type CHECK constraint so the
-- pushNewEvent helper (events.ts) can insert in-app notification rows
-- when a clique member creates a new event.
--
-- Latest constraint (post-007) allows 8 types:
--   'new_photo', 'new_video', 'video_ready', 'video_processing_failed',
--   'event_expiring', 'event_expired', 'member_joined', 'event_deleted'
--
-- This migration appends 'new_event' to make 9. The existing 8 are preserved.
--
-- Idempotent: DROP CONSTRAINT IF EXISTS allows safe re-runs.

BEGIN;

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'new_photo',
    'new_video',
    'video_ready',
    'video_processing_failed',
    'event_expiring',
    'event_expired',
    'member_joined',
    'event_deleted',
    'new_event'
  ));

COMMIT;
