-- Add video support to the photos table
-- Extends the existing photos table with media_type + video-specific columns
-- Renames reactions.photo_id to media_id (FK target unchanged)
-- Updates notifications.type CHECK to allow video notification types
-- See docs/VIDEO_ARCHITECTURE_DECISIONS.md Decision 1 for the schema choice rationale

BEGIN;

-- =============================================================================
-- 1. Add media_type discriminator column
-- =============================================================================
ALTER TABLE photos ADD COLUMN media_type TEXT NOT NULL DEFAULT 'photo'
  CHECK (media_type IN ('photo', 'video'));

-- =============================================================================
-- 2. Add video-specific columns (all nullable for photo rows)
-- =============================================================================
ALTER TABLE photos ADD COLUMN duration_seconds INTEGER;

ALTER TABLE photos ADD COLUMN source_container TEXT
  CHECK (source_container IS NULL OR source_container IN ('mp4', 'mov'));

ALTER TABLE photos ADD COLUMN source_video_codec TEXT
  CHECK (source_video_codec IS NULL OR source_video_codec IN ('h264', 'hevc'));

ALTER TABLE photos ADD COLUMN source_audio_codec TEXT;
ALTER TABLE photos ADD COLUMN is_hdr_source BOOLEAN;
ALTER TABLE photos ADD COLUMN normalized_to_sdr BOOLEAN;
ALTER TABLE photos ADD COLUMN hls_manifest_blob_path TEXT;
ALTER TABLE photos ADD COLUMN mp4_fallback_blob_path TEXT;
ALTER TABLE photos ADD COLUMN poster_blob_path TEXT;

ALTER TABLE photos ADD COLUMN processing_status TEXT
  CHECK (processing_status IS NULL OR processing_status IN ('pending', 'queued', 'running', 'complete', 'failed'));

ALTER TABLE photos ADD COLUMN processing_error TEXT;

-- =============================================================================
-- 3. Extend status enum to include video-specific states
-- =============================================================================
ALTER TABLE photos DROP CONSTRAINT photos_status_check;
ALTER TABLE photos ADD CONSTRAINT photos_status_check
  CHECK (status IN ('pending', 'active', 'deleted', 'processing', 'rejected'));

-- =============================================================================
-- 4. Allow video MIME types in addition to photo MIME types
-- =============================================================================
ALTER TABLE photos DROP CONSTRAINT photos_mime_type_check;
ALTER TABLE photos ADD CONSTRAINT photos_mime_type_check
  CHECK (mime_type IN ('image/jpeg', 'image/png', 'video/mp4', 'video/quicktime'));

-- =============================================================================
-- 5. Rename reactions.photo_id to media_id (FK target unchanged — still photos.id)
-- =============================================================================
ALTER TABLE reactions RENAME COLUMN photo_id TO media_id;
ALTER INDEX idx_reactions_photo_id RENAME TO idx_reactions_media_id;
ALTER TABLE reactions RENAME CONSTRAINT reactions_photo_id_fkey TO reactions_media_id_fkey;
-- Also rename the auto-generated unique constraint for consistency
ALTER TABLE reactions RENAME CONSTRAINT reactions_photo_id_user_id_reaction_type_key TO reactions_media_id_user_id_reaction_type_key;

-- =============================================================================
-- 6. Update notifications.type CHECK to allow video notification types
-- =============================================================================
ALTER TABLE notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'new_photo',
    'new_video',
    'video_ready',
    'video_processing_failed',
    'event_expiring',
    'event_expired',
    'member_joined',
    'event_deleted'
  ));

-- =============================================================================
-- 7. New indexes for video query patterns
-- =============================================================================

-- Index for unified media feed queries that filter by event + media_type
CREATE INDEX idx_photos_media_type_event ON photos(event_id, media_type, created_at DESC);

-- Partial index for tracking videos in processing pipeline
CREATE INDEX idx_photos_processing_status ON photos(processing_status, created_at)
  WHERE processing_status IS NOT NULL;

-- Partial index for orphan cleanup of pending video uploads (30-min window per Q5)
CREATE INDEX idx_photos_video_orphan ON photos(created_at)
  WHERE media_type = 'video' AND status = 'pending';

-- Partial index for failed video processing cleanup
CREATE INDEX idx_photos_video_failed ON photos(created_at)
  WHERE media_type = 'video' AND status = 'rejected';

COMMIT;
