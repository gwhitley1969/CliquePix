import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse, errorResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { validateRequiredString } from '../shared/utils/validators';
import { isValidUUID } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ConflictError, ValidationError } from '../shared/utils/errors';
import { Circle, CircleMember, CircleWithMemberCount } from '../shared/models/circle';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import * as crypto from 'crypto';

function generateInviteCode(): string {
  return crypto.randomBytes(4).toString('hex'); // 8 alphanumeric chars
}

// POST /api/circles
async function createCircle(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const body = await req.json() as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const inviteCode = generateInviteCode();

    const circle = await queryOne<CircleWithMemberCount>(
      `WITH new_circle AS (
        INSERT INTO circles (name, invite_code, created_by_user_id)
        VALUES ($1, $2, $3)
        RETURNING *
      ),
      new_member AS (
        INSERT INTO circle_members (circle_id, user_id, role)
        SELECT id, $3, 'owner' FROM new_circle
        RETURNING *
      )
      SELECT nc.*, 1 AS member_count
      FROM new_circle nc`,
      [name, inviteCode, authUser.id],
    );

    trackEvent('circle_created', { circleId: circle!.id, userId: authUser.id });

    return successResponse(circle, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/circles
async function listCircles(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circles = await query<CircleWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM circle_members WHERE circle_id = c.id) AS member_count
      FROM circles c
      INNER JOIN circle_members cm ON cm.circle_id = c.id
      WHERE cm.user_id = $1
      ORDER BY c.created_at DESC`,
      [authUser.id],
    );

    return successResponse(circles);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/circles/{circleId}
async function getCircle(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circleId = req.params.circleId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Check membership and fetch circle in one query
    const circle = await queryOne<CircleWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM circle_members WHERE circle_id = c.id) AS member_count
      FROM circles c
      INNER JOIN circle_members cm ON cm.circle_id = c.id AND cm.user_id = $2
      WHERE c.id = $1`,
      [circleId, authUser.id],
    );

    if (!circle) {
      throw new NotFoundError('circle');
    }

    return successResponse(circle);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/circles/{circleId}/invite
async function getInviteInfo(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circleId = req.params.circleId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Verify circle exists and user is a member
    const circle = await queryOne<Circle>(
      `SELECT c.*
      FROM circles c
      INNER JOIN circle_members cm ON cm.circle_id = c.id AND cm.user_id = $2
      WHERE c.id = $1`,
      [circleId, authUser.id],
    );

    if (!circle) {
      throw new NotFoundError('circle');
    }

    return successResponse({
      invite_code: circle.invite_code,
      invite_url: `https://clique-pix.com/invite/${circle.invite_code}`,
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/circles/{circleId}/join
async function joinCircle(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const body = await req.json() as Record<string, unknown>;
    const inviteCode = validateRequiredString(body.invite_code, 'invite_code', 20);

    // Look up circle by invite code
    const circle = await queryOne<CircleWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM circle_members WHERE circle_id = c.id) AS member_count
      FROM circles c
      WHERE c.invite_code = $1`,
      [inviteCode],
    );

    if (!circle) {
      throw new NotFoundError('circle');
    }

    // Check if already a member (idempotent)
    const existingMember = await queryOne<CircleMember>(
      'SELECT * FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circle.id, authUser.id],
    );

    if (existingMember) {
      // Already a member — return success with updated member count
      trackEvent('circle_joined', { circleId: circle.id, userId: authUser.id, alreadyMember: 'true' });
      return successResponse(circle);
    }

    // Create membership
    await execute(
      `INSERT INTO circle_members (circle_id, user_id, role) VALUES ($1, $2, 'member')`,
      [circle.id, authUser.id],
    );

    // Re-fetch with updated member count
    const updatedCircle = await queryOne<CircleWithMemberCount>(
      `SELECT c.*,
        (SELECT COUNT(*)::int FROM circle_members WHERE circle_id = c.id) AS member_count
      FROM circles c
      WHERE c.id = $1`,
      [circle.id],
    );

    // Send push notifications to existing circle members
    const tokens = await query<{ token: string }>(
      `SELECT pt.token FROM push_tokens pt
       JOIN circle_members cm ON cm.user_id = pt.user_id
       WHERE cm.circle_id = $1 AND pt.user_id != $2`,
      [circle.id, authUser.id],
    );

    if (tokens.length > 0) {
      const failedTokens = await sendToMultipleTokens(
        tokens.map(t => t.token),
        'New Member!',
        `${authUser.displayName} joined ${circle.name}`,
        { circle_id: circle.id },
      );

      await execute(
        `INSERT INTO notifications (id, user_id, type, payload_json)
         SELECT gen_random_uuid(), cm.user_id, 'member_joined', $1::jsonb
         FROM circle_members cm
         WHERE cm.circle_id = $2 AND cm.user_id != $3`,
        [JSON.stringify({ circle_id: circle.id, circle_name: circle.name, joined_user_name: authUser.displayName }), circle.id, authUser.id],
      );

      if (failedTokens.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failedTokens]);
      }

      const successCount = tokens.length - failedTokens.length;
      if (successCount > 0) {
        trackEvent('notification_sent', { circleId: circle.id, type: 'member_joined', count: String(successCount) });
      }
    }

    trackEvent('circle_joined', { circleId: circle.id, userId: authUser.id });

    return successResponse(updatedCircle);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/circles/{circleId}/members
async function listMembers(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circleId = req.params.circleId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Verify user is a member
    const membership = await queryOne<CircleMember>(
      'SELECT * FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, authUser.id],
    );

    if (!membership) {
      throw new NotFoundError('circle');
    }

    const members = await query<{
      user_id: string;
      display_name: string;
      avatar_url: string | null;
      role: string;
      joined_at: Date;
    }>(
      `SELECT u.id AS user_id, u.display_name, u.avatar_url, cm.role, cm.joined_at
      FROM circle_members cm
      INNER JOIN users u ON u.id = cm.user_id
      WHERE cm.circle_id = $1
      ORDER BY cm.joined_at ASC`,
      [circleId],
    );

    return successResponse(members);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/circles/{circleId}/members/me
async function leaveCircle(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circleId = req.params.circleId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Verify user is a member and get their role
    const membership = await queryOne<CircleMember>(
      'SELECT * FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, authUser.id],
    );

    if (!membership) {
      throw new NotFoundError('circle');
    }

    if (membership.role === 'owner') {
      // Check if there are other members
      const memberCount = await queryOne<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM circle_members WHERE circle_id = $1',
        [circleId],
      );

      if (memberCount && memberCount.count > 1) {
        throw new ForbiddenError('Transfer ownership before leaving.');
      }

      // Owner is the only member — delete the circle (cascade deletes memberships)
      await execute('DELETE FROM circles WHERE id = $1', [circleId]);

      trackEvent('circle_left', { circleId, userId: authUser.id, circleDeleted: 'true' });

      return successResponse({ message: 'Circle deleted.' });
    }

    // Regular member — remove membership
    await execute(
      'DELETE FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, authUser.id],
    );

    trackEvent('circle_left', { circleId, userId: authUser.id });

    return successResponse({ message: 'You have left the circle.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/circles/{circleId}/members/{userId}
async function removeMember(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const circleId = req.params.circleId;
    const userId = req.params.userId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }
    if (!userId || !isValidUUID(userId)) {
      throw new ValidationError('A valid user ID is required.');
    }

    // Verify the requester is the circle owner
    const ownerMembership = await queryOne<CircleMember>(
      'SELECT * FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, authUser.id],
    );

    if (!ownerMembership || ownerMembership.role !== 'owner') {
      throw new ForbiddenError('Only the circle owner can remove members.');
    }

    // Prevent owner from removing themselves via this endpoint
    if (userId === authUser.id) {
      throw new ValidationError('Use the leave endpoint to remove yourself.');
    }

    // Verify the target user is a member
    const targetMembership = await queryOne<CircleMember>(
      'SELECT * FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, userId],
    );

    if (!targetMembership) {
      throw new NotFoundError('member');
    }

    // Remove the member
    await execute(
      'DELETE FROM circle_members WHERE circle_id = $1 AND user_id = $2',
      [circleId, userId],
    );

    trackEvent('member_removed', { circleId, removedUserId: userId, removedBy: authUser.id });

    return successResponse({ message: 'Member removed.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// Register all endpoints
app.http('createCircle', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'circles',
  handler: createCircle,
});

app.http('listCircles', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'circles',
  handler: listCircles,
});

app.http('getCircle', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}',
  handler: getCircle,
});

app.http('getInviteInfo', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/invite',
  handler: getInviteInfo,
});

app.http('joinCircle', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/join',
  handler: joinCircle,
});

app.http('listMembers', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/members',
  handler: listMembers,
});

app.http('leaveCircle', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/members/me',
  handler: leaveCircle,
});

app.http('removeMember', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/members/{userId}',
  handler: removeMember,
});
