import { commitVideoUpload, getVideoUploadUrl, type VideoUploadUrl } from '../../api/endpoints/videos';
import { trackError, trackEvent } from '../../lib/ai';

const MAX_RETRIES = 5;
const RETRY_BASE_MS = 500;

export interface UploadProgress {
  uploadedBlocks: number;
  totalBlocks: number;
  bytesUploaded: number;
  totalBytes: number;
  percent: number;
}

export interface UploadResult {
  videoId: string;
  previewUrl?: string;
}

/**
 * Block-based video upload. Sequential blocks with retry+backoff, matching
 * the mobile `video_block_upload_service.dart` pattern. Progress is persisted
 * in sessionStorage keyed by videoId so a mid-upload network blip can pick up
 * where it left off — but note a full page reload loses the File reference,
 * so the uncommitted blocks will be garbage-collected by the backend's
 * 30-minute orphan cleanup.
 */
export async function uploadVideo(input: {
  file: File;
  eventId: string;
  durationSeconds: number;
  onProgress?: (p: UploadProgress) => void;
}): Promise<UploadResult> {
  const { file, eventId, durationSeconds, onProgress } = input;

  trackEvent('web_video_upload_started', {
    event_id: eventId,
    size_bytes: file.size,
    duration_seconds: Math.round(durationSeconds),
  });

  // Step 1: reserve the video row and get pre-signed block URLs.
  const reservation = await getVideoUploadUrl(eventId, {
    filename: file.name,
    size_bytes: file.size,
    duration_seconds: Math.round(durationSeconds),
  });

  const progressKey = `video_upload_progress_${reservation.videoId}`;
  const completed = new Set<string>(loadProgress(progressKey));

  onProgress?.(buildProgress(completed.size, reservation, file.size));

  // Step 2: upload each block sequentially. Retry each block up to 5 times
  // with exponential backoff. Skip blocks already persisted from a prior
  // attempt (client-side resume, matching mobile behavior).
  for (let i = 0; i < reservation.blockUploadUrls.length; i++) {
    const { blockId, url } = reservation.blockUploadUrls[i];
    if (completed.has(blockId)) continue;

    const start = i * reservation.blockSizeBytes;
    const end = Math.min(start + reservation.blockSizeBytes, file.size);
    const chunk = file.slice(start, end);

    await putBlockWithRetry(url, chunk, i);
    completed.add(blockId);
    saveProgress(progressKey, [...completed]);
    onProgress?.(buildProgress(completed.size, reservation, file.size));
  }

  // Step 3: commit the ordered block list. Backend calls Put Block List,
  // stamps the row `processing`, and enqueues the transcode job.
  const orderedIds = reservation.blockUploadUrls.map((b) => b.blockId);
  const commit = await commitVideoUpload(eventId, reservation.videoId, orderedIds);

  // Clear per-video progress once committed — future uploads won't collide.
  try {
    sessionStorage.removeItem(progressKey);
  } catch {
    /* quota / private mode — harmless */
  }

  trackEvent('web_video_upload_committed', {
    event_id: eventId,
    video_id: reservation.videoId,
    block_count: reservation.blockCount,
  });

  return { videoId: commit.videoId, previewUrl: commit.previewUrl };
}

async function putBlockWithRetry(url: string, chunk: Blob, index: number): Promise<void> {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const response = await fetch(url, {
        method: 'PUT',
        body: chunk,
        headers: {
          'Content-Type': 'application/octet-stream',
        },
      });
      if (!response.ok) {
        // 4xx errors are not retryable (permission, expired SAS, invalid state).
        // 5xx are transient — fall through to the retry path.
        if (response.status >= 400 && response.status < 500) {
          throw new UploadBlockError(index, response.status, 'non_retryable');
        }
        throw new UploadBlockError(index, response.status, 'retryable');
      }
      return;
    } catch (err) {
      attempt += 1;
      const kind = err instanceof UploadBlockError ? err.kind : 'retryable';
      if (kind === 'non_retryable' || attempt >= MAX_RETRIES) {
        trackError(err as Error, { stage: 'video_block_upload', blockIndex: index });
        throw err;
      }
      const backoff = RETRY_BASE_MS * 2 ** (attempt - 1);
      await new Promise((resolve) => setTimeout(resolve, backoff));
    }
  }
}

class UploadBlockError extends Error {
  constructor(
    public readonly blockIndex: number,
    public readonly status: number,
    public readonly kind: 'retryable' | 'non_retryable',
  ) {
    super(`Block ${blockIndex} failed with status ${status}`);
    this.name = 'UploadBlockError';
  }
}

function loadProgress(key: string): string[] {
  try {
    const raw = sessionStorage.getItem(key);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveProgress(key: string, ids: string[]): void {
  try {
    sessionStorage.setItem(key, JSON.stringify(ids));
  } catch {
    /* storage quota / private mode — non-fatal, we just lose resume */
  }
}

function buildProgress(
  uploaded: number,
  reservation: VideoUploadUrl,
  totalBytes: number,
): UploadProgress {
  return {
    uploadedBlocks: uploaded,
    totalBlocks: reservation.blockCount,
    bytesUploaded: Math.min(uploaded * reservation.blockSizeBytes, totalBytes),
    totalBytes,
    percent: reservation.blockCount === 0 ? 0 : Math.round((uploaded / reservation.blockCount) * 100),
  };
}
