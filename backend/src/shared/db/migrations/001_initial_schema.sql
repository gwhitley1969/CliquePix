-- CliquePix Initial Schema
-- Execute against pg-cliquepix (East US 2)
-- Database: cliquepix

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- Helper: updated_at trigger function
-- =============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- users
-- =============================================================================
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_auth_id TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  email_or_phone TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- circles
-- =============================================================================
CREATE TABLE circles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  created_by_user_id UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_circles_invite_code ON circles(invite_code);

CREATE TRIGGER circles_updated_at
  BEFORE UPDATE ON circles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- circle_members
-- =============================================================================
CREATE TABLE circle_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'member')) DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (circle_id, user_id)
);

CREATE INDEX idx_circle_members_user_id ON circle_members(user_id);
CREATE INDEX idx_circle_members_circle_id ON circle_members(circle_id);

-- =============================================================================
-- events
-- =============================================================================
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  created_by_user_id UUID NOT NULL REFERENCES users(id),
  retention_hours INTEGER NOT NULL CHECK (retention_hours IN (24, 72, 168)),
  status TEXT NOT NULL CHECK (status IN ('active', 'expired')) DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_events_circle_id ON events(circle_id);
CREATE INDEX idx_events_status ON events(status);
CREATE INDEX idx_events_expires_at ON events(expires_at);

-- =============================================================================
-- photos
-- =============================================================================
CREATE TABLE photos (
  id UUID PRIMARY KEY, -- NOT auto-generated; set by server at upload-url step
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  uploaded_by_user_id UUID NOT NULL REFERENCES users(id),
  blob_path TEXT NOT NULL,
  thumbnail_blob_path TEXT,
  original_filename TEXT,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
  width INTEGER,
  height INTEGER,
  file_size_bytes BIGINT,
  status TEXT NOT NULL CHECK (status IN ('pending', 'active', 'deleted')) DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_photos_event_id ON photos(event_id);
CREATE INDEX idx_photos_status_expires ON photos(status, expires_at);
CREATE INDEX idx_photos_status_created ON photos(status, created_at);

-- =============================================================================
-- reactions
-- =============================================================================
CREATE TABLE reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id UUID NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reaction_type TEXT NOT NULL CHECK (reaction_type IN ('heart', 'laugh', 'fire', 'wow')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (photo_id, user_id, reaction_type)
);

CREATE INDEX idx_reactions_photo_id ON reactions(photo_id);

-- =============================================================================
-- push_tokens
-- =============================================================================
CREATE TABLE push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_push_tokens_user_id ON push_tokens(user_id);

CREATE TRIGGER push_tokens_updated_at
  BEFORE UPDATE ON push_tokens
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- notifications
-- =============================================================================
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('new_photo', 'event_expiring', 'event_expired')),
  payload_json JSONB NOT NULL DEFAULT '{}',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
