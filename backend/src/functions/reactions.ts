import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { isValidUUID, validateReactionType } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError } from '../shared/utils/errors';

async function addReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const photoId = req.params.photoId;
    if (!photoId || !isValidUUID(photoId)) {
      throw new (await import('../shared/utils/errors')).ValidationError('Invalid photo ID.');
    }

    const body = await req.json() as Record<string, unknown>;
    const reactionType = validateReactionType(body.reaction_type);

    // Check photo exists and is active, and user has access
    const photo = await queryOne<any>(
      `SELECT p.id, p.event_id FROM photos p
       JOIN events e ON e.id = p.event_id
       JOIN circle_members cm ON cm.circle_id = e.circle_id AND cm.user_id = $2
       WHERE p.id = $1 AND p.status = 'active'`,
      [photoId, authUser.id],
    );
    if (!photo) throw new NotFoundError('photo');

    // Insert with conflict handling
    const reaction = await queryOne<any>(
      `INSERT INTO reactions (photo_id, user_id, reaction_type)
       VALUES ($1, $2, $3)
       ON CONFLICT (photo_id, user_id, reaction_type) DO UPDATE SET created_at = reactions.created_at
       RETURNING *`,
      [photoId, authUser.id, reactionType],
    );

    trackEvent('reaction_added', { photo_id: photoId, reaction_type: reactionType });
    return successResponse(reaction, 201);
  } catch (error) {
    return handleError(error);
  }
}

async function removeReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const photoId = req.params.photoId;
    const reactionId = req.params.reactionId;

    if (!photoId || !isValidUUID(photoId) || !reactionId || !isValidUUID(reactionId)) {
      throw new (await import('../shared/utils/errors')).ValidationError('Invalid ID.');
    }

    const reaction = await queryOne<any>(
      'SELECT * FROM reactions WHERE id = $1 AND photo_id = $2',
      [reactionId, photoId],
    );
    if (!reaction) throw new NotFoundError('reaction');
    if (reaction.user_id !== authUser.id) throw new ForbiddenError('You can only remove your own reactions.');

    await execute('DELETE FROM reactions WHERE id = $1', [reactionId]);
    trackEvent('reaction_removed', { photo_id: photoId });
    return successResponse({ deleted: true });
  } catch (error) {
    return handleError(error);
  }
}

app.http('addReaction', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}/reactions',
  handler: addReaction,
});

app.http('removeReaction', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}/reactions/{reactionId}',
  handler: removeReaction,
});
