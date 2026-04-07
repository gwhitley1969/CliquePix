import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { isValidUUID, validateReactionType } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';

/**
 * Reaction handlers — work for both photos and videos.
 *
 * Migration 007 renamed reactions.photo_id to reactions.media_id (FK target
 * is still photos(id), since photos and videos share that table). Both photo
 * and video routes resolve the path param to a media_id and use the same
 * underlying logic.
 */

async function addReactionForMedia(
  req: HttpRequest,
  context: InvocationContext,
  mediaId: string | undefined,
  mediaTypeLabel: 'photo' | 'video',
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    if (!mediaId || !isValidUUID(mediaId)) {
      throw new ValidationError(`Invalid ${mediaTypeLabel} ID.`);
    }

    const body = (await req.json()) as Record<string, unknown>;
    const reactionType = validateReactionType(body.reaction_type);

    // Verify the media exists, is active, matches the expected type, and the user has access
    const media = await queryOne<{ id: string; event_id: string }>(
      `SELECT p.id, p.event_id FROM photos p
       JOIN events e ON e.id = p.event_id
       JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
       WHERE p.id = $1 AND p.status = 'active' AND p.media_type = $3`,
      [mediaId, authUser.id, mediaTypeLabel],
    );
    if (!media) throw new NotFoundError(mediaTypeLabel);

    const reaction = await queryOne<{ id: string; media_id: string; user_id: string; reaction_type: string; created_at: Date }>(
      `INSERT INTO reactions (media_id, user_id, reaction_type)
       VALUES ($1, $2, $3)
       ON CONFLICT (media_id, user_id, reaction_type) DO UPDATE SET created_at = reactions.created_at
       RETURNING *`,
      [mediaId, authUser.id, reactionType],
    );

    trackEvent('reaction_added', { mediaId, mediaType: mediaTypeLabel, reactionType });
    return successResponse(reaction, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

async function removeReactionForMedia(
  req: HttpRequest,
  context: InvocationContext,
  mediaId: string | undefined,
  reactionId: string | undefined,
  mediaTypeLabel: 'photo' | 'video',
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    if (!mediaId || !isValidUUID(mediaId) || !reactionId || !isValidUUID(reactionId)) {
      throw new ValidationError('Invalid ID.');
    }

    const reaction = await queryOne<{ id: string; media_id: string; user_id: string }>(
      'SELECT * FROM reactions WHERE id = $1 AND media_id = $2',
      [reactionId, mediaId],
    );
    if (!reaction) throw new NotFoundError('reaction');
    if (reaction.user_id !== authUser.id) {
      throw new ForbiddenError('You can only remove your own reactions.');
    }

    await execute('DELETE FROM reactions WHERE id = $1', [reactionId]);
    trackEvent('reaction_removed', { mediaId, mediaType: mediaTypeLabel, reactionId });
    return successResponse({ deleted: true });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// Photo reaction routes (existing — preserved for backwards compatibility)
// ====================================================================================

async function addPhotoReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return addReactionForMedia(req, context, req.params.photoId, 'photo');
}

async function removePhotoReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return removeReactionForMedia(req, context, req.params.photoId, req.params.reactionId, 'photo');
}

app.http('addPhotoReaction', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}/reactions',
  handler: addPhotoReaction,
});

app.http('removePhotoReaction', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}/reactions/{reactionId}',
  handler: removePhotoReaction,
});

// ====================================================================================
// Video reaction routes (new in v1)
// ====================================================================================

async function addVideoReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return addReactionForMedia(req, context, req.params.videoId, 'video');
}

async function removeVideoReaction(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return removeReactionForMedia(req, context, req.params.videoId, req.params.reactionId, 'video');
}

app.http('addVideoReaction', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}/reactions',
  handler: addVideoReaction,
});

app.http('removeVideoReaction', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}/reactions/{reactionId}',
  handler: removeVideoReaction,
});
