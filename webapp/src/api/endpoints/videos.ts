import { api } from '../client';
import type { ReactionSummary, ReactionType, Video } from '../../models';

export async function listEventVideos(eventId: string): Promise<Video[]> {
  // Backend envelope: { data: { videos: [...] } }
  const res = await api.get<{ data: { videos: Video[] } }>(
    `/api/events/${eventId}/videos`,
  );
  return res.data.data.videos ?? [];
}

export async function getVideo(videoId: string): Promise<Video> {
  const res = await api.get<{ data: Video }>(`/api/videos/${videoId}`);
  return res.data.data;
}

// Response fields arrive camelCased courtesy of the global interceptor.
export interface VideoUploadUrl {
  videoId: string;
  blockUrls: string[];
  commitUrl: string;
}

export async function getVideoUploadUrl(
  eventId: string,
  meta: { filename: string; size_bytes: number; duration_seconds: number },
): Promise<VideoUploadUrl> {
  const res = await api.post<{ data: VideoUploadUrl }>(
    `/api/events/${eventId}/videos/upload-url`,
    meta,
  );
  return res.data.data;
}

export async function commitVideoUpload(
  eventId: string,
  videoId: string,
  blockIds: string[],
): Promise<Video & { previewUrl?: string }> {
  const res = await api.post<{ data: Video & { previewUrl?: string } }>(
    `/api/events/${eventId}/videos`,
    { video_id: videoId, block_ids: blockIds },
  );
  return res.data.data;
}

export interface VideoPlayback {
  hlsManifestUrl: string;
  mp4FallbackUrl: string;
  posterUrl: string;
}

export async function getVideoPlayback(videoId: string): Promise<VideoPlayback> {
  const res = await api.get<{ data: VideoPlayback }>(`/api/videos/${videoId}/playback`);
  return res.data.data;
}

export async function deleteVideo(videoId: string): Promise<void> {
  await api.delete(`/api/videos/${videoId}`);
}

export async function addVideoReaction(
  videoId: string,
  type: ReactionType,
): Promise<ReactionSummary> {
  const res = await api.post<{ data: ReactionSummary }>(`/api/videos/${videoId}/reactions`, {
    type,
  });
  return res.data.data;
}

export async function removeVideoReaction(videoId: string, reactionId: string): Promise<void> {
  await api.delete(`/api/videos/${videoId}/reactions/${reactionId}`);
}
