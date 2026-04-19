import { app, InvocationContext, Timer } from '@azure/functions';
import { query, queryOne, execute } from '../shared/services/dbService';
import { deleteBlob, deleteBlobsByPrefix } from '../shared/services/blobService';
import { sendToMultipleTokens, sendSilentToMultipleTokens } from '../shared/services/fcmService';
import { trackEvent } from '../shared/services/telemetryService';
import { initTelemetry } from '../shared/services/telemetryService';
import * as path from 'path';

// Helper: prefix-delete all blobs under a video's directory
// (e.g., photos/{cliqueId}/{eventId}/{videoId}/) to clean up the original
// master + HLS segments + MP4 fallback + poster in one operation.
async function deleteVideoAssets(video: { blob_path: string; hls_manifest_blob_path: string | null }): Promise<number> {
  // The video's "directory" is the parent of its original.mp4 path
  const videoDirPrefix = path.posix.dirname(video.blob_path) + '/';
  return deleteBlobsByPrefix(videoDirPrefix);
}

async function cleanupExpired(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running expired media cleanup');

  // ====================================================================================
  // 1. Expired PHOTOS — delete original + thumbnail per row
  // ====================================================================================
  const expiredPhotos = await query<any>(
    `SELECT id, blob_path, thumbnail_blob_path, event_id
     FROM photos
     WHERE media_type = 'photo' AND status = 'active' AND expires_at < NOW()
     LIMIT 500`,
  );

  let deletedPhotoCount = 0;
  for (const photo of expiredPhotos) {
    try {
      await deleteBlob(photo.blob_path);
      if (photo.thumbnail_blob_path) {
        await deleteBlob(photo.thumbnail_blob_path);
      }
      await execute(
        "UPDATE photos SET status = 'deleted', deleted_at = NOW() WHERE id = $1",
        [photo.id],
      );
      deletedPhotoCount++;
    } catch (err) {
      context.error(`Failed to clean up photo ${photo.id}:`, err);
    }
  }
  if (deletedPhotoCount > 0) {
    trackEvent('expired_photos_deleted', { count: String(deletedPhotoCount) });
    context.log(`Cleaned up ${deletedPhotoCount} expired photos`);
  }

  // ====================================================================================
  // 2. Expired VIDEOS — prefix-delete the video directory (HLS segments + all derivatives)
  //    Smaller batch since each video can be 30+ blobs to delete
  // ====================================================================================
  const expiredVideos = await query<any>(
    `SELECT id, blob_path, hls_manifest_blob_path, event_id
     FROM photos
     WHERE media_type = 'video' AND status = 'active' AND expires_at < NOW()
     LIMIT 100`,
  );

  let deletedVideoCount = 0;
  let totalBlobsDeleted = 0;
  for (const video of expiredVideos) {
    try {
      const blobCount = await deleteVideoAssets(video);
      totalBlobsDeleted += blobCount;
      await execute(
        "UPDATE photos SET status = 'deleted', deleted_at = NOW() WHERE id = $1",
        [video.id],
      );
      deletedVideoCount++;
    } catch (err) {
      context.error(`Failed to clean up video ${video.id}:`, err);
    }
  }
  if (deletedVideoCount > 0) {
    trackEvent('expired_videos_deleted', { count: String(deletedVideoCount) });
    trackEvent('expired_video_hls_prefix_deleted', {
      videoCount: String(deletedVideoCount),
      blobCount: String(totalBlobsDeleted),
    });
    context.log(`Cleaned up ${deletedVideoCount} expired videos (${totalBlobsDeleted} blobs)`);
  }

  if (expiredPhotos.length === 0 && expiredVideos.length === 0) {
    context.log('No expired media to clean up');
    // Don't return — still process events/dm-threads/expired-event hard-delete below
  }

  // (Original photo-only counter retained for backwards compatibility with downstream queries)
  let deletedCount = deletedPhotoCount + deletedVideoCount;

  // Check for events that should be marked expired
  const expiredEventRows = await query<{ id: string }>(
    `UPDATE events SET status = 'expired'
     WHERE status = 'active' AND expires_at < NOW()
     AND NOT EXISTS (
       SELECT 1 FROM photos WHERE event_id = events.id AND status = 'active'
     )
     RETURNING id`,
  );

  if (expiredEventRows.length > 0) {
    trackEvent('event_expired', { count: String(expiredEventRows.length) });
  }

  // Mark DM threads as read_only for expired events
  const dmReadOnlyCount = await execute(
    `UPDATE event_dm_threads SET status = 'read_only'
     WHERE status = 'active'
     AND event_id IN (SELECT id FROM events WHERE status = 'expired')`,
  );
  if (dmReadOnlyCount > 0) {
    trackEvent('dm_thread_marked_read_only', { count: String(dmReadOnlyCount) });
  }

  // Hard-delete expired events (CASCADE removes photos, reactions, DM threads/messages)
  const expiredEvents = await query<{ id: string }>(
    `SELECT id FROM events WHERE status = 'expired'`,
  );

  if (expiredEvents.length > 0) {
    // Safety net: delete any remaining blobs before cascade-deleting DB records
    for (const event of expiredEvents) {
      const remainingPhotos = await query<{ blob_path: string; thumbnail_blob_path: string | null }>(
        `SELECT blob_path, thumbnail_blob_path FROM photos WHERE event_id = $1`,
        [event.id],
      );
      for (const photo of remainingPhotos) {
        try {
          await deleteBlob(photo.blob_path);
          if (photo.thumbnail_blob_path) await deleteBlob(photo.thumbnail_blob_path);
        } catch (_) { /* blob may already be deleted */ }
      }
    }

    const deleteCount = await execute(
      `DELETE FROM events WHERE status = 'expired'`,
    );
    trackEvent('expired_events_deleted', { count: String(deleteCount) });
    context.log(`Deleted ${deleteCount} expired events`);
  }

  trackEvent('expired_photos_deleted', { count: String(deletedCount) });
  context.log(`Cleaned up ${deletedCount} expired photos`);
}

async function cleanupOrphans(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running orphan upload cleanup');

  // ====================================================================================
  // 1. Orphaned PHOTO uploads — 10 min window (existing behavior)
  // ====================================================================================
  const photoOrphans = await query<any>(
    `SELECT id, blob_path FROM photos
     WHERE media_type = 'photo' AND status = 'pending'
       AND created_at < NOW() - INTERVAL '10 minutes'
     LIMIT 200`,
  );

  let cleanedPhotoCount = 0;
  for (const orphan of photoOrphans) {
    try {
      await deleteBlob(orphan.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [orphan.id]);
      cleanedPhotoCount++;
    } catch (err) {
      context.error(`Failed to clean up photo orphan ${orphan.id}:`, err);
    }
  }

  // ====================================================================================
  // 2. Orphaned VIDEO uploads — 30 min window (Q5: videos take longer to upload)
  // ====================================================================================
  const videoOrphans = await query<any>(
    `SELECT id, blob_path FROM photos
     WHERE media_type = 'video' AND status = 'pending'
       AND created_at < NOW() - INTERVAL '30 minutes'
     LIMIT 100`,
  );

  let cleanedVideoCount = 0;
  for (const orphan of videoOrphans) {
    try {
      // Pending videos may have partial blocks committed but not finalized.
      // deleteBlob handles both committed and uncommitted blocks.
      await deleteBlob(orphan.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [orphan.id]);
      cleanedVideoCount++;
    } catch (err) {
      context.error(`Failed to clean up video orphan ${orphan.id}:`, err);
    }
  }

  // ====================================================================================
  // 3. Failed video processing cleanup — 1 hour window
  //    Videos that the transcoder rejected (status='rejected') may have partially-
  //    written outputs. Prefix-delete the whole video directory.
  // ====================================================================================
  const failedVideos = await query<any>(
    `SELECT id, blob_path FROM photos
     WHERE media_type = 'video' AND status = 'rejected'
       AND created_at < NOW() - INTERVAL '1 hour'
     LIMIT 100`,
  );

  let cleanedFailedCount = 0;
  for (const failed of failedVideos) {
    try {
      const videoDirPrefix = path.posix.dirname(failed.blob_path) + '/';
      await deleteBlobsByPrefix(videoDirPrefix);
      await execute('DELETE FROM photos WHERE id = $1', [failed.id]);
      cleanedFailedCount++;
    } catch (err) {
      context.error(`Failed to clean up failed video ${failed.id}:`, err);
    }
  }

  if (cleanedPhotoCount > 0) {
    trackEvent('orphaned_uploads_cleaned', { count: String(cleanedPhotoCount), mediaType: 'photo' });
  }
  if (cleanedVideoCount > 0) {
    trackEvent('orphaned_video_uploads_cleaned', { count: String(cleanedVideoCount) });
  }
  if (cleanedFailedCount > 0) {
    trackEvent('failed_video_processing_cleaned', { count: String(cleanedFailedCount) });
  }

  const totalCleaned = cleanedPhotoCount + cleanedVideoCount + cleanedFailedCount;
  context.log(`Cleaned up ${totalCleaned} orphaned/failed uploads (${cleanedPhotoCount} photo / ${cleanedVideoCount} video orphans / ${cleanedFailedCount} failed videos)`);
}

async function notifyExpiring(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running expiration notification check');

  const expiringEvents = await query<any>(
    `SELECT e.id, e.name, e.clique_id, e.expires_at
     FROM events e
     WHERE e.status = 'active'
       AND e.expires_at > NOW() + INTERVAL '23 hours'
       AND e.expires_at <= NOW() + INTERVAL '25 hours'
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
         WHERE n.type = 'event_expiring'
           AND n.payload_json->>'event_id' = e.id::text
           AND n.created_at > NOW() - INTERVAL '20 hours'
       )`,
  );

  if (expiringEvents.length === 0) {
    context.log('No events expiring soon');
    return;
  }

  let notifiedCount = 0;
  for (const event of expiringEvents) {
    try {
      const tokens = await query<{ token: string; user_id: string }>(
        `SELECT pt.token, pt.user_id FROM push_tokens pt
         JOIN clique_members cm ON cm.user_id = pt.user_id
         WHERE cm.clique_id = $1`,
        [event.clique_id],
      );

      if (tokens.length > 0) {
        const failedTokens = await sendToMultipleTokens(
          tokens.map(t => t.token),
          'Event Expiring Soon',
          `"${event.name}" expires in 24 hours. Save your photos!`,
          { event_id: event.id },
        );

        // Create notification records
        const userIds = [...new Set(tokens.map(t => t.user_id))];
        for (const userId of userIds) {
          await execute(
            `INSERT INTO notifications (user_id, type, payload_json)
             VALUES ($1, 'event_expiring', $2::jsonb)`,
            [userId, JSON.stringify({ event_id: event.id, event_name: event.name, expires_at: event.expires_at })],
          );
        }

        if (failedTokens.length > 0) {
          await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failedTokens]);
        }

        notifiedCount += userIds.length;
      }
    } catch (err) {
      context.error(`Failed to notify for event ${event.id}:`, err);
    }
  }

  trackEvent('notification_sent', { type: 'event_expiring', count: String(notifiedCount) });
  context.log(`Sent ${notifiedCount} expiration notifications`);
}

// ====================================================================================
// refreshTokenPushTimer
// ====================================================================================
// Entra External ID (CIAM) has a hardcoded 12-hour refresh-token inactivity
// timeout. To keep users signed in, this timer finds users whose last
// authenticated API call was 9-11 hours ago and sends a SILENT FCM push that
// wakes the app in the background. The app handler performs a silent MSAL
// refresh, which resets the inactivity clock. Deduped to at most once per 6h
// per user. See docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md.
async function refreshTokenPushTimer(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();

  const candidates = await query<{ user_id: string; token: string; platform: string }>(
    `SELECT pt.user_id, pt.token, pt.platform
       FROM push_tokens pt
       JOIN users u ON u.id = pt.user_id
      WHERE u.last_activity_at BETWEEN NOW() - INTERVAL '11 hours' AND NOW() - INTERVAL '9 hours'
        AND (u.last_refresh_push_sent_at IS NULL
             OR u.last_refresh_push_sent_at < NOW() - INTERVAL '6 hours')`,
  );

  if (candidates.length === 0) {
    trackEvent('refresh_push_timer_ran', { candidates: '0', sent: '0', failed: '0' });
    context.log('refreshTokenPushTimer: no candidates in 9-11h inactivity window');
    return;
  }

  // Group tokens by user so we can batch the sent-at update.
  const byUser = new Map<string, string[]>();
  for (const c of candidates) {
    const tokens = byUser.get(c.user_id) ?? [];
    tokens.push(c.token);
    byUser.set(c.user_id, tokens);
  }

  let sentCount = 0;
  let failedCount = 0;
  const userIdsPushed: string[] = [];

  for (const [userId, tokens] of byUser.entries()) {
    try {
      const failed = await sendSilentToMultipleTokens(tokens, {
        type: 'token_refresh',
        userId,
      });
      sentCount += tokens.length - failed.length;
      failedCount += failed.length;

      if (failed.length > 0) {
        // Stale device tokens — same pattern as other timers
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [failed]);
      }

      if (tokens.length - failed.length > 0) {
        userIdsPushed.push(userId);
      }
    } catch (err) {
      context.error(`refreshTokenPushTimer: failed for user ${userId}:`, err);
      failedCount += tokens.length;
    }
  }

  if (userIdsPushed.length > 0) {
    await execute(
      'UPDATE users SET last_refresh_push_sent_at = NOW() WHERE id = ANY($1)',
      [userIdsPushed],
    );
  }

  trackEvent('refresh_push_timer_ran', {
    candidates: String(candidates.length),
    users: String(byUser.size),
    sent: String(sentCount),
    failed: String(failedCount),
  });
  context.log(
    `refreshTokenPushTimer: ${sentCount} silent pushes sent to ${userIdsPushed.length} users (${failedCount} failed)`,
  );
}

app.timer('cleanupExpired', {
  schedule: '0 */15 * * * *',
  handler: cleanupExpired,
});

app.timer('cleanupOrphans', {
  schedule: '0 */5 * * * *',
  handler: cleanupOrphans,
});

app.timer('notifyExpiring', {
  schedule: '0 0 * * * *',
  handler: notifyExpiring,
});

// Offset 7 minutes from cleanupExpired to avoid co-scheduling two DB-heavy
// timers on the same instance at the same second.
app.timer('refreshTokenPushTimer', {
  schedule: '0 7,22,37,52 * * * *',
  handler: refreshTokenPushTimer,
});
