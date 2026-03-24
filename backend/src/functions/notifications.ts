import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { isValidUUID, validatePlatform, validateRequiredString } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';

async function listNotifications(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const limit = Math.min(parseInt(req.query.get('limit') || '50', 10), 100);
    const cursor = req.query.get('cursor');

    let sql = 'SELECT * FROM notifications WHERE user_id = $1';
    const params: unknown[] = [authUser.id];

    if (cursor) {
      sql += ' AND created_at < $2';
      params.push(cursor);
    }

    sql += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1);
    params.push(limit);

    const notifications = await query<any>(sql, params);
    const nextCursor = notifications.length === limit
      ? notifications[notifications.length - 1].created_at.toISOString()
      : null;

    return successResponse({ notifications, next_cursor: nextCursor });
  } catch (error) {
    return handleError(error);
  }
}

async function markRead(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const notificationId = req.params.notificationId;
    if (!notificationId || !isValidUUID(notificationId)) {
      throw new ValidationError('Invalid notification ID.');
    }

    const notification = await queryOne<any>(
      'SELECT * FROM notifications WHERE id = $1',
      [notificationId],
    );
    if (!notification) throw new NotFoundError('notification');
    if (notification.user_id !== authUser.id) throw new ForbiddenError();

    await execute('UPDATE notifications SET is_read = true WHERE id = $1', [notificationId]);
    return successResponse({ ...notification, is_read: true });
  } catch (error) {
    return handleError(error);
  }
}

async function registerPushToken(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const body = await req.json() as Record<string, unknown>;

    const platform = validatePlatform(body.platform);
    const token = validateRequiredString(body.token, 'token', 500);

    const result = await queryOne<any>(
      `INSERT INTO push_tokens (user_id, platform, token)
       VALUES ($1, $2, $3)
       ON CONFLICT (token) DO UPDATE SET
         user_id = EXCLUDED.user_id,
         platform = EXCLUDED.platform,
         updated_at = NOW()
       RETURNING *`,
      [authUser.id, platform, token],
    );

    return successResponse(result, 201);
  } catch (error) {
    return handleError(error);
  }
}

app.http('listNotifications', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'notifications',
  handler: listNotifications,
});

app.http('markNotificationRead', {
  methods: ['PATCH'],
  authLevel: 'anonymous',
  route: 'notifications/{notificationId}/read',
  handler: markRead,
});

app.http('registerPushToken', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'push-tokens',
  handler: registerPushToken,
});
