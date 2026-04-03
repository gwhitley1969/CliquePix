-- Make creator/uploader FKs nullable with ON DELETE SET NULL
-- Required for account deletion: preserves shared circles/events/photos when user deletes account

-- circles.created_by_user_id → SET NULL
ALTER TABLE circles ALTER COLUMN created_by_user_id DROP NOT NULL;
ALTER TABLE circles DROP CONSTRAINT circles_created_by_user_id_fkey;
ALTER TABLE circles ADD CONSTRAINT circles_created_by_user_id_fkey
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- events.created_by_user_id → SET NULL
ALTER TABLE events ALTER COLUMN created_by_user_id DROP NOT NULL;
ALTER TABLE events DROP CONSTRAINT events_created_by_user_id_fkey;
ALTER TABLE events ADD CONSTRAINT events_created_by_user_id_fkey
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- photos.uploaded_by_user_id → SET NULL
ALTER TABLE photos ALTER COLUMN uploaded_by_user_id DROP NOT NULL;
ALTER TABLE photos DROP CONSTRAINT photos_uploaded_by_user_id_fkey;
ALTER TABLE photos ADD CONSTRAINT photos_uploaded_by_user_id_fkey
  FOREIGN KEY (uploaded_by_user_id) REFERENCES users(id) ON DELETE SET NULL;
