-- Add 'clique_ownership_transferred' to the notifications.type CHECK constraint
-- so notifyNewOwner (cliqueOwnershipService.ts) can insert an in-app row when a
-- member is made the owner of a clique (explicit transfer, owner-leave
-- auto-promote, or account-deletion auto-promote).
--
-- Prior constraint (post-011) allows 9 types:
--   'new_photo','new_video','video_ready','video_processing_failed',
--   'event_expiring','event_expired','member_joined','event_deleted','new_event'
--
-- This migration appends 'clique_ownership_transferred' to make 10. Idempotent.

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
    'new_event',
    'clique_ownership_transferred'
  ));

COMMIT;
