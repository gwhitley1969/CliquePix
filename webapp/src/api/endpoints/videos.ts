import { api } from '../client';
import type { ReactionRecord, ReactionType, Video } from '../../models';

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

// Response shape per backend videos.ts getUploadUrl handler, camelized by the
// global response interceptor. Block URLs are COMPLETE — each is a pre-signed
// Azure Blob PUT with `?comp=block&blockid=<id>` already appended. The client
// just issues `PUT <url>` with the block bytes as the body.
export interface VideoUploadUrl {
  videoId: string;
  blobPath: string;
  blockSizeBytes: number;
  blockCount: number;
  blockUploadUrls: Array<{ blockId: string; url: string }>;
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

// Commit response — the backend returns 202 Accepted with the minimal shape
// below (NOT a full Video record). The feed refetch after commit or the
// Web PubSub `video_ready` event surfaces the complete row.
export interface VideoCommitResult {
  videoId: string;
  status: 'processing';
  previewUrl?: string;
  message?: string;
}

export async function commitVideoUpload(
  eventId: string,
  videoId: string,
  blockIds: string[],
): Promise<VideoCommitResult> {
  const res = await api.post<{ data: VideoCommitResult }>(
    `/api/events/${eventId}/videos`,
    { video_id: videoId, block_ids: blockIds },
  );
  return res.data.data;
}

// Playback: `hlsManifest` is RAW M3U8 TEXT (not a URL) with per-segment SAS
// URLs already rewritten by the backend. The client wraps it in a Blob URL
// before passing to hls.js or the native video element. MP4 fallback and
// poster are normal SAS URLs. All SAS windows are 15 minutes.
export interface VideoPlayback {
  videoId: string;
  hlsManifest: string;
  mp4FallbackUrl: string;
  posterUrl: string;
  durationSeconds: number;
  width: number;
  height: number;
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
  reactionType: ReactionType,
): Promise<ReactionRecord> {
  const res = await api.post<{ data: ReactionRecord }>(`/api/videos/${videoId}/reactions`, {
    reaction_type: reactionType,
  });
  return res.data.data;
}

export async function removeVideoReaction(videoId: string, reactionId: string): Promise<void> {
  await api.delete(`/api/videos/${videoId}/reactions/${reactionId}`);
}
