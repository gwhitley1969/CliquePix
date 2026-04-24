import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
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
import * as crypto from 'crypto';

function generateInviteCode(): string {
  return crypto.randomBytes(4).toString('hex'); // 8 alphanumeric chars
}

// POST /api/cliques
async function createClique(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

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

    const body = await req.json() as Record<string, unknown>;
    const inviteCode = validateRequiredString(body.invite_code, 'invite_code', 20);

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

    // Send push notifications to existing clique members
    const tokens = await query<{ token: string }>(
      `SELECT pt.token FROM push_tokens pt
       JOIN clique_members cm ON cm.user_id = pt.user_id
       WHERE cm.clique_id = $1 AND pt.user_id != $2`,
      [clique.id, authUser.id],
    );

    if (tokens.length > 0) {
      const failedTokens = await sendToMultipleTokens(
        tokens.map(t => t.token),
        'New Member!',
        `${authUser.displayName} joined ${clique.name}`,
        { clique_id: clique.id },
      );

      await execute(
        `INSERT INTO notifications (id, user_id, type, payload_json)
         SELECT gen_random_uuid(), cm.user_id, 'member_joined', $1::jsonb
         FROM clique_members cm
         WHERE cm.clique_id = $2 AND cm.user_id != $3`,
        [JSON.stringify({ clique_id: clique.id, clique_name: clique.name, joined_user_name: authUser.displayName }), clique.id, authUser.id],
      );

      if (failedTokens.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failedTokens]);
      }

      const successCount = tokens.length - failedTokens.length;
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

    if (membership.role === 'owner') {
      // Check if there are other members
      const memberCount = await queryOne<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM clique_members WHERE clique_id = $1',
        [cliqueId],
      );

      if (memberCount && memberCount.count > 1) {
        throw new ForbiddenError('Transfer ownership before leaving.');
      }

      // Owner is the only member — delete the clique (cascade deletes memberships)
      await execute('DELETE FROM cliques WHERE id = $1', [cliqueId]);

      trackEvent('clique_left', { cliqueId, userId: authUser.id, cliqueDeleted: 'true' });

      return successResponse({ message: 'Clique deleted.' });
    }

    // Regular member — remove membership
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
