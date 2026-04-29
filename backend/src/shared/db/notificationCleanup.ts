// Stale-notification cleanup helpers.
//
// The `notifications` table has only one FK (`user_id` → users). Target IDs
// (`event_id`, `photo_id`, `video_id`, `clique_id`) live inside JSONB
// `payload_json` with no FK and no cascade. So when an event / photo / video
// / clique is hard-deleted, every OTHER user's notifications about it survive
// indefinitely — and tapping one 404s on the resource fetch.
//
// Two-tier strategy:
//   - Synchronous helpers (deleteNotificationsFor*) called from user-visible
//     delete sites for immediate UX feedback.
//   - Periodic sweep (sweepStaleNotifications) called from the existing 15-min
//     timer. Catches everything synchronous wiring missed (account-deletion
//     bulk-photo-delete in auth.ts, sole-owner-leaves clique-delete in
//     cliques.ts, future delete sites we forget to wire).
//
// IMPORTANT: every NEW delete site that removes an event/photo/video/clique
// must EITHER call one of the targeted helpers below OR rely on the periodic
// sweep covering it within 15 minutes. See docs/NOTIFICATION_SYSTEM.md.

import { execute } from '../services/dbService';

export async function deleteNotificationsForEvent(eventId: string): Promise<number> {
  return execute(
    `DELETE FROM notifications WHERE payload_json->>'event_id' = $1`,
    [eventId],
  );
}

export async function deleteNotificationsForPhoto(photoId: string): Promise<number> {
  return execute(
    `DELETE FROM notifications WHERE payload_json->>'photo_id' = $1`,
    [photoId],
  );
}

export async function deleteNotificationsForVideo(videoId: string): Promise<number> {
  return execute(
    `DELETE FROM notifications WHERE payload_json->>'video_id' = $1`,
    [videoId],
  );
}

export async function deleteNotificationsForClique(cliqueId: string): Promise<number> {
  return execute(
    `DELETE FROM notifications WHERE payload_json->>'clique_id' = $1`,
    [cliqueId],
  );
}

// Sweep: remove every notification whose target resource no longer exists.
// Four independent DELETEs — each handles its own JSONB key. Idempotent and
// safe to re-run. Run by the 15-min `cleanupExpired` timer in timers.ts AFTER
// the bulk event hard-delete so newly-orphaned event_* rows are caught in the
// same pass.
//
// `photos` table hosts both photo and video rows (migration 007's media_type
// column). Both photo_id and video_id sub-queries join on the same `photos`
// table by design.
export async function sweepStaleNotifications(): Promise<{
  events: number;
  photos: number;
  videos: number;
  cliques: number;
}> {
  const events = await execute(
    `DELETE FROM notifications
     WHERE payload_json ? 'event_id'
       AND NOT EXISTS (
         SELECT 1 FROM events e WHERE e.id::text = notifications.payload_json->>'event_id'
       )`,
  );
  // Photos and videos use soft-delete (UPDATE photos SET status='deleted')
  // when the user deletes them. The row stays in the table — getPhoto /
  // getVideo filter on status='active' so the client sees 404 anyway. So
  // treat soft-deleted rows as effectively gone for notification purposes.
  const photos = await execute(
    `DELETE FROM notifications
     WHERE payload_json ? 'photo_id'
       AND NOT EXISTS (
         SELECT 1 FROM photos p
         WHERE p.id::text = notifications.payload_json->>'photo_id'
           AND p.status = 'active'
       )`,
  );
  const videos = await execute(
    `DELETE FROM notifications
     WHERE payload_json ? 'video_id'
       AND NOT EXISTS (
         SELECT 1 FROM photos p
         WHERE p.id::text = notifications.payload_json->>'video_id'
           AND p.status = 'active'
       )`,
  );
  const cliques = await execute(
    `DELETE FROM notifications
     WHERE payload_json ? 'clique_id'
       AND NOT EXISTS (
         SELECT 1 FROM cliques c WHERE c.id::text = notifications.payload_json->>'clique_id'
       )`,
  );
  return { events, photos, videos, cliques };
}
