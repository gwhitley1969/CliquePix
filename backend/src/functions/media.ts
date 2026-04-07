// Unified media feed endpoint — returns photos AND videos for an event
// in a single ordered list. Used by the Flutter event feed.
//
// The Photo and Video flows still have their own dedicated /photos and /videos
// list endpoints for backwards-compat and edge cases, but the mixed-media
// feed query goes through here.

import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne } from '../shared/services/dbService';
import { generateViewSas } from '../shared/services/sasService';
import { isValidUUID } from '../shared/utils/validators';
import { NotFoundError, ValidationError } from '../shared/utils/errors';
import { Photo } from '../shared/models/photo';
import { Event } from '../shared/models/event';

const PHOTO_VIEW_SAS_EXPIRY_SECONDS = 5 * 60;
const VIDEO_VIEW_SAS_EXPIRY_SECONDS = 15 * 60;

async function getEventWithMembershipCheck(
  eventId: string,
  userId: string,
): Promise<Event & { member_id: string }> {
  const event = await queryOne<Event & { member_id: string }>(
    `SELECT e.*, cm.id AS member_id
     FROM events e
     JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
     WHERE e.id = $1`,
    [eventId, userId],
  );
  if (!event) throw new NotFoundError('event');
  return event;
}

interface MediaFeedItem {
  id: string;
  media_type: 'photo' | 'video';
  event_id: string;
  uploaded_by_user_id: string;
  uploaded_by_name: string | null;
  created_at: Date;
  reaction_counts: Record<string, number>;
  user_reactions: string[];
  // Photo fields
  thumbnail_url?: string | null;
  original_url?: string | null;
  // Video fields
  poster_url?: string | null;
  duration_seconds?: number | null;
  processing_status?: string | null;
  width?: number | null;
  height?: number | null;
}

// GET /api/events/{eventId}/media — unified mixed-media feed
async function listMedia(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    await getEventWithMembershipCheck(eventId, authUser.id);

    // Fetch all photos AND videos for this event in one ordered query.
    // Includes 'processing' videos so the uploader sees their own placeholder.
    // Excludes deleted/rejected.
    const media = await query<Photo & { uploaded_by_name: string | null }>(
      `SELECT p.*, u.display_name AS uploaded_by_name
       FROM photos p
       LEFT JOIN users u ON u.id = p.uploaded_by_user_id
       WHERE p.event_id = $1
         AND p.status IN ('active', 'processing')
       ORDER BY p.created_at DESC`,
      [eventId],
    );

    // Batch-fetch reactions for all media items
    const mediaIds = media.map((m) => m.id);
    let reactionRows: { media_id: string; reaction_type: string; count: number }[] = [];
    let userReactionRows: { media_id: string; reaction_type: string }[] = [];

    if (mediaIds.length > 0) {
      [reactionRows, userReactionRows] = await Promise.all([
        query<{ media_id: string; reaction_type: string; count: number }>(
          `SELECT media_id, reaction_type, COUNT(*)::int AS count
           FROM reactions
           WHERE media_id = ANY($1)
           GROUP BY media_id, reaction_type`,
          [mediaIds],
        ),
        query<{ media_id: string; reaction_type: string }>(
          `SELECT media_id, reaction_type
           FROM reactions
           WHERE media_id = ANY($1) AND user_id = $2`,
          [mediaIds, authUser.id],
        ),
      ]);
    }

    const reactionsByMedia = new Map<string, Record<string, number>>();
    for (const row of reactionRows) {
      if (!reactionsByMedia.has(row.media_id)) {
        reactionsByMedia.set(row.media_id, {});
      }
      reactionsByMedia.get(row.media_id)![row.reaction_type] = row.count;
    }

    const userReactionsByMedia = new Map<string, string[]>();
    for (const row of userReactionRows) {
      if (!userReactionsByMedia.has(row.media_id)) {
        userReactionsByMedia.set(row.media_id, []);
      }
      userReactionsByMedia.get(row.media_id)!.push(row.reaction_type);
    }

    // Generate SAS URLs and shape response items
    const items: MediaFeedItem[] = await Promise.all(
      media.map(async (m): Promise<MediaFeedItem> => {
        const reactionCounts = reactionsByMedia.get(m.id) ?? {};
        const userReactions = userReactionsByMedia.get(m.id) ?? [];

        if (m.media_type === 'photo') {
          const [thumbUrl, origUrl] = await Promise.all([
            m.thumbnail_blob_path
              ? generateViewSas(m.thumbnail_blob_path, PHOTO_VIEW_SAS_EXPIRY_SECONDS)
              : Promise.resolve(null),
            generateViewSas(m.blob_path, PHOTO_VIEW_SAS_EXPIRY_SECONDS),
          ]);

          return {
            id: m.id,
            media_type: 'photo',
            event_id: m.event_id,
            uploaded_by_user_id: m.uploaded_by_user_id,
            uploaded_by_name: m.uploaded_by_name,
            created_at: m.created_at,
            reaction_counts: reactionCounts,
            user_reactions: userReactions,
            thumbnail_url: thumbUrl,
            original_url: origUrl,
            width: m.width,
            height: m.height,
          };
        } else {
          // Video — poster URL only (playback URLs come from /videos/{id}/playback)
          const posterUrl = m.poster_blob_path
            ? await generateViewSas(m.poster_blob_path, VIDEO_VIEW_SAS_EXPIRY_SECONDS)
            : null;

          return {
            id: m.id,
            media_type: 'video',
            event_id: m.event_id,
            uploaded_by_user_id: m.uploaded_by_user_id,
            uploaded_by_name: m.uploaded_by_name,
            created_at: m.created_at,
            reaction_counts: reactionCounts,
            user_reactions: userReactions,
            poster_url: posterUrl,
            duration_seconds: m.duration_seconds,
            processing_status: m.processing_status,
            width: m.width,
            height: m.height,
          };
        }
      }),
    );

    return successResponse({ media: items });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

app.http('listMedia', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/media',
  handler: listMedia,
});
