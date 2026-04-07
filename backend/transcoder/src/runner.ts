// CliquePix transcoder runner — Container Apps Job entry point.
//
// One execution = one queue message processed.
// On success: deletes the queue message and exits 0.
// On failure: leaves the queue message visible (after the visibility timeout)
// for retry, exits non-zero.
//
// LOCAL_MODE: when set to "true", the runner reads from a local file path
// (LOCAL_INPUT_FILE) and writes outputs to LOCAL_OUTPUT_DIR. Skips queue
// dequeue and callback POST. Used for FFmpeg parameter tuning and integration
// testing without round-tripping through Azure.

import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { dequeueMessage, deleteMessage } from './queueService';
import { downloadBlob, uploadBlob, uploadDirectory, setBlobTier } from './blobService';
import { ffprobe, transcodeHls, transcodeMp4Fallback, extractPoster } from './ffmpegService';
import { postCallback } from './callbackService';
import type { CallbackPayload, FfprobeResult } from './types';

const LOCAL_MODE = process.env.LOCAL_MODE === 'true';

async function main(): Promise<void> {
  if (LOCAL_MODE) {
    await runLocalMode();
  } else {
    await runQueueMode();
  }
}

// ====================================================================================
// Local mode — used for FFmpeg parameter tuning during dev
// ====================================================================================

async function runLocalMode(): Promise<void> {
  const inputFile = process.env.LOCAL_INPUT_FILE;
  const outputDir = process.env.LOCAL_OUTPUT_DIR ?? '/output';

  if (!inputFile) {
    console.error('LOCAL_MODE requires LOCAL_INPUT_FILE env var');
    process.exit(1);
  }
  if (!fs.existsSync(inputFile)) {
    console.error(`Input file not found: ${inputFile}`);
    process.exit(1);
  }

  console.log(`[LOCAL_MODE] Processing ${inputFile} → ${outputDir}`);

  const probeResult = await ffprobe(inputFile);
  if (!probeResult.valid) {
    console.error(`[LOCAL_MODE] Validation failed: ${probeResult.errorCode} — ${probeResult.errorMessage}`);
    process.exit(1);
  }
  console.log(`[LOCAL_MODE] ffprobe: ${probeResult.width}x${probeResult.height} ${probeResult.videoCodec} ${probeResult.durationSeconds.toFixed(1)}s${probeResult.isHdr ? ' HDR' : ''}`);

  await fs.promises.mkdir(outputDir, { recursive: true });
  await fs.promises.mkdir(path.join(outputDir, 'hls'), { recursive: true });

  const start = Date.now();
  await transcodeHls(inputFile, path.join(outputDir, 'hls'));
  const hlsTime = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`[LOCAL_MODE] HLS done in ${hlsTime}s → ${outputDir}/hls/manifest.m3u8`);

  const mp4Start = Date.now();
  await transcodeMp4Fallback(inputFile, path.join(outputDir, 'fallback.mp4'));
  console.log(`[LOCAL_MODE] MP4 fallback done in ${((Date.now() - mp4Start) / 1000).toFixed(1)}s → ${outputDir}/fallback.mp4`);

  const posterStart = Date.now();
  await extractPoster(inputFile, path.join(outputDir, 'poster.jpg'), probeResult.durationSeconds);
  console.log(`[LOCAL_MODE] Poster done in ${((Date.now() - posterStart) / 1000).toFixed(1)}s → ${outputDir}/poster.jpg`);

  const totalTime = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`[LOCAL_MODE] Total: ${totalTime}s`);
  console.log(`[LOCAL_MODE] Outputs ready in ${outputDir}/`);
  console.log(`[LOCAL_MODE] Inspect: ls -la ${outputDir}/hls/ && cat ${outputDir}/hls/manifest.m3u8`);
}

// ====================================================================================
// Queue mode — production path
// ====================================================================================

async function runQueueMode(): Promise<void> {
  console.log('[runner] Polling video-transcode-queue...');
  const message = await dequeueMessage();
  if (!message) {
    console.log('[runner] No messages in queue, exiting cleanly');
    return;
  }

  const { videoId, blobPath, eventId, cliqueId } = message.payload;
  console.log(`[runner] Processing video ${videoId} from event ${eventId}`);

  // Use a unique work directory under /tmp to avoid collisions if multiple
  // job replicas ever land on the same host
  const workDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), `transcoder-${videoId}-`));
  const localInput = path.join(workDir, 'original.mp4');
  const hlsDir = path.join(workDir, 'hls');
  const fallbackPath = path.join(workDir, 'fallback.mp4');
  const posterPath = path.join(workDir, 'poster.jpg');

  try {
    // 1. Download original from blob storage
    console.log(`[runner] Downloading ${blobPath}`);
    await downloadBlob(blobPath, localInput);

    // 2. Validate with ffprobe
    const probeResult = await ffprobe(localInput);
    if (!probeResult.valid) {
      console.error(`[runner] Validation failed: ${probeResult.errorCode}`);
      await postCallback({
        video_id: videoId,
        success: false,
        error_code: probeResult.errorCode,
        error_message: probeResult.errorMessage,
      });
      await deleteMessage(message);
      return;
    }
    console.log(`[runner] Validated: ${probeResult.width}x${probeResult.height} ${probeResult.videoCodec} ${probeResult.durationSeconds.toFixed(1)}s${probeResult.isHdr ? ' HDR' : ''}`);

    // 3. Transcode HLS, MP4 fallback, poster
    console.log('[runner] Transcoding HLS...');
    await fs.promises.mkdir(hlsDir, { recursive: true });
    await transcodeHls(localInput, hlsDir);

    console.log('[runner] Transcoding MP4 fallback...');
    await transcodeMp4Fallback(localInput, fallbackPath);

    console.log('[runner] Extracting poster...');
    await extractPoster(localInput, posterPath, probeResult.durationSeconds);

    // 4. Upload outputs to blob storage at expected paths.
    // The "photos/" prefix is the historical convention used throughout the
    // codebase — the container is named "photos" AND the path inside the
    // container starts with "photos/" to mirror the project's blob naming
    // (matches photos.ts and videos.ts blob path construction).
    const basePrefix = `photos/${cliqueId}/${eventId}/${videoId}`;
    console.log(`[runner] Uploading outputs to ${basePrefix}/`);
    await uploadDirectory(hlsDir, `${basePrefix}/hls`);
    await uploadBlob(fallbackPath, `${basePrefix}/fallback.mp4`, 'video/mp4');
    await uploadBlob(posterPath, `${basePrefix}/poster.jpg`, 'image/jpeg');

    // 5. Move the original master to Cool tier (Decision 7 — written once, read never)
    try {
      await setBlobTier(blobPath, 'Cool');
      console.log('[runner] Moved original master to Cool tier');
    } catch (err) {
      console.warn('[runner] Failed to set Cool tier (non-fatal):', err);
    }

    // 6. Report success to Function callback
    const successPayload: CallbackPayload = {
      video_id: videoId,
      success: true,
      hls_manifest_blob_path: `${basePrefix}/hls/manifest.m3u8`,
      mp4_fallback_blob_path: `${basePrefix}/fallback.mp4`,
      poster_blob_path: `${basePrefix}/poster.jpg`,
      duration_seconds: Math.round(probeResult.durationSeconds),
      width: probeResult.width,
      height: probeResult.height,
      is_hdr_source: probeResult.isHdr,
      normalized_to_sdr: probeResult.isHdr,
    };
    console.log('[runner] Posting success callback');
    await postCallback(successPayload);

    // 7. Delete queue message (only after callback succeeds)
    await deleteMessage(message);
    console.log(`[runner] Done processing ${videoId}`);
  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('[runner] Transcoding failed:', errorMessage);
    try {
      await postCallback({
        video_id: videoId,
        success: false,
        error_code: 'TRANSCODE_ERROR',
        error_message: errorMessage,
      });
      // If callback succeeds, delete the message — we've reported the failure
      await deleteMessage(message);
    } catch (callbackErr) {
      console.error('[runner] Failed to post failure callback:', callbackErr);
      // Don't delete the message — let it retry via visibility timeout
      // Eventually it'll go to the poison queue after 5 attempts
      throw err;
    }
  } finally {
    // Clean up local work dir
    try {
      await fs.promises.rm(workDir, { recursive: true, force: true });
    } catch (_) {
      // best effort
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('[runner] Fatal error:', err);
    process.exit(1);
  });
