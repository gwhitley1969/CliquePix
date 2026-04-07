-- Event DM threads (1:1 only, read state inlined on thread row)
-- user_a_id < user_b_id enforced by CHECK constraint to prevent duplicate threads
CREATE TABLE event_dm_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('active', 'read_only')) DEFAULT 'active',
  user_a_last_read_message_id UUID NULL,
  user_b_last_read_message_id UUID NULL,
  last_message_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_dm_thread_event_users UNIQUE (event_id, user_a_id, user_b_id),
  CONSTRAINT ck_dm_thread_user_order CHECK (user_a_id < user_b_id)
);

-- Event DM messages
CREATE TABLE event_dm_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID NOT NULL REFERENCES event_dm_threads(id) ON DELETE CASCADE,
  sender_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  body TEXT NOT NULL CHECK (length(trim(body)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_dm_threads_event_id ON event_dm_threads(event_id);
CREATE INDEX idx_dm_threads_user_a ON event_dm_threads(user_a_id);
CREATE INDEX idx_dm_threads_user_b ON event_dm_threads(user_b_id);
CREATE INDEX idx_dm_messages_thread_created ON event_dm_messages(thread_id, created_at DESC);
