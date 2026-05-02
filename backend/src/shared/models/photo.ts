// The `photos` table now hosts both photos AND videos. The table name is
// historical (kept for v1 to minimize migration churn); will be renamed to
// `media` post-v1. See migration 007 and docs/VIDEO_ARCHITECTURE_DECISIONS.md
// Decision 1.

export type MediaType = 'photo' | 'video';

// Status enum extended in migration 007:
//   pending    - upload-url issued, blob not yet committed
//   active     - photo: blob uploaded; video: transcoding complete
//   processing - video only: blocks committed, transcoding in progress
//   rejected   - video only: ffprobe validation failed
//   deleted    - cleanup job ran (final state)
export type MediaStatus = 'pending' | 'active' | 'processing' | 'rejected' | 'deleted';

// Photo MIME types (existing); video MIME types added in migration 007
export type PhotoMimeType = 'image/jpeg' | 'image/png';
export type VideoMimeType = 'video/mp4' | 'video/quicktime';
export type MediaMimeType = PhotoMimeType | VideoMimeType;

// Source video container (mp4 or mov)
export type VideoSourceContainer = 'mp4' | 'mov';

// Source video codec (h264 or hevc)
export type VideoSourceCodec = 'h264' | 'hevc';

// Video processing pipeline state (independent of high-level status)
export type VideoProcessingStatus = 'pending' | 'queued' | 'running' | 'complete' | 'failed';

/**
 * The Photo interface represents one row in the `photos` table.
 * Despite the name, it can be either a photo or a video — distinguished
 * by the `media_type` column.
 *
 * Photo-specific fields are non-null for media_type='photo'.
 * Video-specific fields are non-null for media_type='video' (filled in
 * progressively as the transcoder completes).
 */
export interface Photo {
  // Core columns (all media types)
  id: string;
  event_id: string;
  uploaded_by_user_id: string;
  blob_path: string;
  original_filename: string | null;
  mime_type: MediaMimeType;
  width: number | null;
  height: number | null;
  file_size_bytes: number | null;
  status: MediaStatus;
  created_at: Date;
  expires_at: Date;
  deleted_at: Date | null;

  // Discriminator (added migration 007)
  media_type: MediaType;

  // Photo-specific (null for videos)
  thumbnail_blob_path: string | null;

  // Video-specific (all null for photos; populated by transcoder callback)
  duration_seconds: number | null;
  source_container: VideoSourceContainer | null;
  source_video_codec: VideoSourceCodec | null;
  source_audio_codec: string | null;
  is_hdr_source: boolean | null;
  normalized_to_sdr: boolean | null;
  hls_manifest_blob_path: string | null;
  mp4_fallback_blob_path: string | null;
  poster_blob_path: string | null;
  processing_status: VideoProcessingStatus | null;
  processing_error: string | null;
}

/**
 * Photo with view-time SAS URLs added by the API. Used by the photo feed.
 */
export interface PhotoWithUrls extends Photo {
  original_url: string;
  thumbnail_url: string | null;
  reaction_counts: Record<string, number>;
  user_reactions: string[];
  // Up to 3 distinct most-recent reactor avatars (de-duped by user_id) for
  // the "who reacted?" strip rendered above the reaction pill row in the
  // mobile + web clients. Empty array when there are no reactions.
  top_reactors: import('./reaction').ReactorAvatar[];
  // Uploader denormalization. null when the uploader has been deleted
  // (photos.uploaded_by_user_id FK is ON DELETE SET NULL) — callers
  // must handle nulls rather than undefineds.
  uploaded_by_name: string | null;
  uploaded_by_avatar_url: string | null;
  uploaded_by_avatar_thumb_url: string | null;
  uploaded_by_avatar_updated_at: string | null;
  uploaded_by_avatar_frame_preset: number;
}

/**
 * Video with view-time SAS URLs added by the API. Used by the video feed
 * and the playback endpoint.
 *
 * Note: `hls_manifest` is the REWRITTEN manifest text (per-segment SAS URLs
 * already inlined), not the raw blob. The client treats it as opaque.
 */
export interface VideoWithUrls extends Photo {
  poster_url: string | null;
  mp4_fallback_url: string | null;
  hls_manifest?: string;
  reaction_counts: Record<string, number>;
  user_reactions: string[];
  // Up to 3 distinct most-recent reactor avatars (de-duped by user_id). See
  // PhotoWithUrls.top_reactors above — same semantics for video cards.
  top_reactors: import('./reaction').ReactorAvatar[];
  // Uploader denormalization. null when the uploader has been deleted
  // (photos.uploaded_by_user_id FK is ON DELETE SET NULL).
  uploaded_by_name: string | null;
  uploaded_by_avatar_url: string | null;
  uploaded_by_avatar_thumb_url: string | null;
  uploaded_by_avatar_updated_at: string | null;
  uploaded_by_avatar_frame_preset: number;
  // Instant preview: a read-only SAS URL for the ORIGINAL blob, returned only
  // when the caller is the uploader AND the video is still processing/pending.
  // The uploader's client uses this to play the video immediately without
  // waiting for the transcoder. Null for everyone else and for active videos.
  preview_url?: string | null;
}

// Backwards-compat alias for code paths still using PhotoStatus
// (will be removed once all callers are migrated to MediaStatus)
export type PhotoStatus = MediaStatus;
export type MimeType = PhotoMimeType;
