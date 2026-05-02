import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { isValidUUID, validateReactionType } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
import { enrichUserAvatar } from '../shared/services/avatarEnricher';
import {
  ReactionType,
  ReactorEntry,
  ReactorListResponse,
} from '../shared/models/reaction';

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

/**
 * GET /api/photos/{id}/reactions and the video equivalent. Returns the
 * full reactor list for the "who reacted?" sheet.
 *
 * Authorization: caller must be a member of the event's clique. We reuse
 * the same membership-gating SELECT as add/remove — non-members get a 404
 * (`PHOTO_NOT_FOUND` / `VIDEO_NOT_FOUND`) so we never reveal media
 * existence to outsiders.
 *
 * Sort: newest first. Cap: 200 rows (practical max ≈ 30 members × 4 types).
 *
 * The same user can leave multiple reaction types on the same media (the
 * UNIQUE constraint includes reaction_type), so a user appears once per
 * reaction they left, not once per media. Client groups for the "All" tab
 * as needed; backend stays 1:1 with the rows.
 */
const REACTOR_LIST_LIMIT = 200;

async function listReactionsForMedia(
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

    // Same membership gate as addReactionForMedia (lines above). Non-members
    // and processing/failed/deleted media all return NotFoundError to avoid
    // leaking existence.
    const media = await queryOne<{ id: string }>(
      `SELECT p.id FROM photos p
       JOIN events e ON e.id = p.event_id
       JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
       WHERE p.id = $1 AND p.status = 'active' AND p.media_type = $3`,
      [mediaId, authUser.id, mediaTypeLabel],
    );
    if (!media) throw new NotFoundError(mediaTypeLabel);

    const rows = await query<{
      id: string;
      user_id: string;
      reaction_type: ReactionType;
      created_at: Date;
      display_name: string;
      avatar_blob_path: string | null;
      avatar_thumb_blob_path: string | null;
      avatar_updated_at: Date | null;
      avatar_frame_preset: number | null;
    }>(
      `SELECT r.id, r.user_id, r.reaction_type, r.created_at,
              u.display_name,
              u.avatar_blob_path, u.avatar_thumb_blob_path,
              u.avatar_updated_at, u.avatar_frame_preset
       FROM reactions r
       JOIN users u ON u.id = r.user_id
       WHERE r.media_id = $1
       ORDER BY r.created_at DESC
       LIMIT $2`,
      [mediaId, REACTOR_LIST_LIMIT],
    );

    const reactors: ReactorEntry[] = await Promise.all(
      rows.map(async (row) => {
        const avatar = await enrichUserAvatar({
          avatar_blob_path: row.avatar_blob_path,
          avatar_thumb_blob_path: row.avatar_thumb_blob_path,
          avatar_updated_at: row.avatar_updated_at,
          avatar_frame_preset: row.avatar_frame_preset,
        });
        return {
          id: row.id,
          user_id: row.user_id,
          display_name: row.display_name,
          reaction_type: row.reaction_type,
          created_at: row.created_at.toISOString(),
          avatar_url: avatar.avatar_url,
          avatar_thumb_url: avatar.avatar_thumb_url,
          avatar_updated_at: avatar.avatar_updated_at,
          avatar_frame_preset: avatar.avatar_frame_preset,
        };
      }),
    );

    const byType: Record<ReactionType, number> = { heart: 0, laugh: 0, fire: 0, wow: 0 };
    for (const r of reactors) {
      byType[r.reaction_type] = (byType[r.reaction_type] ?? 0) + 1;
    }

    const response: ReactorListResponse = {
      media_id: mediaId,
      total_reactions: reactors.length,
      by_type: byType,
      reactors,
    };

    trackEvent('reactor_list_fetched', {
      mediaId,
      mediaType: mediaTypeLabel,
      totalReactions: String(reactors.length),
    });
    return successResponse(response);
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

async function getPhotoReactions(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return listReactionsForMedia(req, context, req.params.photoId, 'photo');
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

app.http('getPhotoReactions', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}/reactions',
  handler: getPhotoReactions,
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

async function getVideoReactions(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return listReactionsForMedia(req, context, req.params.videoId, 'video');
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

app.http('getVideoReactions', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}/reactions',
  handler: getVideoReactions,
});

// Exported for jest tests in __tests__/reactions.test.ts (they invoke the
// route handler directly to avoid spinning up the Functions host).
export { listReactionsForMedia };
