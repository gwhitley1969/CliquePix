import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { requireActiveEntitlement } from '../shared/middleware/requireActiveEntitlement';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { validateRequiredString } from '../shared/utils/validators';
import { isValidUUID } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
import { Clique, CliqueMember, CliqueWithMemberCount } from '../shared/models/clique';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { enrichUserAvatar } from '../shared/services/avatarEnricher';
import { deleteMediaAssets } from '../shared/services/blobService';
import { selectSuccessorUserId, promoteToOwner, notifyNewOwner } from '../shared/services/cliqueOwnershipService';
import * as crypto from 'crypto';

// Max accepted length when validating an inbound invite code on join. MUST stay
// >= the length generateInviteCode() emits, or sanitizeString() truncates the
// submitted code and the exact-match lookup can never match (joins 404). Keep
// these two in lockstep — inviteCode.test.ts asserts the round-trip.
export const INVITE_CODE_MAX_LENGTH = 64;

export function generateInviteCode(): string {
  // 16 bytes = 128 bits of entropy (32 hex chars). 4 bytes (32 bits) was
  // brute-forceable given no APIM rate limiting + invite-code-only join
  // resolution — an attacker could probabilistically enumerate valid codes to
  // join private cliques. Longer codes are backward-compatible (join resolves
  // by exact match; existing shorter codes keep working).
  return crypto.randomBytes(16).toString('hex');
}

// POST /api/cliques
async function createClique(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const body = await req.json() as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const inviteCode = generateInviteCode();

    const clique = await queryOne<CliqueWithMemberCount>(
      `WITH new_clique AS (
        INSERT INTO cliques (name, invite_code, created_by_user_id)
        VALUES ($1, $2, $3)
        RETURNING *
      ),
      new_member AS (
        INSERT INTO clique_members (clique_id, user_id, role)
        SELECT id, $3, 'owner' FROM new_clique
        RETURNING *
      )
      SELECT nc.*, 1 AS member_count
      FROM new_clique nc`,
      [name, inviteCode, authUser.id],
    );

    trackEvent('clique_created', { cliqueId: clique!.id, userId: authUser.id });

    return successResponse(clique, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/cliques
async function listCliques(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliques = await query<CliqueWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM clique_members WHERE clique_id = c.id) AS member_count
      FROM cliques c
      INNER JOIN clique_members cm ON cm.clique_id = c.id
      WHERE cm.user_id = $1
      ORDER BY c.created_at DESC`,
      [authUser.id],
    );

    return successResponse(cliques);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/cliques/{cliqueId}
async function getClique(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }

    // Check membership and fetch clique in one query
    const clique = await queryOne<CliqueWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM clique_members WHERE clique_id = c.id) AS member_count
      FROM cliques c
      INNER JOIN clique_members cm ON cm.clique_id = c.id AND cm.user_id = $2
      WHERE c.id = $1`,
      [cliqueId, authUser.id],
    );

    if (!clique) {
      throw new NotFoundError('clique');
    }

    return successResponse(clique);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/cliques/{cliqueId}/invite
async function getInviteInfo(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }

    // Verify clique exists and user is a member
    const clique = await queryOne<Clique>(
      `SELECT c.*
      FROM cliques c
      INNER JOIN clique_members cm ON cm.clique_id = c.id AND cm.user_id = $2
      WHERE c.id = $1`,
      [cliqueId, authUser.id],
    );

    if (!clique) {
      throw new NotFoundError('clique');
    }

    return successResponse({
      invite_code: clique.invite_code,
      invite_url: `https://clique-pix.com/invite/${clique.invite_code}`,
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/cliques/{cliqueId}/join
async function joinClique(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const body = await req.json() as Record<string, unknown>;
    // Use INVITE_CODE_MAX_LENGTH (not a bare literal): the previous limit of 20
    // silently truncated every 32-char C1-hardened code via sanitizeString's
    // slice(), so the exact-match lookup below never matched and joins 404'd.
    // Legacy 8-char codes still fit and still match.
    const inviteCode = validateRequiredString(body.invite_code, 'invite_code', INVITE_CODE_MAX_LENGTH);

    // Look up clique by invite code
    const clique = await queryOne<CliqueWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM clique_members WHERE clique_id = c.id) AS member_count
      FROM cliques c
      WHERE c.invite_code = $1`,
      [inviteCode],
    );

    if (!clique) {
      throw new NotFoundError('clique');
    }

    // Check if already a member (idempotent)
    const existingMember = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [clique.id, authUser.id],
    );

    if (existingMember) {
      // Already a member — return success with updated member count
      trackEvent('clique_joined', { cliqueId: clique.id, userId: authUser.id, alreadyMember: 'true' });
      return successResponse(clique);
    }

    // Create membership
    await execute(
      `INSERT INTO clique_members (clique_id, user_id, role) VALUES ($1, $2, 'member')`,
      [clique.id, authUser.id],
    );

    // Re-fetch with updated member count
    const updatedClique = await queryOne<CliqueWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM clique_members WHERE clique_id = c.id) AS member_count
      FROM cliques c
      WHERE c.id = $1`,
      [clique.id],
    );

    // Create in-app notification records for existing members (except joiner).
    // NOTIF-1: independent of push tokens so web-only members (who register no
    // FCM token) still get notified. Own try/catch so a failure can't erase the
    // FCM path below.
    try {
      await execute(
        `INSERT INTO notifications (id, user_id, type, payload_json)
         SELECT gen_random_uuid(), cm.user_id, 'member_joined', $1::jsonb
         FROM clique_members cm
         WHERE cm.clique_id = $2 AND cm.user_id != $3`,
        [JSON.stringify({ clique_id: clique.id, clique_name: clique.name, joined_user_name: authUser.displayName }), clique.id, authUser.id],
      );
    } catch (err) {
      console.error('INSERT notifications for member_joined failed:', err);
    }

    // Send FCM push to existing members who have device tokens.
    const tokens = await query<{ token: string }>(
      `SELECT pt.token FROM push_tokens pt
       JOIN clique_members cm ON cm.user_id = pt.user_id
       WHERE cm.clique_id = $1 AND pt.user_id != $2`,
      [clique.id, authUser.id],
    );

    if (tokens.length > 0) {
      const sendResult = await sendToMultipleTokens(
        tokens.map(t => t.token),
        'New Member!',
        `${authUser.displayName} joined ${clique.name}`,
        { clique_id: clique.id },
      );

      // NOTIF-2: only purge PERMANENTLY-invalid tokens, never transient failures.
      if (sendResult.permanentlyInvalid.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [sendResult.permanentlyInvalid]);
      }

      const successCount = tokens.length - sendResult.totalFailed;
      if (successCount > 0) {
        trackEvent('notification_sent', { cliqueId: clique.id, type: 'member_joined', count: String(successCount) });
      }
    }

    trackEvent('clique_joined', { cliqueId: clique.id, userId: authUser.id });

    return successResponse(updatedClique);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/cliques/{cliqueId}/members
async function listMembers(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }

    // Verify user is a member
    const membership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, authUser.id],
    );

    if (!membership) {
      throw new NotFoundError('clique');
    }

    // Project raw avatar columns (blob paths), then enrich into signed URLs
    // below. Note: u.avatar_url is the legacy (always-null) column from
    // migration 001 — we keep emitting it in the output for one release so
    // old clients don't NPE on a missing field, but the value is always
    // null post-migration 010.
    const members = await query<{
      user_id: string;
      display_name: string;
      avatar_url: string | null;
      avatar_blob_path: string | null;
      avatar_thumb_blob_path: string | null;
      avatar_updated_at: Date | null;
      avatar_frame_preset: number;
      role: string;
      joined_at: Date;
    }>(
      `SELECT u.id AS user_id, u.display_name, u.avatar_url,
              u.avatar_blob_path, u.avatar_thumb_blob_path,
              u.avatar_updated_at, u.avatar_frame_preset,
              cm.role, cm.joined_at
      FROM clique_members cm
      INNER JOIN users u ON u.id = cm.user_id
      WHERE cm.clique_id = $1
      ORDER BY cm.joined_at ASC`,
      [cliqueId],
    );

    const enriched = await Promise.all(
      members.map(async (m) => {
        const avatar = await enrichUserAvatar({
          avatar_blob_path: m.avatar_blob_path,
          avatar_thumb_blob_path: m.avatar_thumb_blob_path,
          avatar_updated_at: m.avatar_updated_at,
          avatar_frame_preset: m.avatar_frame_preset,
        });
        return {
          user_id: m.user_id,
          display_name: m.display_name,
          avatar_url: avatar.avatar_url,
          avatar_thumb_url: avatar.avatar_thumb_url,
          avatar_updated_at: avatar.avatar_updated_at,
          avatar_frame_preset: avatar.avatar_frame_preset,
          role: m.role,
          joined_at: m.joined_at,
        };
      }),
    );

    return successResponse(enriched);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/cliques/{cliqueId}/members/me
async function leaveClique(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }

    // Verify user is a member and get their role
    const membership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, authUser.id],
    );

    if (!membership) {
      throw new NotFoundError('clique');
    }

    // How many members are there right now (including the leaver)?
    const memberCount = await queryOne<{ count: number }>(
      'SELECT COUNT(*)::int AS count FROM clique_members WHERE clique_id = $1',
      [cliqueId],
    );

    if (!memberCount || memberCount.count <= 1) {
      // Last member leaving (ANY role) — the clique (and its events + media rows)
      // is about to be CASCADE-deleted. Blobs are NOT auto-deleted, so enumerate
      // every photo/video across the clique's events and delete their blobs
      // FIRST. Without this, originals + thumbnails + (for videos) the whole
      // HLS/fallback/poster dir orphan in storage forever, since once the rows
      // are gone no cleanup path can ever find them. Mirrors deleteEvent /
      // deleteMe (uses the shared deleteMediaAssets helper). Previously only the
      // sole-OWNER path did this, so an ownerless clique's last member leaving
      // leaked every blob.
      const media = await query<{ blob_path: string; thumbnail_blob_path: string | null; media_type: string }>(
        `SELECT p.blob_path, p.thumbnail_blob_path, p.media_type
         FROM photos p
         JOIN events e ON e.id = p.event_id
         WHERE e.clique_id = $1 AND p.status IN ('active', 'pending')`,
        [cliqueId],
      );
      let blobCleanupFailures = 0;
      for (const m of media) {
        try {
          await deleteMediaAssets(m);
        } catch (err) {
          blobCleanupFailures++;
          context.error(`Failed to delete media assets while deleting clique ${cliqueId}:`, err);
        }
      }

      await execute('DELETE FROM cliques WHERE id = $1', [cliqueId]);

      trackEvent('clique_left', {
        cliqueId,
        userId: authUser.id,
        cliqueDeleted: 'true',
        mediaBlobsDeleted: String(media.length - blobCleanupFailures),
        mediaBlobCleanupFailures: String(blobCleanupFailures),
      });

      return successResponse({ message: 'Clique deleted.' });
    }

    // Other members remain. If the leaver is the owner, auto-promote the
    // longest-tenured remaining member so the clique is never left ownerless.
    // (An owner used to be hard-blocked with "Transfer ownership before
    // leaving." — but no transfer endpoint existed, so they were stuck and
    // deleting their account was the only exit, which orphaned the clique.)
    // Explicit hand-off via POST /cliques/{id}/transfer-ownership remains
    // available; this is the no-friction fallback.
    if (membership.role === 'owner') {
      const successor = await selectSuccessorUserId(cliqueId, authUser.id);
      if (successor) {
        await promoteToOwner(cliqueId, successor);
        await notifyNewOwner(cliqueId, successor);
        trackEvent('clique_ownership_transferred', {
          cliqueId,
          from: authUser.id,
          to: successor,
          reason: 'owner_left',
        });
      }
    }

    // Remove the leaver's membership.
    await execute(
      'DELETE FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, authUser.id],
    );

    // Mark DM threads involving leaving user as read-only
    await execute(
      `UPDATE event_dm_threads SET status = 'read_only'
       WHERE event_id IN (SELECT id FROM events WHERE clique_id = $1)
       AND (user_a_id = $2 OR user_b_id = $2)
       AND status = 'active'`,
      [cliqueId, authUser.id],
    );

    trackEvent('clique_left', { cliqueId, userId: authUser.id });

    return successResponse({ message: 'You have left the clique.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/cliques/{cliqueId}/members/{userId}
async function removeMember(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    const userId = req.params.userId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }
    if (!userId || !isValidUUID(userId)) {
      throw new ValidationError('A valid user ID is required.');
    }

    // Verify the requester is the clique owner
    const ownerMembership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, authUser.id],
    );

    if (!ownerMembership || ownerMembership.role !== 'owner') {
      throw new ForbiddenError('Only the clique owner can remove members.');
    }

    // Prevent owner from removing themselves via this endpoint
    if (userId === authUser.id) {
      throw new ValidationError('Use the leave endpoint to remove yourself.');
    }

    // Verify the target user is a member
    const targetMembership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, userId],
    );

    if (!targetMembership) {
      throw new NotFoundError('member');
    }

    // Remove the member
    await execute(
      'DELETE FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, userId],
    );

    // Mark DM threads involving removed user as read-only
    await execute(
      `UPDATE event_dm_threads SET status = 'read_only'
       WHERE event_id IN (SELECT id FROM events WHERE clique_id = $1)
       AND (user_a_id = $2 OR user_b_id = $2)
       AND status = 'active'`,
      [cliqueId, userId],
    );

    trackEvent('member_removed', { cliqueId, removedUserId: userId, removedBy: authUser.id });

    return successResponse({ message: 'Member removed.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/cliques/{cliqueId}/transfer-ownership
export async function transferOwnership(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    requireActiveEntitlement(authUser);

    const cliqueId = req.params.cliqueId;
    if (!cliqueId || !isValidUUID(cliqueId)) {
      throw new ValidationError('A valid clique ID is required.');
    }

    const body = await req.json() as Record<string, unknown>;
    const targetUserId = body.user_id;
    if (typeof targetUserId !== 'string' || !isValidUUID(targetUserId)) {
      throw new ValidationError('A valid user_id is required.');
    }

    // Caller must be the current owner.
    const ownerMembership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, authUser.id],
    );
    if (!ownerMembership || ownerMembership.role !== 'owner') {
      throw new ForbiddenError('Only the clique owner can transfer ownership.');
    }
    if (targetUserId === authUser.id) {
      throw new ValidationError('You already own this clique.');
    }

    // Target must be a current member.
    const targetMembership = await queryOne<CliqueMember>(
      'SELECT * FROM clique_members WHERE clique_id = $1 AND user_id = $2',
      [cliqueId, targetUserId],
    );
    if (!targetMembership) {
      throw new NotFoundError('member');
    }

    // Atomic role swap in a single statement — no window where the clique has
    // zero or two owners.
    await execute(
      `UPDATE clique_members
       SET role = CASE WHEN user_id = $2 THEN 'member' WHEN user_id = $3 THEN 'owner' END
       WHERE clique_id = $1 AND user_id IN ($2, $3)`,
      [cliqueId, authUser.id, targetUserId],
    );
    // Keep created_by_user_id in lockstep so the client recognizes the new owner.
    await execute('UPDATE cliques SET created_by_user_id = $2 WHERE id = $1', [cliqueId, targetUserId]);

    await notifyNewOwner(cliqueId, targetUserId);

    trackEvent('clique_ownership_transferred', {
      cliqueId,
      from: authUser.id,
      to: targetUserId,
      reason: 'explicit',
    });

    return successResponse({ message: 'Ownership transferred.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// Register all endpoints
app.http('createClique', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'cliques',
  handler: createClique,
});

app.http('listCliques', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'cliques',
  handler: listCliques,
});

app.http('getClique', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}',
  handler: getClique,
});

app.http('getInviteInfo', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/invite',
  handler: getInviteInfo,
});

app.http('joinClique', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/join',
  handler: joinClique,
});

app.http('listMembers', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/members',
  handler: listMembers,
});

app.http('leaveClique', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/members/me',
  handler: leaveClique,
});

app.http('removeMember', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/members/{userId}',
  handler: removeMember,
});

app.http('transferOwnership', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'cliques/{cliqueId}/transfer-ownership',
  handler: transferOwnership,
});
