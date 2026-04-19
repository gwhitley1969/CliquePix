import { api } from '../client';
import type { Photo, ReactionRecord, ReactionType } from '../../models';

export async function listEventPhotos(eventId: string): Promise<Photo[]> {
  // Backend envelope: { data: { photos: [...], nextCursor: string|null } }
  const res = await api.get<{ data: { photos: Photo[]; nextCursor?: string | null } }>(
    `/api/events/${eventId}/photos`,
  );
  return res.data.data.photos ?? [];
}

export async function getPhoto(photoId: string): Promise<Photo> {
  const res = await api.get<{ data: Photo }>(`/api/photos/${photoId}`);
  return res.data.data;
}

// Response fields arrive as snake_case from the backend and get camelCased by
// the global response interceptor, so this interface matches post-transform shape.
export interface PhotoUploadUrl {
  photoId: string;
  uploadUrl: string;
}

export async function getPhotoUploadUrl(
  eventId: string,
  meta: { mime_type: string; file_size_bytes: number; width: number; height: number },
): Promise<PhotoUploadUrl> {
  // Request body stays snake_case because the backend validates on those keys;
  // our global camelize runs on RESPONSES only, not requests.
  const res = await api.post<{ data: PhotoUploadUrl }>(
    `/api/events/${eventId}/photos/upload-url`,
    meta,
  );
  return res.data.data;
}

export async function confirmPhotoUpload(
  eventId: string,
  photoId: string,
  meta: { mime_type: string; width: number; height: number; file_size_bytes: number },
): Promise<Photo> {
  const res = await api.post<{ data: Photo }>(`/api/events/${eventId}/photos`, {
    photo_id: photoId,
    ...meta,
  });
  return res.data.data;
}

export async function deletePhoto(photoId: string): Promise<void> {
  await api.delete(`/api/photos/${photoId}`);
}

export async function addPhotoReaction(
  photoId: string,
  reactionType: ReactionType,
): Promise<ReactionRecord> {
  // Backend validates on `reaction_type` in the body — not `type`. POST is
  // upsert-idempotent via ON CONFLICT, so re-sending an existing reaction
  // returns the same ID (which the caller captures to enable a later DELETE).
  const res = await api.post<{ data: ReactionRecord }>(`/api/photos/${photoId}/reactions`, {
    reaction_type: reactionType,
  });
  return res.data.data;
}

export async function removePhotoReaction(photoId: string, reactionId: string): Promise<void> {
  await api.delete(`/api/photos/${photoId}/reactions/${reactionId}`);
}
