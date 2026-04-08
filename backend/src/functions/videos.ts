import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { v4 as uuidv4 } from 'uuid';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { query, queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import {
  blobExists,
  getBlobProperties,
  deleteBlob,
  deleteBlobsByPrefix,
  commitBlockList,
} from '../shared/services/blobService';
import { generateUploadSas, generateViewSas } from '../shared/services/sasService';
import { enqueueTranscodeJob } from '../shared/services/storageQueueService';
import { rewriteHlsManifest } from '../shared/services/hlsManifestRewriter';
import { sendToUser } from '../shared/services/webPubSubService';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { isValidUUID } from '../shared/utils/validators';
import {
  NotFoundError,
  ForbiddenError,
  ValidationError,
  AppError,
} from '../shared/utils/errors';
import { Photo, VideoWithUrls } from '../shared/models/photo';
import { Event } from '../shared/models/event';

// ====================================================================================
// Constants
// ====================================================================================

const BLOCK_SIZE = 4 * 1024 * 1024; // 4MB blocks per Decision 5
const MAX_VIDEO_FILE_SIZE = 500 * 1024 * 1024; // 500MB hard ceiling
const MAX_VIDEO_DURATION_SECONDS = 5 * 60; // 5 minutes per spec
const VIDEO_BLOCK_SAS_EXPIRY_SECONDS = 30 * 60; // 30 min — covers slow connections
const VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS = 15 * 60; // 15 min — covers playback sessions
// Q7: soft cap of active+pending+processing videos per user per event.
// 2026-04-08: temporarily bumped 5 → 10 to give headroom while the in-app
// video delete UI ships (video_player_screen.dart PopupMenuButton). Consider
// restoring to 5 once users have had time to clean up their test events.
const PER_USER_VIDEO_LIMIT = 10;

// ====================================================================================
// Validation error response shapes — approved defaults
// ====================================================================================
// User-facing error codes and messages for video upload failures.
// Tone: friendly + actionable. Each message tells the user what to DO,
// not just what went wrong.
const VIDEO_ERROR_CODES = {
  UNSUPPORTED_CONTAINER: {
    status: 415,
    message: "We can't process this video format. Please use MP4 or MOV.",
  },
  UNSUPPORTED_CODEC: {
    status: 415,
    message: "This video uses a format we can't process. Try re-recording or exporting as H.264 or HEVC.",
  },
  DURATION_EXCEEDED: {
    status: 413,
    message: "Videos must be 5 minutes or shorter. Please trim your video and try again.",
  },
  CORRUPT_MEDIA: {
    status: 422,
    message: "We couldn't read this video file. It may be damaged. Try re-recording or selecting a different video.",
  },
  HDR_CONVERSION_FAILED: {
    status: 422,
    message: "We couldn't convert this HDR video for playback. Try re-recording in standard (non-HDR) mode.",
  },
  VIDEO_LIMIT_REACHED: {
    status: 429,
    message: "You've reached the 5-video limit for this event. Delete a video to upload another.",
  },
  FILE_TOO_LARGE: {
    status: 413,
    message: "This video is too large. Videos must be under 500MB. Try recording at a lower quality.",
  },
} as const;

type VideoErrorCode = keyof typeof VIDEO_ERROR_CODES;

function videoError(code: VideoErrorCode): never {
  const { status, message } = VIDEO_ERROR_CODES[code];
  throw new AppError(code, message || code, status);
}

// ====================================================================================
// Shared helpers
// ====================================================================================

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
  if (!event) {
    throw new NotFoundError('event');
  }
  return event;
}

// ★ USER CONTRIBUTION POINT 3 — Per-user video limit enforcement
//
// Architectural commitment (Q7): soft cap of 5 currently non-deleted videos
// per user per event. Counts videos in status IN ('pending','processing','active').
// Deleted and rejected videos do NOT count — deletion frees a slot.
//
// Considerations:
//   - The exact SQL query: COUNT(*) with WHERE clause is the obvious choice.
//   - Whether to fetch the count first or rely on a database constraint: SQL
//     count is simpler and matches the "soft cap" wording (we can change the
//     limit later without a migration).
//   - Whether to include the current count in the error response: helpful for
//     a frontend that wants to show "5/5 videos used". You decide.
//   - The exact statuses to count: pending + processing + active (not deleted,
//     not rejected). This is what "currently in use" means.
//
// TODO(gene): Implement the count query and the limit check. If the count
// is at or above PER_USER_VIDEO_LIMIT, call videoError('VIDEO_LIMIT_REACHED').
//
// Reference SQL pattern (you may modify):
//   SELECT COUNT(*) AS count FROM photos
//   WHERE event_id = $1 AND uploaded_by_user_id = $2
//     AND media_type = 'video'
//     AND status IN ('pending', 'processing', 'active')
async function enforceVideoLimit(eventId: string, userId: string): Promise<void> {
  // Approved default: count currently non-deleted videos by this user in this event.
  // Counts pending (uploading), processing (transcoding), and active (ready) statuses.
  // Excludes deleted and rejected — those don't take up a slot.
  const result = await queryOne<{ count: number }>(
    `SELECT COUNT(*)::int AS count FROM photos
     WHERE event_id = $1
       AND uploaded_by_user_id = $2
       AND media_type = 'video'
       AND status IN ('pending', 'processing', 'active')`,
    [eventId, userId],
  );
  const currentCount = result?.count ?? 0;
  if (currentCount >= PER_USER_VIDEO_LIMIT) {
    videoError('VIDEO_LIMIT_REACHED');
  }
}

// ★ USER CONTRIBUTION POINT 4 — Video deletion cleanup semantics
//
// Architectural commitment (Q5): mark row deleted immediately, callback
// discards results if transcode is still in flight. But what about cleanup
// of blobs that already exist on disk?
//
// Three cases to handle:
//   1. status='pending': only the partial original master blob exists (or none).
//      Delete it via deleteBlob(video.blob_path).
//   2. status='processing': original master exists, derived assets do NOT yet
//      (transcoder will see status='deleted' on callback and skip writing them
//      OR write them and then the callback discards). Delete the master.
//   3. status='active': original + HLS prefix + MP4 fallback + poster all exist.
//      Need a prefix-delete to catch all the HLS segments + a few targeted
//      deletes for the named files.
//
// Two implementation styles:
//   (A) Switch on status, delete only what should exist for that status
//   (B) Try to delete everything blindly with try/catch (idempotent)
//
// Recommendation: (A) is more code but easier to reason about. (B) works
// but generates noise in the logs from "blob not found" errors which makes
// real failures harder to spot.
//
// TODO(gene): Implement the cleanup logic.
//
// Reference helpers:
//   - deleteBlob(blobPath: string): single-blob delete
//   - deleteBlobsByPrefix(prefix: string): delete everything under a prefix
//   - The HLS prefix is: video.hls_manifest_blob_path's parent directory
//     e.g., "photos/{cliqueId}/{eventId}/{videoId}/hls/"
async function cleanupVideoBlobs(video: Photo): Promise<void> {
  // Approved default: switch on status to delete only what should exist.
  // Cleaner logs than blind try-catch (no spurious "blob not found" errors
  // for assets that haven't been written yet).
  //
  // All deletes are wrapped in try/catch individually because:
  //   1. The blob may have been deleted by a race condition (timer cleanup)
  //   2. We want partial cleanup to succeed even if one delete fails
  //   3. Cleanup is best-effort — failure here shouldn't break the delete flow

  // Always attempt to delete the original master (exists in all status > pending)
  if (video.blob_path) {
    try {
      await deleteBlob(video.blob_path);
    } catch (err) {
      console.warn(`Failed to delete video master ${video.blob_path}:`, err);
    }
  }

  // For active videos (transcoding completed), the derivative assets exist.
  // Use prefix-delete on the HLS directory to catch all the segment files
  // in one operation, then targeted deletes for the named files.
  if (video.status === 'active') {
    if (video.hls_manifest_blob_path) {
      // Compute the HLS directory prefix from the manifest path
      // (e.g., "photos/.../hls/manifest.m3u8" → "photos/.../hls/")
      const lastSlash = video.hls_manifest_blob_path.lastIndexOf('/');
      if (lastSlash > 0) {
        const hlsDirPrefix = video.hls_manifest_blob_path.substring(0, lastSlash + 1);
        try {
          await deleteBlobsByPrefix(hlsDirPrefix);
        } catch (err) {
          console.warn(`Failed to prefix-delete HLS dir ${hlsDirPrefix}:`, err);
        }
      }
    }
    if (video.mp4_fallback_blob_path) {
      try {
        await deleteBlob(video.mp4_fallback_blob_path);
      } catch (err) {
        console.warn(`Failed to delete MP4 fallback ${video.mp4_fallback_blob_path}:`, err);
      }
    }
    if (video.poster_blob_path) {
      try {
        await deleteBlob(video.poster_blob_path);
      } catch (err) {
        console.warn(`Failed to delete poster ${video.poster_blob_path}:`, err);
      }
    }
  }

  // For pending or processing videos, only the original master exists
  // (already handled above). Nothing more to delete.
}

async function enrichVideoWithUrls(video: Photo, userId: string): Promise<VideoWithUrls> {
  // Instant preview: only the uploader sees a preview_url, and only while the
  // video is still processing/pending. Once status flips to 'active', this
  // returns null and the client falls through to the standard HLS/MP4 path.
  const isUploader = video.uploaded_by_user_id === userId;
  const isNotYetActive = video.status === 'processing' || video.status === 'pending';
  const shouldGeneratePreview = isUploader && isNotYetActive && Boolean(video.blob_path);

  const [posterUrl, mp4FallbackUrl, previewUrl, reactionRows, userReactionRows] = await Promise.all([
    video.poster_blob_path
      ? generateViewSas(video.poster_blob_path, VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS)
      : Promise.resolve(null),
    video.mp4_fallback_blob_path
      ? generateViewSas(video.mp4_fallback_blob_path, VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS)
      : Promise.resolve(null),
    shouldGeneratePreview
      ? generateViewSas(video.blob_path, VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS).catch((err) => {
          console.warn(`[enrichVideoWithUrls] preview SAS failed for ${video.id}:`, err);
          return null;
        })
      : Promise.resolve(null),
    query<{ reaction_type: string; count: number }>(
      `SELECT reaction_type, COUNT(*)::int AS count
       FROM reactions
       WHERE media_id = $1
       GROUP BY reaction_type`,
      [video.id],
    ),
    query<{ reaction_type: string }>(
      `SELECT reaction_type FROM reactions WHERE media_id = $1 AND user_id = $2`,
      [video.id, userId],
    ),
  ]);

  const reactionCounts: Record<string, number> = {};
  for (const row of reactionRows) {
    reactionCounts[row.reaction_type] = row.count;
  }

  return {
    ...video,
    poster_url: posterUrl,
    mp4_fallback_url: mp4FallbackUrl,
    preview_url: previewUrl,
    reaction_counts: reactionCounts,
    user_reactions: userReactionRows.map((r) => r.reaction_type),
  };
}

async function pushVideoReady(eventId: string, uploaderUserId: string, videoId: string): Promise<void> {
  const payload = { type: 'video_ready' as const, event_id: eventId, video_id: videoId };

  // Web PubSub: include the UPLOADER so their instant-preview card can
  // upgrade from 'processing' to the transcoded HLS/MP4 state when the
  // transcode completes. The uploader's EventFeedScreen listens to the same
  // onVideoReady stream as other clique members.
  await sendToUser(uploaderUserId, payload).catch((err) =>
    console.error(`Web PubSub send failed for uploader ${uploaderUserId}:`, err),
  );

  // Find other clique members (excluding the uploader) for Web PubSub
  // broadcast, FCM push, and in-app notification records.
  const otherMembers = await query<{ user_id: string }>(
    `SELECT DISTINCT cm.user_id FROM events e
     JOIN clique_members cm ON cm.clique_id = e.clique_id
     WHERE e.id = $1 AND cm.user_id != $2`,
    [eventId, uploaderUserId],
  );

  if (otherMembers.length === 0) return;

  // Web PubSub push for other members (foreground feed update)
  await Promise.all(
    otherMembers.map((m) =>
      sendToUser(m.user_id, payload).catch((err) =>
        console.error(`Web PubSub send failed for ${m.user_id}:`, err),
      ),
    ),
  );

  // FCM push for background/terminated OTHER members. Uploader is excluded
  // here because they already saw their upload complete — a push notification
  // about their own video would be redundant noise.
  const tokens = await query<{ token: string }>(
    `SELECT pt.token FROM push_tokens pt
     WHERE pt.user_id = ANY($1::uuid[])`,
    [otherMembers.map((m) => m.user_id)],
  );

  if (tokens.length > 0) {
    await sendToMultipleTokens(
      tokens.map((t) => t.token),
      'New video ready',
      'A new video has been added to your event',
      payload,
    );
  }

  // Create in-app notification records (other members only, unchanged)
  await execute(
    `INSERT INTO notifications (user_id, type, payload_json)
     SELECT cm.user_id, 'video_ready', $1::jsonb
     FROM clique_members cm
     JOIN events e ON e.clique_id = cm.clique_id
     WHERE e.id = $2 AND cm.user_id != $3`,
    [JSON.stringify({ event_id: eventId, video_id: videoId }), eventId, uploaderUserId],
  );

  trackEvent('video_ready_push_sent', {
    eventId,
    videoId,
    // +1 for the uploader (who always gets a Web PubSub push now)
    recipientCount: String(otherMembers.length + 1),
  });
}

async function pushVideoProcessingFailed(
  uploaderUserId: string,
  eventId: string,
  videoId: string,
  errorMessage: string,
): Promise<void> {
  const tokens = await query<{ token: string }>(
    `SELECT token FROM push_tokens WHERE user_id = $1`,
    [uploaderUserId],
  );

  if (tokens.length > 0) {
    await sendToMultipleTokens(
      tokens.map((t) => t.token),
      'Video upload failed',
      errorMessage,
      {
        type: 'video_processing_failed',
        event_id: eventId,
        video_id: videoId,
      },
    );
  }

  await execute(
    `INSERT INTO notifications (user_id, type, payload_json)
     VALUES ($1, 'video_processing_failed', $2::jsonb)`,
    [
      uploaderUserId,
      JSON.stringify({ event_id: eventId, video_id: videoId, error: errorMessage }),
    ],
  );
}

// ====================================================================================
// 1. POST /api/events/{eventId}/videos/upload-url
//    Generates block SAS URLs for the client to upload chunks.
// ====================================================================================

async function getVideoUploadUrl(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    const event = await getEventWithMembershipCheck(eventId, authUser.id);
    if (event.status !== 'active') {
      throw new ValidationError('This event has expired. Videos can no longer be uploaded.');
    }

    const body = (await req.json()) as Record<string, unknown>;
    const filename = typeof body.filename === 'string' ? body.filename.slice(0, 255) : null;
    const sizeBytes = typeof body.size_bytes === 'number' ? Math.round(body.size_bytes) : 0;
    const durationSeconds =
      typeof body.duration_seconds === 'number' ? Math.round(body.duration_seconds) : 0;

    // Server-side limits — re-validate even though the client validated too
    if (sizeBytes <= 0) {
      throw new ValidationError('A valid size_bytes is required.');
    }
    if (durationSeconds <= 0) {
      throw new ValidationError('A valid duration_seconds is required.');
    }
    if (durationSeconds > MAX_VIDEO_DURATION_SECONDS) {
      videoError('DURATION_EXCEEDED');
    }
    if (sizeBytes > MAX_VIDEO_FILE_SIZE) {
      videoError('FILE_TOO_LARGE');
    }

    // Per-user limit check (★ USER CONTRIBUTION 3)
    await enforceVideoLimit(eventId, authUser.id);

    const videoId = uuidv4();
    const blobPath = `photos/${event.clique_id}/${eventId}/${videoId}/original.mp4`;

    await queryOne<Photo>(
      `INSERT INTO photos
        (id, event_id, uploaded_by_user_id, blob_path, mime_type, status, media_type,
         expires_at, original_filename, file_size_bytes, duration_seconds, processing_status)
       VALUES ($1, $2, $3, $4, 'video/mp4', 'pending', 'video', $5, $6, $7, $8, 'pending')
       RETURNING *`,
      [videoId, eventId, authUser.id, blobPath, event.expires_at, filename, sizeBytes, durationSeconds],
    );

    // Calculate block count and generate one SAS per block
    const blockCount = Math.ceil(sizeBytes / BLOCK_SIZE);
    const blockUploadUrls: Array<{ block_id: string; url: string }> = [];

    // Generate the base SAS once and reuse it for all blocks (it's per-blob,
    // so all blocks of this blob can share it). Then append the &comp=block&blockid=
    // query parameters per block.
    const baseSasUrl = await generateUploadSas(blobPath, VIDEO_BLOCK_SAS_EXPIRY_SECONDS);

    for (let i = 0; i < blockCount; i++) {
      // Block IDs must be base64-encoded fixed-length strings (Azure requirement)
      const blockIdRaw = String(i).padStart(6, '0');
      const blockId = Buffer.from(blockIdRaw).toString('base64');
      const urlWithBlockId = `${baseSasUrl}&comp=block&blockid=${encodeURIComponent(blockId)}`;
      blockUploadUrls.push({ block_id: blockId, url: urlWithBlockId });
    }

    trackEvent('video_upload_started', {
      videoId,
      eventId,
      userId: authUser.id,
      fileSizeBytes: String(sizeBytes),
      durationSeconds: String(durationSeconds),
      blockCount: String(blockCount),
    });

    return successResponse(
      {
        video_id: videoId,
        blob_path: blobPath,
        block_size_bytes: BLOCK_SIZE,
        block_count: blockCount,
        block_upload_urls: blockUploadUrls,
        commit_url: `/api/events/${eventId}/videos`,
      },
      201,
    );
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 2. POST /api/events/{eventId}/videos
//    Commit upload (Put Block List) and dispatch transcoder job.
// ====================================================================================

async function commitVideoUpload(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    await getEventWithMembershipCheck(eventId, authUser.id);

    const body = (await req.json()) as Record<string, unknown>;
    const videoId = body.video_id;
    if (typeof videoId !== 'string' || !isValidUUID(videoId)) {
      throw new ValidationError('A valid video_id is required.');
    }

    const blockIds = body.block_ids;
    if (!Array.isArray(blockIds) || blockIds.length === 0 || !blockIds.every((b) => typeof b === 'string')) {
      throw new ValidationError('A valid block_ids array is required.');
    }

    // Fetch the pending video record
    const video = await queryOne<Photo>(
      `SELECT * FROM photos WHERE id = $1 AND event_id = $2 AND media_type = 'video'`,
      [videoId, eventId],
    );

    if (!video) {
      throw new NotFoundError('video');
    }
    if (video.status !== 'pending') {
      throw new ValidationError('This video has already been committed or deleted.');
    }
    if (video.uploaded_by_user_id !== authUser.id) {
      throw new ForbiddenError('You can only confirm your own uploads.');
    }

    // Commit the blocks via Put Block List
    try {
      await commitBlockList(video.blob_path, blockIds as string[], 'video/mp4');
    } catch (err) {
      // commitBlockList throws if any blockId isn't present in the uncommitted
      // block list — e.g., the client's block uploads never reached Azure, or
      // sent the wrong block IDs. Surface this as its own telemetry event so
      // we can diagnose client-side upload bugs.
      trackEvent('video_commit_block_list_failed', {
        videoId,
        eventId,
        userId: authUser.id,
        expectedBlocks: String(blockIds.length),
        error: err instanceof Error ? err.message : String(err),
      });
      // Delete the pending row so the user can retry cleanly
      await execute(`DELETE FROM photos WHERE id = $1`, [videoId]);
      throw new ValidationError(
        `Failed to commit video blocks: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    // Verify the assembled blob exists with the expected size.
    // Explicit Number() conversion on BOTH sides as defense in depth —
    // the global pg type parser already converts BIGINT to number, but
    // being explicit here makes the comparison intent obvious and
    // protects against future changes to the type parser config.
    const blobProps = await getBlobProperties(video.blob_path);
    const actualSize = Number(blobProps.contentLength ?? 0);
    const expectedSize = Number(video.file_size_bytes ?? 0);
    if (actualSize !== expectedSize) {
      // Size mismatch — likely a client bug or partial upload.
      // Track this specifically so we can catch client upload bugs in telemetry.
      trackEvent('video_commit_size_mismatch', {
        videoId,
        eventId,
        userId: authUser.id,
        expectedSize: String(expectedSize),
        actualSize: String(actualSize),
        blockCount: String(blockIds.length),
      });
      await deleteBlob(video.blob_path);
      await execute(`DELETE FROM photos WHERE id = $1`, [videoId]);
      throw new ValidationError(
        `Uploaded blob size (${actualSize}) does not match expected size (${expectedSize}).`,
      );
    }

    // Get clique_id for the queue message
    const eventDetails = await queryOne<{ clique_id: string }>(
      `SELECT clique_id FROM events WHERE id = $1`,
      [eventId],
    );
    if (!eventDetails) throw new NotFoundError('event');

    // Mark the row as processing and enqueue the transcode job
    await execute(
      `UPDATE photos SET status = 'processing', processing_status = 'queued' WHERE id = $1`,
      [videoId],
    );

    await enqueueTranscodeJob({
      videoId,
      blobPath: video.blob_path,
      eventId,
      cliqueId: eventDetails.clique_id,
    });

    trackEvent('video_upload_committed', {
      videoId,
      eventId,
      userId: authUser.id,
      totalBlockCount: String(blockIds.length),
    });
    trackEvent('video_transcoding_queued', { videoId, eventId });

    // Instant preview: return a read SAS URL for the original blob so the
    // uploader can play the video immediately without waiting for transcoding.
    // The original is a valid MP4/MOV at this point (all blocks committed +
    // size verified). Wrapped in try/catch because preview URL is a nice-to-
    // have — if SAS generation fails, the transcode job is already enqueued
    // and the client falls back to the "Polishing..." placeholder.
    let previewUrl: string | null = null;
    try {
      previewUrl = await generateViewSas(video.blob_path, VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS);
    } catch (err) {
      console.warn(`[video commit] Failed to generate preview SAS for ${videoId}:`, err);
      trackEvent('video_preview_sas_failed', {
        videoId,
        eventId,
        userId: authUser.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    return successResponse(
      {
        video_id: videoId,
        status: 'processing',
        preview_url: previewUrl,
        message: 'Video uploaded successfully and queued for processing.',
      },
      202,
    );
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 3. GET /api/events/{eventId}/videos
//    List videos for an event (active + processing for the uploader's own pending uploads).
// ====================================================================================

async function listVideos(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const eventId = req.params.eventId;
    if (!eventId || !isValidUUID(eventId)) {
      throw new ValidationError('A valid event ID is required.');
    }

    await getEventWithMembershipCheck(eventId, authUser.id);

    const videos = await query<Photo & { uploaded_by_name: string | null }>(
      `SELECT p.*, u.display_name AS uploaded_by_name
       FROM photos p
       LEFT JOIN users u ON u.id = p.uploaded_by_user_id
       WHERE p.event_id = $1 AND p.media_type = 'video'
         AND p.status IN ('active', 'processing')
       ORDER BY p.created_at DESC`,
      [eventId],
    );

    const enriched = await Promise.all(
      videos.map((v) => enrichVideoWithUrls(v, authUser.id)),
    );

    return successResponse({ videos: enriched });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 4. GET /api/videos/{videoId}
//    Single video metadata + view URLs (no playback manifest — see /playback for that).
// ====================================================================================

async function getVideo(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const videoId = req.params.videoId;
    if (!videoId || !isValidUUID(videoId)) {
      throw new ValidationError('A valid video ID is required.');
    }

    const video = await queryOne<Photo & { uploaded_by_name: string | null }>(
      `SELECT p.*, u.display_name AS uploaded_by_name
       FROM photos p
       JOIN events e ON e.id = p.event_id
       JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
       LEFT JOIN users u ON u.id = p.uploaded_by_user_id
       WHERE p.id = $1 AND p.media_type = 'video'`,
      [videoId, authUser.id],
    );

    if (!video) throw new NotFoundError('video');

    const enriched = await enrichVideoWithUrls(video, authUser.id);
    return successResponse(enriched);
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 5. GET /api/videos/{videoId}/playback
//    Returns the rewritten HLS manifest + MP4 fallback URL + poster URL.
// ====================================================================================

async function getVideoPlayback(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const videoId = req.params.videoId;
    if (!videoId || !isValidUUID(videoId)) {
      throw new ValidationError('A valid video ID is required.');
    }

    const video = await queryOne<Photo>(
      `SELECT p.* FROM photos p
       JOIN events e ON e.id = p.event_id
       JOIN clique_members cm ON cm.clique_id = e.clique_id AND cm.user_id = $2
       WHERE p.id = $1 AND p.media_type = 'video' AND p.status = 'active'`,
      [videoId, authUser.id],
    );

    if (!video) throw new NotFoundError('video');
    if (!video.hls_manifest_blob_path || !video.mp4_fallback_blob_path || !video.poster_blob_path) {
      throw new ValidationError('Video is not ready for playback (missing derivative assets).');
    }

    // Rewrite the HLS manifest with fresh per-segment SAS URLs (60s in-Function cache)
    const hlsManifest = await rewriteHlsManifest(videoId, video.hls_manifest_blob_path);
    const mp4FallbackUrl = await generateViewSas(
      video.mp4_fallback_blob_path,
      VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS,
    );
    const posterUrl = await generateViewSas(
      video.poster_blob_path,
      VIDEO_PLAYBACK_SAS_EXPIRY_SECONDS,
    );

    trackEvent('video_played', { videoId, userId: authUser.id });

    return successResponse({
      video_id: videoId,
      hls_manifest: hlsManifest,
      mp4_fallback_url: mp4FallbackUrl,
      poster_url: posterUrl,
      duration_seconds: video.duration_seconds,
      width: video.width,
      height: video.height,
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 6. DELETE /api/videos/{videoId}
//    Soft-delete the video, schedule cleanup of any existing blobs.
// ====================================================================================

async function deleteVideo(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);

    const videoId = req.params.videoId;
    if (!videoId || !isValidUUID(videoId)) {
      throw new ValidationError('A valid video ID is required.');
    }

    const video = await queryOne<Photo>(
      `SELECT * FROM photos WHERE id = $1 AND media_type = 'video'`,
      [videoId],
    );

    if (!video) throw new NotFoundError('video');
    if (video.uploaded_by_user_id !== authUser.id) {
      throw new ForbiddenError('You can only delete your own videos.');
    }

    // Mark deleted immediately (Q5: callback discards results if transcode in flight)
    await execute(
      `UPDATE photos SET status = 'deleted', deleted_at = NOW() WHERE id = $1`,
      [videoId],
    );

    // Best-effort cleanup of any blobs that already exist (★ USER CONTRIBUTION 4)
    try {
      await cleanupVideoBlobs(video);
    } catch (err) {
      console.error(`cleanupVideoBlobs failed for ${videoId} (non-fatal):`, err);
    }

    trackEvent('video_deleted', { videoId, eventId: video.event_id, userId: authUser.id });

    return successResponse({ video_id: videoId, status: 'deleted' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// 7. POST /api/internal/video-processing-complete
//    Container Apps Job callback when transcoding completes (or fails).
//    Authenticated via the transcoder MI's bearer token.
// ====================================================================================

interface CallbackBody {
  video_id: string;
  success: boolean;
  error_code?: string;
  error_message?: string;
  hls_manifest_blob_path?: string;
  mp4_fallback_blob_path?: string;
  poster_blob_path?: string;
  duration_seconds?: number;
  width?: number;
  height?: number;
  is_hdr_source?: boolean;
  normalized_to_sdr?: boolean;
  // Performance telemetry (added 2026-04-08 with stream-copy fast path)
  processing_mode?: 'transcode' | 'stream_copy';
  fast_path_failure_reason?: string | null;
}

async function videoProcessingComplete(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    // Auth: handled by Functions runtime via authLevel='function'.
    // The transcoder must present a valid function key as ?code=<key>.
    // The key is stored in Key Vault and surfaced to the Container Apps Job
    // as a secret env var. See docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md.
    //
    // (Earlier attempt: managed identity bearer token via custom audience.
    //  That requires an Azure AD app registration which we deferred to v1.5.)

    const body = (await req.json()) as CallbackBody;
    if (!body.video_id || !isValidUUID(body.video_id)) {
      throw new ValidationError('A valid video_id is required.');
    }

    const video = await queryOne<Photo>(
      `SELECT * FROM photos WHERE id = $1 AND media_type = 'video'`,
      [body.video_id],
    );
    if (!video) throw new NotFoundError('video');

    // Idempotency: skip if already processed (transcoder may have retried after a network blip)
    if (video.status === 'active' && video.processing_status === 'complete') {
      trackEvent('video_processing_callback_idempotent_skip', { videoId: body.video_id });
      return successResponse({ status: 'already_complete' });
    }

    // Q5: if the row is already deleted, discard results and clean up any written blobs
    if (video.status === 'deleted') {
      if (body.success) {
        try {
          await cleanupVideoBlobs({
            ...video,
            hls_manifest_blob_path: body.hls_manifest_blob_path ?? null,
            mp4_fallback_blob_path: body.mp4_fallback_blob_path ?? null,
            poster_blob_path: body.poster_blob_path ?? null,
          });
        } catch (err) {
          console.error('Cleanup after delete-during-transcode failed (non-fatal):', err);
        }
      }
      trackEvent('video_processing_discarded_after_delete', { videoId: body.video_id });
      return successResponse({ status: 'discarded' });
    }

    if (!body.success) {
      await execute(
        `UPDATE photos
         SET status = 'rejected', processing_status = 'failed', processing_error = $1
         WHERE id = $2`,
        [body.error_message ?? body.error_code ?? 'Unknown error', body.video_id],
      );
      trackEvent('video_transcoding_failed', {
        videoId: body.video_id,
        errorCode: body.error_code ?? 'unknown',
      });

      // Notify only the uploader of failure (Q6 + plan helper)
      try {
        await pushVideoProcessingFailed(
          video.uploaded_by_user_id,
          video.event_id,
          body.video_id,
          body.error_message ?? 'Processing failed',
        );
      } catch (err) {
        console.error('Failed to send processing-failed push (non-fatal):', err);
      }

      return successResponse({ status: 'failed' });
    }

    // Success path — populate video columns
    await execute(
      `UPDATE photos
       SET status = 'active',
           processing_status = 'complete',
           hls_manifest_blob_path = $1,
           mp4_fallback_blob_path = $2,
           poster_blob_path = $3,
           duration_seconds = COALESCE($4, duration_seconds),
           width = COALESCE($5, width),
           height = COALESCE($6, height),
           is_hdr_source = $7,
           normalized_to_sdr = $8
       WHERE id = $9`,
      [
        body.hls_manifest_blob_path ?? null,
        body.mp4_fallback_blob_path ?? null,
        body.poster_blob_path ?? null,
        body.duration_seconds ?? null,
        body.width ?? null,
        body.height ?? null,
        body.is_hdr_source ?? null,
        body.normalized_to_sdr ?? null,
        body.video_id,
      ],
    );

    trackEvent('video_transcoding_completed', {
      videoId: body.video_id,
      durationSeconds: String(body.duration_seconds ?? 0),
      processingMode: String(body.processing_mode ?? 'transcode'),
      fastPathFailureReason: String(body.fast_path_failure_reason ?? 'none'),
    });

    // Push video_ready to event members
    try {
      await pushVideoReady(video.event_id, video.uploaded_by_user_id, body.video_id);
    } catch (err) {
      console.error('Failed to push video_ready (non-fatal):', err);
    }

    return successResponse({ status: 'complete' });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// ====================================================================================
// Route registration
// ====================================================================================

app.http('getVideoUploadUrl', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/videos/upload-url',
  handler: getVideoUploadUrl,
});

app.http('commitVideoUpload', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/videos',
  handler: commitVideoUpload,
});

app.http('listVideos', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'events/{eventId}/videos',
  handler: listVideos,
});

app.http('getVideo', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}',
  handler: getVideo,
});

app.http('getVideoPlayback', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}/playback',
  handler: getVideoPlayback,
});

app.http('deleteVideo', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'videos/{videoId}',
  handler: deleteVideo,
});

app.http('videoProcessingComplete', {
  methods: ['POST'],
  authLevel: 'function',
  route: 'internal/video-processing-complete',
  handler: videoProcessingComplete,
});
