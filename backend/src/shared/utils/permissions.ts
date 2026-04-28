/**
 * Authorization helper for media (photo + video) deletion.
 *
 * Two roles can delete a media item:
 *   - `'uploader'`  — the user who uploaded it (`photos.uploaded_by_user_id`)
 *   - `'organizer'` — the creator of the event the media belongs to
 *                     (`events.created_by_user_id`). This is the moderation
 *                     path that lets event organizers remove inappropriate
 *                     content uploaded by other clique members.
 *
 * Uploader takes precedence when both apply (an organizer deleting their
 * own media in their own event is logged as `'uploader'`, not moderation).
 *
 * Both ID columns became nullable in migration 004 (ON DELETE SET NULL on
 * user account deletion). The truthiness guards prevent `null === null`
 * pathological matches if `authUserId` is ever empty — auth middleware
 * should already reject empty IDs, but the guard is defense in depth.
 */

export type MediaDeleterRole = 'uploader' | 'organizer';

export interface CanDeleteMediaInput {
  uploadedByUserId: string | null;
  eventCreatedByUserId: string | null;
  authUserId: string;
}

export function canDeleteMedia(input: CanDeleteMediaInput): MediaDeleterRole | null {
  if (!input.authUserId) return null;
  if (input.uploadedByUserId && input.authUserId === input.uploadedByUserId) {
    return 'uploader';
  }
  if (input.eventCreatedByUserId && input.authUserId === input.eventCreatedByUserId) {
    return 'organizer';
  }
  return null;
}
