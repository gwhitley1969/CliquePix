import { queryOne, execute } from './dbService';

/**
 * Clique ownership lifecycle helpers.
 *
 * A clique has two coupled representations of "owner", kept in LOCKSTEP:
 *   - `clique_members.role = 'owner'` — the backend authority (removeMember,
 *     leaveClique, transferOwnership all gate on this).
 *   - `cliques.created_by_user_id` — what the CLIENT reads for its `isOwner`
 *     check. Kept pointing at the current owner so already-installed app builds
 *     (which compute isOwner from this field) keep working.
 *
 * Invariant: every clique with >= 1 member has exactly one `role='owner'`
 * member, and `created_by_user_id` points at that member.
 */

/**
 * Longest-tenured current member of `cliqueId` other than `excludeUserId`, or
 * null if there is no other member. Deterministic (earliest `joined_at`, ties
 * broken by `user_id`) so the choice is stable across the backfill migration,
 * concurrent calls, and tests. Matches the `getMembers` ordering.
 */
export async function selectSuccessorUserId(
  cliqueId: string,
  excludeUserId: string,
): Promise<string | null> {
  const row = await queryOne<{ user_id: string }>(
    `SELECT user_id FROM clique_members
     WHERE clique_id = $1 AND user_id <> $2
     ORDER BY joined_at ASC, user_id ASC
     LIMIT 1`,
    [cliqueId, excludeUserId],
  );
  return row?.user_id ?? null;
}

/**
 * Promote `successorUserId` to owner of `cliqueId` and keep `created_by_user_id`
 * in lockstep. The role UPDATE is a single statement (exactly the successor's
 * row); the `created_by` UPDATE is separate but idempotent, so an interruption
 * between them leaves a functional owner (role set) with at most a stale
 * `created_by` that the backfill / a later transfer re-fixes.
 */
export async function promoteToOwner(
  cliqueId: string,
  successorUserId: string,
): Promise<void> {
  await execute(
    `UPDATE clique_members SET role = 'owner' WHERE clique_id = $1 AND user_id = $2`,
    [cliqueId, successorUserId],
  );
  await execute(
    `UPDATE cliques SET created_by_user_id = $2 WHERE id = $1`,
    [cliqueId, successorUserId],
  );
}
