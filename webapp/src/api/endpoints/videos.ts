import { api } from '../client';
import type { ReactionSummary, ReactionType, Video } from '../../models';

export async function listEventVideos(eventId: string): Promise<Video[]> {
  const res = await api.get<{ data: Video[] }>(`/api/events/${eventId}/videos`);
  return res.data.data;
}

export async function getVideo(videoId: string): Promise<Video> {
  const res = await api.get<{ data: Video }>(`/api/videos/${videoId}`);
  return res.data.data;
}

export interface VideoUploadUrl {
  video_id: string;
  block_urls: string[];
  commit_url: string;
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
): Promise<Video & { preview_url?: string }> {
  const res = await api.post<{ data: Video & { preview_url?: string } }>(
    `/api/events/${eventId}/videos`,
    { video_id: videoId, block_ids: blockIds },
  );
  return res.data.data;
}

export interface VideoPlayback {
  hls_manifest_url: string;
  mp4_fallback_url: string;
  poster_url: string;
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
