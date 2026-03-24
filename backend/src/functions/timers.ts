import { app, InvocationContext, Timer } from '@azure/functions';
import { query, queryOne, execute } from '../shared/services/dbService';
import { deleteBlob } from '../shared/services/blobService';
import { sendToMultipleTokens } from '../shared/services/fcmService';
import { trackEvent } from '../shared/services/telemetryService';
import { initTelemetry } from '../shared/services/telemetryService';

async function cleanupExpired(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running expired photo cleanup');

  const expiredPhotos = await query<any>(
    `SELECT id, blob_path, thumbnail_blob_path, event_id
     FROM photos WHERE status = 'active' AND expires_at < NOW()
     LIMIT 500`,
  );

  if (expiredPhotos.length === 0) {
    context.log('No expired photos to clean up');
    return;
  }

  let deletedCount = 0;
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
      deletedCount++;
    } catch (err) {
      context.error(`Failed to clean up photo ${photo.id}:`, err);
    }
  }

  // Check for events that should be marked expired
  await execute(
    `UPDATE events SET status = 'expired'
     WHERE status = 'active' AND expires_at < NOW()
     AND NOT EXISTS (
       SELECT 1 FROM photos WHERE event_id = events.id AND status = 'active'
     )`,
  );

  trackEvent('expired_photos_deleted', { count: String(deletedCount) });
  context.log(`Cleaned up ${deletedCount} expired photos`);
}

async function cleanupOrphans(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running orphan upload cleanup');

  const orphans = await query<any>(
    `SELECT id, blob_path FROM photos
     WHERE status = 'pending' AND created_at < NOW() - INTERVAL '10 minutes'
     LIMIT 200`,
  );

  if (orphans.length === 0) {
    context.log('No orphaned uploads to clean up');
    return;
  }

  let cleanedCount = 0;
  for (const orphan of orphans) {
    try {
      await deleteBlob(orphan.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [orphan.id]);
      cleanedCount++;
    } catch (err) {
      context.error(`Failed to clean up orphan ${orphan.id}:`, err);
    }
  }

  trackEvent('orphaned_uploads_cleaned', { count: String(cleanedCount) });
  context.log(`Cleaned up ${cleanedCount} orphaned uploads`);
}

async function notifyExpiring(myTimer: Timer, context: InvocationContext): Promise<void> {
  initTelemetry();
  context.log('Running expiration notification check');

  const expiringEvents = await query<any>(
    `SELECT e.id, e.name, e.circle_id, e.expires_at
     FROM events e
     WHERE e.status = 'active'
       AND e.expires_at > NOW() + INTERVAL '23 hours'
       AND e.expires_at <= NOW() + INTERVAL '25 hours'`,
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
         JOIN circle_members cm ON cm.user_id = pt.user_id
         WHERE cm.circle_id = $1`,
        [event.circle_id],
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

  trackEvent('expiration_notifications_sent', { count: String(notifiedCount) });
  context.log(`Sent ${notifiedCount} expiration notifications`);
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
