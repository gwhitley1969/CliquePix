// Shared types for the CliquePix video transcoder

/**
 * Message format dequeued from video-transcode-queue.
 * Producer: backend Function `POST /api/events/{eventId}/videos` (commit endpoint).
 * Consumer: this transcoder runner.
 */
export interface TranscodeJobMessage {
  videoId: string;
  blobPath: string;
  eventId: string;
  cliqueId: string;
}

/**
 * ffprobe validation result. If `valid: false`, the runner reports failure
 * and exits without transcoding.
 */
export type FfprobeResult =
  | {
      valid: true;
      durationSeconds: number;
      width: number;
      height: number;
      isHdr: boolean;
      videoCodec: 'h264' | 'hevc';
      audioCodec: string | null;
      container: 'mp4' | 'mov';
    }
  | {
      valid: false;
      errorCode: ValidationErrorCode;
      errorMessage: string;
    };

export type ValidationErrorCode =
  | 'UNSUPPORTED_CONTAINER'
  | 'UNSUPPORTED_CODEC'
  | 'DURATION_EXCEEDED'
  | 'CORRUPT_MEDIA'
  | 'HDR_CONVERSION_FAILED';

/**
 * Payload sent to the Function callback endpoint when transcoding completes.
 */
export interface CallbackSuccessPayload {
  video_id: string;
  success: true;
  hls_manifest_blob_path: string;
  mp4_fallback_blob_path: string;
  poster_blob_path: string;
  duration_seconds: number;
  width: number;
  height: number;
  is_hdr_source: boolean;
  normalized_to_sdr: boolean;
  // Performance telemetry (added 2026-04-08, stream-copy fast path)
  processing_mode: 'transcode' | 'stream_copy';
  // Only set when the fast path was attempted but failed and we fell through
  // to the slow re-encode path. null in all other cases.
  fast_path_failure_reason?: string | null;
}

export interface CallbackFailurePayload {
  video_id: string;
  success: false;
  error_code: string;
  error_message: string;
}

export type CallbackPayload = CallbackSuccessPayload | CallbackFailurePayload;
