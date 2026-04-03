import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { isValidUUID, validateRequiredString } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
import { publishToThread, getClientAccessToken, addUserToThreadGroup } from '../shared/services/webPubSubService';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { DmThread, DmMessage } from '../shared/models/dmThread';

// Normalize user IDs so user_a < user_b (prevents duplicate threads)
function normalizeUserPair(id1: string, id2: string): { userA: string; userB: string } {
  return id1 < id2 ? { userA: id1, userB: id2 } : { userA: id2, userB: id1 };
}

// Verify user is a participant in the thread
function isParticipant(thread: DmThread, userId: string): boolean {
  return thread.user_a_id === userId || thread.user_b_id === userId;
}

// Get the other user's ID from a thread
function getOtherUserId(thread: DmThread, userId: string): string {
  return thread.user_a_id === userId ? thread.user_b_id : thread.user_a_id;
}

// ─── Create or Get DM Thread ───────────────────────────────────────────────────

async function createOrGetDmThread(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const eventId = req.params.eventId;

    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const body = (await req.json()) as Record<string, unknown>;
    const targetUserId = body.target_user_id as string;
    if (!targetUserId || !isValidUUID(targetUserId)) {
      throw new ValidationError('A valid target_user_id is required.');
    }

    if (targetUserId === authUser.id) {
      throw new ValidationError('Cannot create a DM thread with yourself.');
    }

    // Verify event exists and is active
    const event = await queryOne<{ id: string; circle_id: string; status: string }>(
      'SELECT id, circle_id, status FROM events WHERE id = $1',
      [eventId],
    );
    if (!event) throw new NotFoundError('event');
    if (event.status !== 'active') throw new ValidationError('Cannot create DM threads for expired events.');

    // Verify both users are circle members
    const memberCount = await queryOne<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM circle_members
       WHERE circle_id = $1 AND user_id IN ($2, $3)`,
      [event.circle_id, authUser.id, targetUserId],
    );
    if (!memberCount || memberCount.count < 2) {
      throw new ForbiddenError('Both users must be members of the event\'s circle.');
    }

    const { userA, userB } = normalizeUserPair(authUser.id, targetUserId);

    // Try to find existing thread
    let thread = await queryOne<DmThread>(
      'SELECT * FROM event_dm_threads WHERE event_id = $1 AND user_a_id = $2 AND user_b_id = $3',
      [eventId, userA, userB],
    );

    if (!thread) {
      thread = await queryOne<DmThread>(
        `INSERT INTO event_dm_threads (event_id, user_a_id, user_b_id)
         VALUES ($1, $2, $3)
         RETURNING *`,
        [eventId, userA, userB],
      );
      trackEvent('dm_thread_created', { eventId, threadId: thread!.id, userId: authUser.id });
    }

    // Get other user's display name
    const otherUser = await queryOne<{ display_name: string }>(
      'SELECT display_name FROM users WHERE id = $1',
      [getOtherUserId(thread!, authUser.id)],
    );

    return successResponse({
      ...thread,
      other_user_id: getOtherUserId(thread!, authUser.id),
      other_user_name: otherUser?.display_name ?? 'User',
    }, thread ? 200 : 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── List DM Threads for Event ─────────────────────────────────────────────────

async function listDmThreads(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const eventId = req.params.eventId;

    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const threads = await query<any>(
      `SELECT t.*,
              CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END AS other_user_id,
              CASE WHEN t.user_a_id = $2 THEN ub.display_name ELSE ua.display_name END AS other_user_name,
              (SELECT body FROM event_dm_messages WHERE thread_id = t.id ORDER BY created_at DESC LIMIT 1) AS last_message_preview,
              (SELECT COUNT(*)::int FROM event_dm_messages m
               WHERE m.thread_id = t.id
               AND m.created_at > COALESCE(
                 (SELECT created_at FROM event_dm_messages WHERE id =
                   CASE WHEN $2 = t.user_a_id THEN t.user_a_last_read_message_id
                        ELSE t.user_b_last_read_message_id END
                 ), t.created_at
               )
              ) AS unread_count
       FROM event_dm_threads t
       JOIN users ua ON ua.id = t.user_a_id
       JOIN users ub ON ub.id = t.user_b_id
       WHERE t.event_id = $1
       AND (t.user_a_id = $2 OR t.user_b_id = $2)
       ORDER BY t.last_message_at DESC NULLS LAST`,
      [eventId, authUser.id],
    );

    return successResponse(threads);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── Get DM Thread ─────────────────────────────────────────────────────────────

async function getDmThread(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const threadId = req.params.threadId;

    if (!threadId || !isValidUUID(threadId)) {
      throw new ValidationError('A valid thread ID is required.');
    }

    const thread = await queryOne<DmThread>(
      'SELECT * FROM event_dm_threads WHERE id = $1',
      [threadId],
    );
    if (!thread) throw new NotFoundError('thread');
    if (!isParticipant(thread, authUser.id)) throw new ForbiddenError();

    const otherUser = await queryOne<{ display_name: string }>(
      'SELECT display_name FROM users WHERE id = $1',
      [getOtherUserId(thread, authUser.id)],
    );

    // Add user to Web PubSub thread group for real-time delivery
    try {
      await addUserToThreadGroup(threadId, authUser.id);
    } catch (_) {
      // Non-fatal — real-time delivery will fall back to FCM
    }

    return successResponse({
      ...thread,
      other_user_id: getOtherUserId(thread, authUser.id),
      other_user_name: otherUser?.display_name ?? 'User',
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── List DM Messages ──────────────────────────────────────────────────────────

async function listDmMessages(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const threadId = req.params.threadId;

    if (!threadId || !isValidUUID(threadId)) {
      throw new ValidationError('A valid thread ID is required.');
    }

    const thread = await queryOne<DmThread>(
      'SELECT * FROM event_dm_threads WHERE id = $1',
      [threadId],
    );
    if (!thread) throw new NotFoundError('thread');
    if (!isParticipant(thread, authUser.id)) throw new ForbiddenError();

    const limit = Math.min(parseInt(req.query.get('limit') || '50', 10), 100);
    const cursor = req.query.get('cursor');

    let sql = `SELECT m.*, u.display_name AS sender_name
               FROM event_dm_messages m
               LEFT JOIN users u ON u.id = m.sender_user_id
               WHERE m.thread_id = $1`;
    const params: unknown[] = [threadId];

    if (cursor) {
      sql += ' AND m.created_at < $2';
      params.push(cursor);
    }

    sql += ' ORDER BY m.created_at DESC LIMIT $' + (params.length + 1);
    params.push(limit);

    const messages = await query<any>(sql, params);
    const nextCursor = messages.length === limit
      ? messages[messages.length - 1].created_at.toISOString()
      : null;

    return successResponse({ messages, next_cursor: nextCursor });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── Send DM Message ───────────────────────────────────────────────────────────

async function sendDmMessage(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const threadId = req.params.threadId;

    if (!threadId || !isValidUUID(threadId)) {
      throw new ValidationError('A valid thread ID is required.');
    }

    const thread = await queryOne<DmThread>(
      'SELECT * FROM event_dm_threads WHERE id = $1',
      [threadId],
    );
    if (!thread) throw new NotFoundError('thread');
    if (!isParticipant(thread, authUser.id)) throw new ForbiddenError();
    if (thread.status !== 'active') {
      throw new ValidationError('This chat is read-only because the event has ended.');
    }

    const reqBody = (await req.json()) as Record<string, unknown>;
    const body = validateRequiredString(reqBody.body, 'body', 2000);

    // Rate limit: max 10 messages per minute per sender per thread
    const recentCount = await queryOne<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM event_dm_messages
       WHERE thread_id = $1 AND sender_user_id = $2 AND created_at > NOW() - interval '1 minute'`,
      [threadId, authUser.id],
    );
    if (recentCount && recentCount.count >= 10) {
      return {
        status: 429,
        jsonBody: { data: null, error: { code: 'RATE_LIMITED', message: 'Too many messages. Please wait a moment.' } },
        headers: { 'Content-Type': 'application/json' },
      };
    }

    // Insert message
    const message = await queryOne<DmMessage>(
      `INSERT INTO event_dm_messages (thread_id, sender_user_id, body)
       VALUES ($1, $2, $3) RETURNING *`,
      [threadId, authUser.id, body],
    );

    // Update thread last_message_at
    await execute(
      'UPDATE event_dm_threads SET last_message_at = $1 WHERE id = $2',
      [message!.created_at, threadId],
    );

    // Publish to Web PubSub for real-time delivery
    try {
      await publishToThread(threadId, {
        type: 'dm_message_created',
        thread_id: threadId,
        event_id: thread.event_id,
        message: {
          id: message!.id,
          thread_id: threadId,
          sender_user_id: authUser.id,
          sender_name: authUser.displayName,
          body,
          created_at: message!.created_at,
        },
      });
    } catch (_) {
      // Non-fatal — recipient will get FCM or fetch on next load
    }

    // Always send FCM push in phase 1
    const recipientId = getOtherUserId(thread, authUser.id);
    const tokens = await query<{ token: string }>(
      'SELECT token FROM push_tokens WHERE user_id = $1',
      [recipientId],
    );
    if (tokens.length > 0) {
      const failedTokens = await sendToMultipleTokens(
        tokens.map(t => t.token),
        `Message from ${authUser.displayName}`,
        body.length > 100 ? body.substring(0, 100) + '...' : body,
        { thread_id: threadId, event_id: thread.event_id, type: 'dm_message' },
      );
      if (failedTokens.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failedTokens]);
      }
    }

    trackEvent('dm_message_sent', {
      threadId,
      eventId: thread.event_id,
      senderId: authUser.id,
    });

    return successResponse({
      ...message,
      sender_name: authUser.displayName,
    }, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── Mark DM Thread Read ───────────────────────────────────────────────────────

async function markDmRead(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const threadId = req.params.threadId;

    if (!threadId || !isValidUUID(threadId)) {
      throw new ValidationError('A valid thread ID is required.');
    }

    const thread = await queryOne<DmThread>(
      'SELECT * FROM event_dm_threads WHERE id = $1',
      [threadId],
    );
    if (!thread) throw new NotFoundError('thread');
    if (!isParticipant(thread, authUser.id)) throw new ForbiddenError();

    const reqBody = (await req.json()) as Record<string, unknown>;
    const lastReadMessageId = reqBody.last_read_message_id as string;
    if (!lastReadMessageId || !isValidUUID(lastReadMessageId)) {
      throw new ValidationError('A valid last_read_message_id is required.');
    }

    const column = authUser.id === thread.user_a_id
      ? 'user_a_last_read_message_id'
      : 'user_b_last_read_message_id';

    await execute(
      `UPDATE event_dm_threads SET ${column} = $1 WHERE id = $2`,
      [lastReadMessageId, threadId],
    );

    return successResponse({ message: 'Thread marked as read.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── Negotiate DM Realtime ─────────────────────────────────────────────────────

async function negotiateDmRealtime(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const token = await getClientAccessToken(authUser.id);

    return successResponse({ url: token.url });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ─── Route Registrations ───────────────────────────────────────────────────────

app.http('createOrGetDmThread', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/dm-threads',
  handler: createOrGetDmThread,
});

app.http('listDmThreads', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/dm-threads',
  handler: listDmThreads,
});

app.http('getDmThread', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'dm-threads/{threadId}',
  handler: getDmThread,
});

app.http('listDmMessages', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'dm-threads/{threadId}/messages',
  handler: listDmMessages,
});

app.http('sendDmMessage', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'dm-threads/{threadId}/messages',
  handler: sendDmMessage,
});

app.http('markDmRead', {
  methods: ['PATCH'],
  authLevel: 'anonymous',
  route: 'dm-threads/{threadId}/read',
  handler: markDmRead,
});

app.http('negotiateDmRealtime', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'realtime/dm/negotiate',
  handler: negotiateDmRealtime,
});
