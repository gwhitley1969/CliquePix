import { api } from '../client';
import type { Photo, ReactionSummary, ReactionType } from '../../models';

export async function listEventPhotos(eventId: string): Promise<Photo[]> {
  const res = await api.get<{ data: Photo[] }>(`/api/events/${eventId}/photos`);
  return res.data.data;
}

export async function getPhoto(photoId: string): Promise<Photo> {
  const res = await api.get<{ data: Photo }>(`/api/photos/${photoId}`);
  return res.data.data;
}

export interface PhotoUploadUrl {
  photo_id: string;
  upload_url: string;
}

export async function getPhotoUploadUrl(
  eventId: string,
  meta: { mime_type: string; file_size_bytes: number; width: number; height: number },
): Promise<PhotoUploadUrl> {
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
  type: ReactionType,
): Promise<ReactionSummary> {
  const res = await api.post<{ data: ReactionSummary }>(`/api/photos/${photoId}/reactions`, {
    type,
  });
  return res.data.data;
}

export async function removePhotoReaction(photoId: string, reactionId: string): Promise<void> {
  await api.delete(`/api/photos/${photoId}/reactions/${reactionId}`);
}
