-- 014_clique_ownership_backfill.sql
--
-- Restore the clique ownership invariant for existing data:
--   every clique with >= 1 member has exactly one role='owner' member, and
--   cliques.created_by_user_id points at that member.
--
-- Heals cliques orphaned when a creator deleted their account: migration 004
-- SET NULLs cliques.created_by_user_id and the owner's clique_members row is
-- CASCADE-deleted (migration 001), leaving members but zero owners. Going
-- forward, deleteMe / leaveClique auto-promote so no new orphans are created.
--
-- Successor = longest-tenured member (earliest joined_at, ties by user_id),
-- matching selectSuccessorUserId() and the getMembers ordering.
-- Idempotent: re-running is a no-op once the invariant holds.
--
-- NOTE: empty cliques (0 members) with a null creator are NOT touched here —
-- their event-media BLOBS can't be deleted from SQL. Detect them with the
-- verification query at the bottom; if any exist, clean via a one-off TS script
-- reusing deleteMediaAssets (mirror auth.ts deleteMe).

BEGIN;

-- (A) Cliques that have members but NO owner: promote the longest-tenured member.
WITH ownerless AS (
  SELECT c.id AS clique_id
  FROM cliques c
  WHERE EXISTS (SELECT 1 FROM clique_members m WHERE m.clique_id = c.id)
    AND NOT EXISTS (SELECT 1 FROM clique_members m WHERE m.clique_id = c.id AND m.role = 'owner')
),
successor AS (
  SELECT DISTINCT ON (cm.clique_id) cm.clique_id, cm.user_id
  FROM clique_members cm
  JOIN ownerless o ON o.clique_id = cm.clique_id
  ORDER BY cm.clique_id, cm.joined_at ASC, cm.user_id ASC
)
UPDATE clique_members cm
SET role = 'owner'
FROM successor s
WHERE cm.clique_id = s.clique_id AND cm.user_id = s.user_id;

-- (B) Lockstep repair: point created_by_user_id at the current owner wherever it
--     is null or out of sync (covers both the freshly-promoted cliques from (A)
--     and any clique whose creator was deleted after transferring ownership).
UPDATE cliques c
SET created_by_user_id = o.user_id
FROM (
  SELECT DISTINCT ON (clique_id) clique_id, user_id
  FROM clique_members
  WHERE role = 'owner'
  ORDER BY clique_id, joined_at ASC, user_id ASC
) o
WHERE c.id = o.clique_id
  AND c.created_by_user_id IS DISTINCT FROM o.user_id;

COMMIT;

-- Verification (run manually after applying):
--   -- expect 0 rows: cliques with members but no owner
--   SELECT c.id FROM cliques c
--   WHERE EXISTS (SELECT 1 FROM clique_members m WHERE m.clique_id = c.id)
--     AND NOT EXISTS (SELECT 1 FROM clique_members m WHERE m.clique_id = c.id AND m.role='owner');
--   -- empty null-creator cliques needing TS blob cleanup (handle separately if any):
--   SELECT c.id FROM cliques c
--   WHERE c.created_by_user_id IS NULL
--     AND NOT EXISTS (SELECT 1 FROM clique_members m WHERE m.clique_id = c.id);
