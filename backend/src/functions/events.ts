import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { validateRequiredString, validateOptionalString, validateRetentionHours, isValidUUID } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
import { deleteBlob } from '../shared/services/blobService';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { Event } from '../shared/models/event';

interface EventWithPhotoCount extends Event {
  photo_count: number;
}

interface EventWithCircleName extends EventWithPhotoCount {
  circle_name: string;
  member_count: number;
}

async function checkCircleMembership(circleId: string, userId: string): Promise<void> {
  const member = await queryOne(
    'SELECT id FROM circle_members WHERE circle_id = $1 AND user_id = $2',
    [circleId, userId],
  );
  if (!member) {
    throw new ForbiddenError('You are not a member of this circle.');
  }
}

async function createEvent(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const circleId = req.params.circleId;

    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Verify circle exists
    const circle = await queryOne('SELECT id FROM circles WHERE id = $1', [circleId]);
    if (!circle) {
      throw new NotFoundError('circle');
    }

    await checkCircleMembership(circleId, authUser.id);

    const body = (await req.json()) as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const description = validateOptionalString(body.description, 500);
    const retentionHours = validateRetentionHours(body.retention_hours);

    const event = await queryOne<Event>(
      `INSERT INTO events (circle_id, name, description, created_by_user_id, retention_hours, status, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'active', NOW() + make_interval(hours => $5))
       RETURNING *`,
      [circleId, name, description, authUser.id, retentionHours],
    );

    trackEvent('event_created', {
      eventId: event!.id,
      circleId,
      retentionHours: String(retentionHours),
      userId: authUser.id,
    });

    return successResponse(event, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function listEvents(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const circleId = req.params.circleId;

    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }

    // Verify circle exists
    const circle = await queryOne('SELECT id FROM circles WHERE id = $1', [circleId]);
    if (!circle) {
      throw new NotFoundError('circle');
    }

    await checkCircleMembership(circleId, authUser.id);

    const events = await query<EventWithPhotoCount>(
      `SELECT e.*, COALESCE(COUNT(p.id), 0)::int AS photo_count
       FROM events e
       LEFT JOIN photos p ON p.event_id = e.id AND p.status = 'active'
       WHERE e.circle_id = $1
       GROUP BY e.id
       ORDER BY e.created_at DESC`,
      [circleId],
    );

    return successResponse(events);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function getEvent(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const eventId = req.params.eventId;

    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const event = await queryOne<EventWithPhotoCount>(
      `SELECT e.*, COALESCE(COUNT(p.id), 0)::int AS photo_count
       FROM events e
       LEFT JOIN photos p ON p.event_id = e.id AND p.status = 'active'
       WHERE e.id = $1
       GROUP BY e.id`,
      [eventId],
    );

    if (!event) {
      throw new NotFoundError('event');
    }

    await checkCircleMembership(event.circle_id, authUser.id);

    return successResponse(event);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function listAllEvents(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const events = await query<EventWithCircleName>(
      `SELECT e.*,
              c.name AS circle_name,
              COALESCE(COUNT(p.id), 0)::int AS photo_count,
              (SELECT COUNT(*)::int FROM circle_members cm2 WHERE cm2.circle_id = e.circle_id) AS member_count
       FROM events e
       JOIN circle_members cm ON cm.circle_id = e.circle_id AND cm.user_id = $1
       JOIN circles c ON c.id = e.circle_id
       LEFT JOIN photos p ON p.event_id = e.id AND p.status = 'active'
       GROUP BY e.id, c.name
       ORDER BY e.created_at DESC`,
      [authUser.id],
    );

    return successResponse(events);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function deleteEvent(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const eventId = req.params.eventId;

    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const event = await queryOne<Event>(
      'SELECT * FROM events WHERE id = $1',
      [eventId],
    );
    if (!event) {
      throw new NotFoundError('event');
    }

    if (event.created_by_user_id !== authUser.id) {
      throw new ForbiddenError('Only the event organizer can delete this event.');
    }

    await checkCircleMembership(event.circle_id, authUser.id);

    // Delete blobs BEFORE cascade DB delete (blobs are not auto-deleted)
    const photos = await query<{ blob_path: string; thumbnail_blob_path: string | null }>(
      `SELECT blob_path, thumbnail_blob_path FROM photos WHERE event_id = $1 AND status IN ('active', 'pending')`,
      [eventId],
    );

    for (const photo of photos) {
      await deleteBlob(photo.blob_path);
      if (photo.thumbnail_blob_path) {
        await deleteBlob(photo.thumbnail_blob_path);
      }
    }

    // CASCADE deletes photos and reactions
    await execute('DELETE FROM events WHERE id = $1', [eventId]);

    // Notify circle members (except the deleter)
    const tokens = await query<{ token: string }>(
      `SELECT pt.token FROM push_tokens pt
       JOIN circle_members cm ON cm.user_id = pt.user_id
       WHERE cm.circle_id = $1 AND pt.user_id != $2`,
      [event.circle_id, authUser.id],
    );

    if (tokens.length > 0) {
      const failedTokens = await sendToMultipleTokens(
        tokens.map(t => t.token),
        'Event Deleted',
        `"${event.name}" was deleted by ${authUser.displayName}`,
        { event_id: eventId },
      );

      // Create in-app notification records
      await execute(
        `INSERT INTO notifications (id, user_id, type, payload_json)
         SELECT gen_random_uuid(), cm.user_id, 'event_deleted', $1::jsonb
         FROM circle_members cm
         WHERE cm.circle_id = $2 AND cm.user_id != $3`,
        [JSON.stringify({ event_id: eventId, event_name: event.name }), event.circle_id, authUser.id],
      );

      if (failedTokens.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failedTokens]);
      }
    }

    trackEvent('event_deleted', {
      eventId,
      circleId: event.circle_id,
      userId: authUser.id,
      photoCount: String(photos.length),
    });

    return successResponse({ message: 'Event deleted.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

app.http('listAllEvents', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events',
  handler: listAllEvents,
});

app.http('createEvent', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/events',
  handler: createEvent,
});

app.http('listEvents', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'circles/{circleId}/events',
  handler: listEvents,
});

app.http('getEvent', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events/{eventId}',
  handler: getEvent,
});

app.http('deleteEvent', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'events/{eventId}',
  handler: deleteEvent,
});
