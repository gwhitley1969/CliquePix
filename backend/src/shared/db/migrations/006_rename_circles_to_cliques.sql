-- Rename "circles" to "cliques" throughout the schema
-- Competitor uses "Circle" branding; differentiating with "Clique"

BEGIN;

-- =============================================================================
-- Rename tables
-- =============================================================================
ALTER TABLE circles RENAME TO cliques;
ALTER TABLE circle_members RENAME TO clique_members;

-- =============================================================================
-- Rename columns
-- =============================================================================
ALTER TABLE clique_members RENAME COLUMN circle_id TO clique_id;
ALTER TABLE events RENAME COLUMN circle_id TO clique_id;

-- =============================================================================
-- Rename indexes
-- =============================================================================
ALTER INDEX idx_circles_invite_code RENAME TO idx_cliques_invite_code;
ALTER INDEX idx_circle_members_user_id RENAME TO idx_clique_members_user_id;
ALTER INDEX idx_circle_members_circle_id RENAME TO idx_clique_members_clique_id;
ALTER INDEX idx_events_circle_id RENAME TO idx_events_clique_id;

-- =============================================================================
-- Rename triggers
-- =============================================================================
ALTER TRIGGER circles_updated_at ON cliques RENAME TO cliques_updated_at;

-- =============================================================================
-- Rename FK constraints (dropped/re-added in migration 004)
-- =============================================================================
ALTER TABLE cliques RENAME CONSTRAINT circles_created_by_user_id_fkey TO cliques_created_by_user_id_fkey;

-- =============================================================================
-- Update existing notification payloads with old circle_id/circle_name keys
-- =============================================================================
UPDATE notifications SET payload_json =
  REPLACE(REPLACE(payload_json::text, '"circle_id"', '"clique_id"'), '"circle_name"', '"clique_name"')::jsonb
  WHERE payload_json::text LIKE '%"circle_%';

COMMIT;
