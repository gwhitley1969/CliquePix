/**
 * Client-side pre-checks for video uploads. The backend duplicates these
 * (see backend/src/functions/videos.ts lines 375-379) but failing fast here
 * saves bandwidth on slow connections and surfaces errors immediately.
 */

export const MAX_VIDEO_SIZE_BYTES = 500 * 1024 * 1024; // 500 MB
export const MAX_VIDEO_DURATION_SECONDS = 5 * 60; // 5 min
export const ALLOWED_VIDEO_EXTENSIONS = ['mp4', 'mov'] as const;

export type VideoValidationResult =
  | { ok: true; durationSeconds: number }
  | { ok: false; reason: string };

export async function validateVideoFile(file: File): Promise<VideoValidationResult> {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? '';
  if (!ALLOWED_VIDEO_EXTENSIONS.includes(ext as (typeof ALLOWED_VIDEO_EXTENSIONS)[number])) {
    return {
      ok: false,
      reason: `Unsupported format. Upload an MP4 or MOV file.`,
    };
  }

  if (file.size > MAX_VIDEO_SIZE_BYTES) {
    return {
      ok: false,
      reason: `Video is ${(file.size / 1024 / 1024).toFixed(0)} MB. Max is 500 MB.`,
    };
  }

  try {
    const durationSeconds = await probeVideoDuration(file);
    if (durationSeconds > MAX_VIDEO_DURATION_SECONDS) {
      return {
        ok: false,
        reason: `Video is ${Math.round(durationSeconds)}s long. Max is 5 minutes.`,
      };
    }
    return { ok: true, durationSeconds };
  } catch {
    return {
      ok: false,
      reason: 'Could not read the video — the file may be corrupted or encoded in an unsupported codec.',
    };
  }
}

function probeVideoDuration(file: File): Promise<number> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement('video');
    video.preload = 'metadata';
    const cleanup = () => {
      URL.revokeObjectURL(url);
      video.remove();
    };
    video.onloadedmetadata = () => {
      const d = video.duration;
      cleanup();
      if (!Number.isFinite(d) || d <= 0) {
        reject(new Error('invalid_duration'));
      } else {
        resolve(d);
      }
    };
    video.onerror = () => {
      cleanup();
      reject(new Error('metadata_load_failed'));
    };
    video.src = url;
  });
}
