import { query, queryOne, execute } from './dbService';
import { sendToMultipleTokens } from './fcmService';

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

/**
 * Notify the NEW owner of `cliqueId` that they now own it — used by all three
 * ownership-change paths (explicit transfer, owner-leave auto-promote,
 * account-deletion auto-promote), so a member who gets handed ownership isn't
 * surprised. Writes an in-app `clique_ownership_transferred` row (independent of
 * push tokens, so web-only users get it) + an FCM push to their devices.
 *
 * BEST-EFFORT: fully wrapped so a notification failure can NEVER break the
 * ownership change itself (which has already been committed by the caller).
 */
export async function notifyNewOwner(
  cliqueId: string,
  newOwnerUserId: string,
): Promise<void> {
  try {
    const clique = await queryOne<{ name: string }>(
      'SELECT name FROM cliques WHERE id = $1',
      [cliqueId],
    );
    const cliqueName = clique?.name ?? 'a clique';

    await execute(
      `INSERT INTO notifications (id, user_id, type, payload_json)
       VALUES (gen_random_uuid(), $1, 'clique_ownership_transferred', $2::jsonb)`,
      [newOwnerUserId, JSON.stringify({ clique_id: cliqueId, clique_name: cliqueName })],
    );

    const tokens = await query<{ token: string }>(
      'SELECT token FROM push_tokens WHERE user_id = $1',
      [newOwnerUserId],
    );
    if (tokens.length > 0) {
      const sendResult = await sendToMultipleTokens(
        tokens.map((t) => t.token),
        "You're now an owner",
        `You're now the owner of ${cliqueName}`,
        { clique_id: cliqueId },
      );
      // Only purge PERMANENTLY-invalid tokens (NOTIF-2), never transient failures.
      if (sendResult.permanentlyInvalid.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [sendResult.permanentlyInvalid]);
      }
    }
  } catch (err) {
    // Never let a notification failure surface to the ownership-change caller.
    console.error('notifyNewOwner failed:', err);
  }
}
