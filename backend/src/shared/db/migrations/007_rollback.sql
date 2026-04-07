-- ROLLBACK for migration 007_add_video_support_to_photos.sql
-- Apply ONLY if no production rows have used the new video columns yet.
-- After any video data exists, this rollback will fail (due to CHECK constraint
-- mismatches) or destroy data (the new columns get dropped).
--
-- Usage: psql "$CONN_STR" -f 007_rollback.sql

BEGIN;

-- =============================================================================
-- 1. Drop new indexes
-- =============================================================================
DROP INDEX IF EXISTS idx_photos_video_failed;
DROP INDEX IF EXISTS idx_photos_video_orphan;
DROP INDEX IF EXISTS idx_photos_processing_status;
DROP INDEX IF EXISTS idx_photos_media_type_event;

-- =============================================================================
-- 2. Restore notifications.type CHECK to its pre-007 state
-- =============================================================================
ALTER TABLE notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'new_photo',
    'event_expiring',
    'event_expired',
    'member_joined',
    'event_deleted'
  ));

-- =============================================================================
-- 3. Rename reactions.media_id back to photo_id
-- =============================================================================
ALTER TABLE reactions RENAME CONSTRAINT reactions_media_id_user_id_reaction_type_key TO reactions_photo_id_user_id_reaction_type_key;
ALTER TABLE reactions RENAME CONSTRAINT reactions_media_id_fkey TO reactions_photo_id_fkey;
ALTER INDEX idx_reactions_media_id RENAME TO idx_reactions_photo_id;
ALTER TABLE reactions RENAME COLUMN media_id TO photo_id;

-- =============================================================================
-- 4. Restore photos mime_type CHECK to its pre-007 state
-- =============================================================================
ALTER TABLE photos DROP CONSTRAINT photos_mime_type_check;
ALTER TABLE photos ADD CONSTRAINT photos_mime_type_check
  CHECK (mime_type IN ('image/jpeg', 'image/png'));

-- =============================================================================
-- 5. Restore photos status CHECK to its pre-007 state
-- =============================================================================
ALTER TABLE photos DROP CONSTRAINT photos_status_check;
ALTER TABLE photos ADD CONSTRAINT photos_status_check
  CHECK (status IN ('pending', 'active', 'deleted'));

-- =============================================================================
-- 6. Drop video-specific columns
-- =============================================================================
ALTER TABLE photos DROP COLUMN IF EXISTS processing_error;
ALTER TABLE photos DROP COLUMN IF EXISTS processing_status;
ALTER TABLE photos DROP COLUMN IF EXISTS poster_blob_path;
ALTER TABLE photos DROP COLUMN IF EXISTS mp4_fallback_blob_path;
ALTER TABLE photos DROP COLUMN IF EXISTS hls_manifest_blob_path;
ALTER TABLE photos DROP COLUMN IF EXISTS normalized_to_sdr;
ALTER TABLE photos DROP COLUMN IF EXISTS is_hdr_source;
ALTER TABLE photos DROP COLUMN IF EXISTS source_audio_codec;
ALTER TABLE photos DROP COLUMN IF EXISTS source_video_codec;
ALTER TABLE photos DROP COLUMN IF EXISTS source_container;
ALTER TABLE photos DROP COLUMN IF EXISTS duration_seconds;

-- =============================================================================
-- 7. Drop media_type column
-- =============================================================================
ALTER TABLE photos DROP COLUMN IF EXISTS media_type;

COMMIT;
