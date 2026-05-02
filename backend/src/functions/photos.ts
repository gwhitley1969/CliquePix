import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { v4 as uuidv4 } from 'uuid';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import { blobExists, getBlobProperties, downloadBlob, uploadBlob, deleteBlob } from '../shared/services/blobService';
import { generateUploadSas, generateViewSas } from '../shared/services/sasService';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { isValidUUID, validateMimeType } from '../shared/utils/validators';
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
import { canDeleteMedia } from '../shared/utils/permissions';
import { Photo, PhotoWithUrls } from '../shared/models/photo';
import { Event } from '../shared/models/event';
import { enrichUserAvatar } from '../shared/services/avatarEnricher';
import { fetchTopReactors } from '../shared/db/topReactors';
import { deleteNotificationsForPhoto } from '../shared/db/notificationCleanup';

/**
 * Shape returned by listPhotos / getPhoto SQL: raw photo + uploader
 * denormalization. The trailing `uploaded_by_*` columns come from the JOIN
 * to users in every SELECT; null-safe for photos whose uploader has been
 * deleted (ON DELETE SET NULL via migration 004).
 */
type PhotoRowWithUploader = Photo & {
  uploaded_by_name: string | null;
  uploaded_by_avatar_blob_path: string | null;
  uploaded_by_avatar_thumb_blob_path: string | null;
  uploaded_by_avatar_updated_at: Date | null;
  uploaded_by_avatar_frame_preset: number | null;
};

// Column list factored out so listPhotos and getPhoto stay in lockstep.
// `p.*` first (so photo columns win on name collision), then aliased user
// columns with the uploaded_by_ prefix used in API responses.
const PHOTO_SELECT_WITH_UPLOADER = `p.*,
  u.display_name AS uploaded_by_name,
  u.avatar_blob_path AS uploaded_by_avatar_blob_path,
  u.avatar_thumb_blob_path AS uploaded_by_avatar_thumb_blob_path,
  u.avatar_updated_at AS uploaded_by_avatar_updated_at,
  u.avatar_frame_preset AS uploaded_by_avatar_frame_preset`;

const MAX_BLOB_SIZE = 15 * 1024 * 1024; // 15MB server-side limit
const DEFAULT_PAGE_LIMIT = 20;
const MAX_PAGE_LIMIT = 50;

// Helper: verify event exists and user is a member of the event's clique
async function getEventWithMembershipCheck(eventId: string, userId: string): Promise<Event & { member_id: string }> {
  const event = await queryOne<Event & { member_id: string }>(
    `SELECT e.*, cm.id AS member_id
     FROM events e
     JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
     WHERE e.id = $1`,
    [eventId, userId],
  );
  if (!event) {
    throw new NotFoundError('event');
  }
  return event;
}

// Helper: enrich a photo row with SAS URLs, reaction counts, user reactions,
// and (since migration 010) the uploader's signed avatar URLs. Accepts a
// row that already has the uploader denormalization JOINed in — callers
// are responsible for using PHOTO_SELECT_WITH_UPLOADER in their SELECT.
async function enrichPhotoWithUrls(
  photo: PhotoRowWithUploader,
  userId: string,
): Promise<PhotoWithUrls> {
  const [originalUrl, thumbnailUrl, reactionRows, userReactionRows, uploaderAvatar, topReactors] = await Promise.all([
    generateViewSas(photo.blob_path),
    photo.thumbnail_blob_path ? generateViewSas(photo.thumbnail_blob_path) : Promise.resolve(null),
    query<{ reaction_type: string; count: number }>(
      `SELECT reaction_type, COUNT(*)::int AS count
       FROM reactions
       WHERE media_id = $1
       GROUP BY reaction_type`,
      [photo.id],
    ),
    query<{ reaction_type: string }>(
      `SELECT reaction_type FROM reactions WHERE media_id = $1 AND user_id = $2`,
      [photo.id, userId],
    ),
    enrichUserAvatar({
      avatar_blob_path: photo.uploaded_by_avatar_blob_path,
      avatar_thumb_blob_path: photo.uploaded_by_avatar_thumb_blob_path,
      avatar_updated_at: photo.uploaded_by_avatar_updated_at,
      avatar_frame_preset: photo.uploaded_by_avatar_frame_preset,
    }),
    // Powers the "who reacted?" strip's avatar stack on the feed card. Cheap
    // enough at beta scale (1 indexed query + ≤3 SAS signs per media) and
    // keeps the strip pre-populated without a second round-trip when the
    // user hasn't tapped to open the sheet yet.
    fetchTopReactors(photo.id),
  ]);

  const reactionCounts: Record<string, number> = {};
  for (const row of reactionRows) {
    reactionCounts[row.reaction_type] = row.count;
  }

  return {
    ...photo,
    original_url: originalUrl,
    thumbnail_url: thumbnailUrl,
    reaction_counts: reactionCounts,
    user_reactions: userReactionRows.map(r => r.reaction_type),
    top_reactors: topReactors,
    uploaded_by_avatar_url: uploaderAvatar.avatar_url,
    uploaded_by_avatar_thumb_url: uploaderAvatar.avatar_thumb_url,
    uploaded_by_avatar_updated_at: uploaderAvatar.avatar_updated_at,
    uploaded_by_avatar_frame_preset: uploaderAvatar.avatar_frame_preset,
  };
}

async function generateThumbnailAsync(blobPath: string, photoId: string): Promise<void> {
  const sharp = (await import('sharp')).default;
  const buffer = await downloadBlob(blobPath);
  const thumbBuffer = await sharp(buffer)
    .resize({ width: 400, height: 400, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 70 })
    .toBuffer();
  const thumbPath = blobPath.replace('/original.jpg', '/thumb.jpg');
  await uploadBlob(thumbPath, thumbBuffer, 'image/jpeg');
  await execute('UPDATE photos SET thumbnail_blob_path = $1 WHERE id = $2', [thumbPath, photoId]);
}

// POST /api/events/{eventId}/photos/upload-url
async function getUploadUrl(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const event = await getEventWithMembershipCheck(eventId, authUser.id);

    if (event.status !== 'active') {
      throw new ValidationError('This event has expired. Photos can no longer be uploaded.');
    }

    const photoId = uuidv4();
    const blobPath = `photos/${event.clique_id}/${eventId}/${photoId}/original.jpg`;

    await queryOne<Photo>(
      `INSERT INTO photos (id, event_id, uploaded_by_user_id, blob_path, mime_type, status, expires_at)
       VALUES ($1, $2, $3, $4, 'image/jpeg', 'pending', $5)
       RETURNING *`,
      [photoId, eventId, authUser.id, blobPath, event.expires_at],
    );

    const uploadUrl = await generateUploadSas(blobPath);

    trackEvent('photo_upload_started', { photoId, eventId, userId: authUser.id });

    return successResponse({
      photo_id: photoId,
      upload_url: uploadUrl,
      blob_path: blobPath,
    }, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/events/{eventId}/photos
async function confirmUpload(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    await getEventWithMembershipCheck(eventId, authUser.id);

    const body = await req.json() as Record<string, unknown>;
    const photoId = body.photo_id;
    if (typeof photoId !== 'string' || !isValidUUID(photoId)) {
      throw new ValidationError('A valid photo_id is required.');
    }

    const mimeType = validateMimeType(body.mime_type);
    const width = typeof body.width === 'number' && body.width > 0 ? Math.round(body.width) : null;
    const height = typeof body.height === 'number' && body.height > 0 ? Math.round(body.height) : null;
    const originalFilename = typeof body.original_filename === 'string' ? body.original_filename.slice(0, 255) : null;

    // Fetch the pending photo record (must be media_type='photo' — videos have
    // their own upload flow via videos.ts commitVideoUpload)
    const photo = await queryOne<Photo>(
      "SELECT * FROM photos WHERE id = $1 AND event_id = $2 AND media_type = 'photo'",
      [photoId, eventId],
    );

    if (!photo) {
      throw new NotFoundError('photo');
    }

    if (photo.status !== 'pending') {
      throw new ValidationError('This photo has already been confirmed or deleted.');
    }

    if (photo.uploaded_by_user_id !== authUser.id) {
      throw new ForbiddenError('You can only confirm your own uploads.');
    }

    // Verify the blob was actually uploaded
    const exists = await blobExists(photo.blob_path);
    if (!exists) {
      throw new ValidationError('The photo file has not been uploaded yet.');
    }

    // Validate blob properties
    const blobProps = await getBlobProperties(photo.blob_path);
    const fileSizeBytes = blobProps.contentLength ?? 0;
    if (fileSizeBytes > MAX_BLOB_SIZE) {
      await deleteBlob(photo.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [photoId]);
      throw new ValidationError('File size exceeds the 15MB limit.');
    }

    // Validate blob content type from actual blob properties (spec: never touch photo bytes in confirm)
    const blobContentType = blobProps.contentType ?? '';
    if (!['image/jpeg', 'image/png'].includes(blobContentType)) {
      await deleteBlob(photo.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [photoId]);
      throw new ValidationError('File is not a valid JPEG or PNG image.');
    }

    // Use client-supplied dimensions (server does not download the blob during confirm)
    const finalWidth = width;
    const finalHeight = height;

    // Update photo record to active
    const updatedPhoto = await queryOne<Photo>(
      `UPDATE photos
       SET status = 'active',
           mime_type = $1,
           width = $2,
           height = $3,
           file_size_bytes = $4,
           original_filename = $5
       WHERE id = $6
       RETURNING *`,
      [mimeType, finalWidth, finalHeight, fileSizeBytes, originalFilename, photoId],
    );

    // Trigger async thumbnail generation (non-blocking, non-fatal)
    generateThumbnailAsync(photo.blob_path, photoId).catch((err) => {
      console.error('Async thumbnail generation failed:', err);
    });

    // Send push notifications to other event members
    const tokens = await query<{ token: string }>(
      `SELECT pt.token FROM push_tokens pt
       JOIN clique_members cm ON cm.user_id = pt.user_id
       JOIN events e ON e.clique_id = cm.clique_id
       WHERE e.id = $1 AND pt.user_id != $2`,
      [eventId, authUser.id],
    );

    if (tokens.length > 0) {
      const failedTokens = await sendToMultipleTokens(
        tokens.map(t => t.token),
        'New Photo!',
        `${authUser.displayName} shared a photo`,
        { event_id: eventId, photo_id: photoId },
      );

      // Create notification records for event members
      await execute(
        `INSERT INTO notifications (id, user_id, type, payload_json)
         SELECT gen_random_uuid(), cm.user_id, 'new_photo', $1::jsonb
         FROM clique_members cm
         JOIN events e ON e.clique_id = cm.clique_id
         WHERE e.id = $2 AND cm.user_id != $3`,
        [JSON.stringify({ event_id: eventId, photo_id: photoId }), eventId, authUser.id],
      );

      // Remove stale tokens
      if (failedTokens.length > 0) {
        await execute(
          'DELETE FROM push_tokens WHERE token = ANY($1)',
          [failedTokens],
        );
      }

      // Track notification telemetry
      const successCount = tokens.length - failedTokens.length;
      if (successCount > 0) {
        trackEvent('notification_sent', { eventId, photoId: photoId as string, count: String(successCount) });
      }
      if (failedTokens.length > 0) {
        trackEvent('notification_send_failed', { eventId, photoId: photoId as string, count: String(failedTokens.length) });
      }
    }

    trackEvent('photo_upload_completed', { photoId, eventId, userId: authUser.id });

    // Return enriched photo with SAS URLs. Uploader IS the caller, so pull
    // the denormalized uploader columns from authUser rather than a re-read.
    const photoWithUploader: PhotoRowWithUploader = {
      ...updatedPhoto!,
      uploaded_by_name: authUser.displayName,
      uploaded_by_avatar_blob_path: authUser.avatarBlobPath,
      uploaded_by_avatar_thumb_blob_path: authUser.avatarThumbBlobPath,
      uploaded_by_avatar_updated_at: authUser.avatarUpdatedAt,
      uploaded_by_avatar_frame_preset: authUser.avatarFramePreset,
    };
    const enrichedPhoto = await enrichPhotoWithUrls(photoWithUploader, authUser.id);
    return successResponse(enrichedPhoto, 201);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/events/{eventId}/photos
async function listPhotos(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    await getEventWithMembershipCheck(eventId, authUser.id);

    // Parse pagination params
    const cursorParam = req.query.get('cursor');
    const limitParam = req.query.get('limit');
    let limit = DEFAULT_PAGE_LIMIT;
    if (limitParam) {
      const parsed = parseInt(limitParam, 10);
      if (!isNaN(parsed) && parsed > 0) {
        limit = Math.min(parsed, MAX_PAGE_LIMIT);
      }
    }

    // Fetch photos with cursor-based pagination.
    // Filter by media_type='photo' so videos don't leak into the photos list
    // (the photos table hosts both now — videos have their own listVideos endpoint).
    let photos: PhotoRowWithUploader[];
    if (cursorParam) {
      photos = await query<PhotoRowWithUploader>(
        `SELECT ${PHOTO_SELECT_WITH_UPLOADER}
         FROM photos p
         JOIN users u ON p.uploaded_by_user_id = u.id
         WHERE p.event_id = $1 AND p.status = 'active' AND p.media_type = 'photo'
           AND p.created_at < $2
         ORDER BY p.created_at DESC
         LIMIT $3`,
        [eventId, cursorParam, limit],
      );
    } else {
      photos = await query<PhotoRowWithUploader>(
        `SELECT ${PHOTO_SELECT_WITH_UPLOADER}
         FROM photos p
         JOIN users u ON p.uploaded_by_user_id = u.id
         WHERE p.event_id = $1 AND p.status = 'active' AND p.media_type = 'photo'
         ORDER BY p.created_at DESC
         LIMIT $2`,
        [eventId, limit],
      );
    }

    // Batch-fetch reaction counts and user reactions for all photos
    const photoIds = photos.map(p => p.id);

    let allReactionCounts: { media_id: string; reaction_type: string; count: number }[] = [];
    let allUserReactions: { media_id: string; reaction_type: string }[] = [];

    if (photoIds.length > 0) {
      [allReactionCounts, allUserReactions] = await Promise.all([
        query<{ media_id: string; reaction_type: string; count: number }>(
          `SELECT media_id, reaction_type, COUNT(*)::int AS count
           FROM reactions
           WHERE media_id = ANY($1)
           GROUP BY media_id, reaction_type`,
          [photoIds],
        ),
        query<{ media_id: string; reaction_type: string }>(
          `SELECT media_id, reaction_type
           FROM reactions
           WHERE media_id = ANY($1) AND user_id = $2`,
          [photoIds, authUser.id],
        ),
      ]);
    }

    // Index reaction data by media_id
    const reactionCountsByPhoto = new Map<string, Record<string, number>>();
    for (const row of allReactionCounts) {
      if (!reactionCountsByPhoto.has(row.media_id)) {
        reactionCountsByPhoto.set(row.media_id, {});
      }
      reactionCountsByPhoto.get(row.media_id)![row.reaction_type] = row.count;
    }

    const userReactionsByPhoto = new Map<string, string[]>();
    for (const row of allUserReactions) {
      if (!userReactionsByPhoto.has(row.media_id)) {
        userReactionsByPhoto.set(row.media_id, []);
      }
      userReactionsByPhoto.get(row.media_id)!.push(row.reaction_type);
    }

    // Generate SAS URLs (photo + thumb + uploader avatar) for all photos.
    // Reactions were already batched above so each photo here fires 3 SAS
    // signings (photo original, photo thumb, uploader avatars) in parallel.
    const enrichedPhotos = await Promise.all(
      photos.map(async (photo) => {
        const [originalUrl, thumbnailUrl, uploaderAvatar] = await Promise.all([
          generateViewSas(photo.blob_path),
          photo.thumbnail_blob_path ? generateViewSas(photo.thumbnail_blob_path) : Promise.resolve(null),
          enrichUserAvatar({
            avatar_blob_path: photo.uploaded_by_avatar_blob_path,
            avatar_thumb_blob_path: photo.uploaded_by_avatar_thumb_blob_path,
            avatar_updated_at: photo.uploaded_by_avatar_updated_at,
            avatar_frame_preset: photo.uploaded_by_avatar_frame_preset,
          }),
        ]);

        return {
          ...photo,
          original_url: originalUrl,
          thumbnail_url: thumbnailUrl,
          reaction_counts: reactionCountsByPhoto.get(photo.id) ?? {},
          user_reactions: userReactionsByPhoto.get(photo.id) ?? [],
          uploaded_by_avatar_url: uploaderAvatar.avatar_url,
          uploaded_by_avatar_thumb_url: uploaderAvatar.avatar_thumb_url,
          uploaded_by_avatar_updated_at: uploaderAvatar.avatar_updated_at,
          uploaded_by_avatar_frame_preset: uploaderAvatar.avatar_frame_preset,
        };
      }),
    );

    const nextCursor = photos.length === limit
      ? (photos[photos.length - 1].created_at as unknown as string)
      : null;

    return successResponse({
      photos: enrichedPhotos,
      next_cursor: nextCursor,
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// GET /api/photos/{photoId}
async function getPhoto(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const photoId = req.params.photoId;
    if (!photoId || !isValidUUID(photoId)) {
      throw new ValidationError('A valid photo ID is required.');
    }

    const photo = await queryOne<PhotoRowWithUploader>(
      `SELECT ${PHOTO_SELECT_WITH_UPLOADER}
       FROM photos p
       LEFT JOIN users u ON u.id = p.uploaded_by_user_id
       WHERE p.id = $1 AND p.status = 'active' AND p.media_type = 'photo'`,
      [photoId],
    );

    if (!photo) {
      throw new NotFoundError('photo');
    }

    // Verify user is a member of the event's clique
    const membership = await queryOne<{ id: string }>(
      `SELECT cm.id FROM clique_members cm
       JOIN events e ON e.clique_id = cm.clique_id
       WHERE e.id = $1 AND cm.user_id = $2`,
      [photo.event_id, authUser.id],
    );

    if (!membership) {
      throw new ForbiddenError('You are not a member of this event\'s clique.');
    }

    const enrichedPhoto = await enrichPhotoWithUrls(photo, authUser.id);

    return successResponse(enrichedPhoto);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/photos/{photoId}
async function deletePhoto(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const photoId = req.params.photoId;
    if (!photoId || !isValidUUID(photoId)) {
      throw new ValidationError('A valid photo ID is required.');
    }

    // Only allow deleting photos via this endpoint — videos have their own DELETE /api/videos/{id}
    // with prefix-delete logic for HLS segments.
    // Authorization: uploader OR event organizer (`events.created_by_user_id`).
    // Enriched with the event JOIN so a single round-trip yields both IDs.
    type PhotoForDelete = Photo & { event_created_by_user_id: string | null };
    const photo = await queryOne<PhotoForDelete>(
      `SELECT p.*, e.created_by_user_id AS event_created_by_user_id
       FROM photos p
       JOIN events e ON e.id = p.event_id
       WHERE p.id = $1 AND p.status = 'active' AND p.media_type = 'photo'`,
      [photoId],
    );

    if (!photo) {
      throw new NotFoundError('photo');
    }

    const role = canDeleteMedia({
      uploadedByUserId: photo.uploaded_by_user_id,
      eventCreatedByUserId: photo.event_created_by_user_id,
      authUserId: authUser.id,
    });
    if (!role) {
      throw new ForbiddenError(
        'You can only delete your own photos or photos from events you created.',
      );
    }

    // Delete blobs (original + thumbnail)
    await deleteBlob(photo.blob_path);
    if (photo.thumbnail_blob_path) {
      await deleteBlob(photo.thumbnail_blob_path);
    }

    // Clean up notifications referencing this photo BEFORE the soft-delete.
    // Photos use UPDATE...status='deleted' but getPhoto filters status='active'
    // so a stale `new_photo` notification would 404 on tap. See
    // notificationCleanup.ts.
    try {
      const cleaned = await deleteNotificationsForPhoto(photoId);
      if (cleaned > 0) {
        trackEvent('stale_notifications_deleted', {
          trigger: 'photo_deleted',
          photoId,
          count: String(cleaned),
        });
      }
    } catch (err) {
      context.error(`Failed to clean notifications for photo ${photoId} (non-fatal):`, err);
      trackEvent('stale_notifications_cleanup_failed', { trigger: 'photo_deleted', photoId });
    }

    // Soft-delete the photo record
    await execute(
      "UPDATE photos SET status = 'deleted', deleted_at = NOW() WHERE id = $1",
      [photoId],
    );

    trackEvent('photo_deleted', {
      photoId,
      eventId: photo.event_id,
      userId: authUser.id,
      deleterRole: role,
      uploaderId: photo.uploaded_by_user_id ?? '',
      eventOrganizerId: photo.event_created_by_user_id ?? '',
    });

    return successResponse({ message: 'Photo deleted.' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// Register all endpoints
app.http('getUploadUrl', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/photos/upload-url',
  handler: getUploadUrl,
});

app.http('confirmUpload', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/photos',
  handler: confirmUpload,
});

app.http('listPhotos', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/photos',
  handler: listPhotos,
});

app.http('getPhoto', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}',
  handler: getPhoto,
});

app.http('deletePhoto', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'photos/{photoId}',
  handler: deletePhoto,
});
