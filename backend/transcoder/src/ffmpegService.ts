// FFmpeg service — ffprobe validation + transcoding invocations
//
// All FFmpeg operations are wrapped in spawned child processes via execFile.
// We do NOT use a Node FFmpeg binding (e.g., fluent-ffmpeg) because:
//   1. The container has FFmpeg as a system binary (jrottenberg/ffmpeg base image)
//   2. Bindings add a layer of indirection that's harder to debug
//   3. Direct execFile gives us full visibility into stderr for parsing errors
//
// ====================================================================================
// FFmpeg parameters — approved defaults (Gene, 2026-04-07)
// ====================================================================================
// Option B "balanced defaults" was chosen as the v1 starting point:
//   preset=medium, crf=23, audio=128k, hls_time=4
// Re-tune in Phase 7 polish based on production transcode timing telemetry.
// ====================================================================================

import { execFile } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import type { FfprobeResult } from './types';

const execFileP = promisify(execFile);

const FFMPEG_BIN = process.env.FFMPEG_PATH ?? 'ffmpeg';
const FFPROBE_BIN = process.env.FFPROBE_PATH ?? 'ffprobe';

// Hard limits from architecture decisions
const MAX_DURATION_SECONDS = 5 * 60; // 5 minutes (Decision 0 / spec)
const MAX_OUTPUT_HEIGHT = 1080; // Single 1080p rendition (Decision 3)
const HLS_SEGMENT_DURATION = 4; // 4-second segments for VOD (Decision 3 standard)

// ====================================================================================
// ffprobe — server-side authoritative validation
// ====================================================================================

interface FfprobeStream {
  codec_type: string;
  codec_name?: string;
  width?: number;
  height?: number;
  duration?: string;
  color_transfer?: string;
  color_primaries?: string;
}

interface FfprobeOutput {
  format?: {
    format_name?: string;
    duration?: string;
  };
  streams?: FfprobeStream[];
}

/**
 * Run ffprobe against a local file and validate it against CliquePix's
 * accepted-format rules. Returns a discriminated result.
 *
 * Validation rules (per architecture Q3):
 *   - Container must be mp4 or mov
 *   - Video codec must be h264 or hevc
 *   - Duration must be ≤ 5 minutes
 *   - File must be parseable (corrupt files return CORRUPT_MEDIA)
 */
export async function ffprobe(localPath: string): Promise<FfprobeResult> {
  let raw: FfprobeOutput;
  try {
    const { stdout } = await execFileP(FFPROBE_BIN, [
      '-v', 'error',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      localPath,
    ]);
    raw = JSON.parse(stdout) as FfprobeOutput;
  } catch (err) {
    return {
      valid: false,
      errorCode: 'CORRUPT_MEDIA',
      errorMessage: err instanceof Error ? err.message : String(err),
    };
  }

  // Container check
  const formatName = raw.format?.format_name ?? '';
  let container: 'mp4' | 'mov';
  if (formatName.includes('mp4')) {
    container = 'mp4';
  } else if (formatName.includes('mov') || formatName.includes('quicktime')) {
    container = 'mov';
  } else {
    return {
      valid: false,
      errorCode: 'UNSUPPORTED_CONTAINER',
      errorMessage: `Unsupported container: ${formatName}`,
    };
  }

  // Duration check
  const durationStr = raw.format?.duration;
  if (!durationStr) {
    return {
      valid: false,
      errorCode: 'CORRUPT_MEDIA',
      errorMessage: 'ffprobe returned no duration',
    };
  }
  const durationSeconds = parseFloat(durationStr);
  if (Number.isNaN(durationSeconds)) {
    return {
      valid: false,
      errorCode: 'CORRUPT_MEDIA',
      errorMessage: `Invalid duration: ${durationStr}`,
    };
  }
  if (durationSeconds > MAX_DURATION_SECONDS) {
    return {
      valid: false,
      errorCode: 'DURATION_EXCEEDED',
      errorMessage: `Duration ${durationSeconds.toFixed(1)}s exceeds max ${MAX_DURATION_SECONDS}s`,
    };
  }

  // Find video stream
  const videoStream = raw.streams?.find((s) => s.codec_type === 'video');
  if (!videoStream || !videoStream.codec_name) {
    return {
      valid: false,
      errorCode: 'CORRUPT_MEDIA',
      errorMessage: 'No video stream found',
    };
  }

  // Codec check
  let videoCodec: 'h264' | 'hevc';
  if (videoStream.codec_name === 'h264') {
    videoCodec = 'h264';
  } else if (videoStream.codec_name === 'hevc') {
    videoCodec = 'hevc';
  } else {
    return {
      valid: false,
      errorCode: 'UNSUPPORTED_CODEC',
      errorMessage: `Unsupported video codec: ${videoStream.codec_name}`,
    };
  }

  // HDR detection (heuristic — checks for HDR-indicating color metadata)
  const isHdr =
    videoStream.color_transfer === 'smpte2084' || // PQ (HDR10)
    videoStream.color_transfer === 'arib-std-b67' || // HLG
    videoStream.color_primaries === 'bt2020';

  // Audio stream (optional — videos without audio still transcode)
  const audioStream = raw.streams?.find((s) => s.codec_type === 'audio');

  return {
    valid: true,
    durationSeconds,
    width: videoStream.width ?? 0,
    height: videoStream.height ?? 0,
    isHdr,
    videoCodec,
    audioCodec: audioStream?.codec_name ?? null,
    container,
  };
}

// ====================================================================================
// HLS transcode — produces .m3u8 manifest + .ts segments
// ====================================================================================

/**
 * Transcode the input video to a single-rendition HLS package (manifest + segments).
 *
 * ★ USER CONTRIBUTION POINT 1 — HLS encoding parameters
 *
 * This function builds the FFmpeg command line. The current parameters are
 * placeholders. You decide:
 *
 * --- VIDEO QUALITY/SPEED TRADE-OFF ---
 *   -preset {value}  : encoding speed vs compression efficiency
 *     Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
 *     Faster preset → larger file (~20-30% bigger), shorter encode time
 *     Slower preset → smaller file, longer encode time
 *     For Container Apps Jobs (you pay per vCPU-second), faster = cheaper transcode
 *     but more storage. Slower = more compute cost but smaller files.
 *
 *   -crf {value}     : Constant Rate Factor (visual quality target)
 *     Range: 18 (visually lossless, very large files) to 28 (visible artifacts, small files)
 *     23 is the standard "visually indistinguishable from source" target
 *     Each +1 increase ≈ 6% smaller file
 *
 * --- AUDIO ---
 *   -b:a {bitrate}   : audio bitrate
 *     128k = standard for music + voice
 *     96k  = acceptable for voice-dominant content (smaller)
 *     192k = audiophile-quality (rarely needed for phone-recorded video)
 *
 * --- HLS SEGMENT LENGTH ---
 *   -hls_time {N}    : segment duration in seconds
 *     2 sec = finer seeking, ~2x as many .ts files (more API calls)
 *     4 sec = VOD standard (current default — recommended)
 *     6 sec = fewer files, slightly worse seeking UX
 *
 * --- HARDWARE ACCELERATION (ADVANCED, OPTIONAL) ---
 *   The base image jrottenberg/ffmpeg:6-alpine is software-only (libx264).
 *   Hardware encoding (h264_nvenc, h264_qsv, h264_vaapi) is NOT available
 *   in this image. If you ever need hardware accel, swap to a different
 *   base image. For v1, software encoding is fine.
 *
 * REFERENCE: the "starting point" parameters from the architecture decisions doc:
 *   -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k
 *   -vf scale=-2:min(ih\,1080) -hls_time 4 -hls_playlist_type vod
 *
 * Three example invocations to consider (uncomment one or write your own):
 *
 *   // Option A — Faster encode, larger files (cost-optimized for compute):
 *   //   '-preset', 'fast', '-crf', '23', '-b:a', '128k', '-hls_time', '4'
 *
 *   // Option B — Standard "visually indistinguishable" target (current default):
 *   //   '-preset', 'medium', '-crf', '23', '-b:a', '128k', '-hls_time', '4'
 *
 *   // Option C — Slower encode, smaller files (storage-optimized):
 *   //   '-preset', 'slow', '-crf', '23', '-b:a', '128k', '-hls_time', '4'
 *
 * Reasonable starting point: Option B (medium/23/128k/4s). Tune based on
 * production telemetry — if transcode jobs frequently approach the 15-min
 * timeout, switch to Option A. If storage cost grows too fast, switch to C.
 */
export async function transcodeHls(inputPath: string, outputDir: string): Promise<string> {
  await fs.promises.mkdir(outputDir, { recursive: true });
  const manifestPath = `${outputDir}/manifest.m3u8`;
  const segmentPattern = `${outputDir}/segment_%03d.ts`;

  // Parameters approved by Gene 2026-04-07: Option B (balanced defaults).
  // - preset=medium: standard balance of encoding speed vs file size
  // - crf=23: visually indistinguishable from source (industry standard)
  // - audio=128k AAC: good for voice + music
  // - hls_time=4: VOD industry standard
  // - scale filter downscales source above 1080p, leaves smaller sources unchanged
  // Re-tune in Phase 7 polish based on production transcode telemetry.
  const args: string[] = [
    '-y', // overwrite output
    '-i', inputPath,
    '-c:v', 'libx264',
    '-preset', 'medium',
    '-crf', '23',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-vf', `scale=-2:min(ih\\,${MAX_OUTPUT_HEIGHT})`,
    '-hls_time', String(HLS_SEGMENT_DURATION),
    '-hls_playlist_type', 'vod',
    '-hls_segment_filename', segmentPattern,
    manifestPath,
  ];

  console.log(`Running ffmpeg (HLS): ${FFMPEG_BIN} ${args.join(' ')}`);
  await execFileP(FFMPEG_BIN, args, { maxBuffer: 50 * 1024 * 1024 });
  return manifestPath;
}

// ====================================================================================
// MP4 fallback transcode — single progressive file for HLS-failure recovery
// ====================================================================================

/**
 * Transcode the input video to a single MP4 file used as fallback for clients
 * that fail HLS playback (older Android devices, edge cases).
 *
 * Same quality settings as HLS but with `-movflags +faststart` to put the
 * moov atom at the front of the file (enables progressive download playback).
 *
 * ★ USER CONTRIBUTION POINT 1 (continued) — MP4 fallback parameters
 *
 * Recommendation: use the SAME preset/CRF/audio settings as the HLS transcode
 * for consistency. The fallback is rarely played, so you don't need to
 * over-optimize either direction.
 */
export async function transcodeMp4Fallback(inputPath: string, outputPath: string): Promise<string> {
  // Parameters approved by Gene 2026-04-07: matching HLS settings for consistency.
  // The fallback is rarely played (only when HLS fails on a client), so
  // matching the HLS encoder settings keeps the user experience predictable.
  const args: string[] = [
    '-y',
    '-i', inputPath,
    '-c:v', 'libx264',
    '-preset', 'medium',
    '-crf', '23',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-vf', `scale=-2:min(ih\\,${MAX_OUTPUT_HEIGHT})`,
    '-movflags', '+faststart',
    outputPath,
  ];

  console.log(`Running ffmpeg (MP4 fallback): ${FFMPEG_BIN} ${args.join(' ')}`);
  await execFileP(FFMPEG_BIN, args, { maxBuffer: 50 * 1024 * 1024 });
  return outputPath;
}

// ====================================================================================
// Poster frame extraction
// ====================================================================================

/**
 * Extract a single poster frame from the video for the feed card thumbnail.
 *
 * Strategy: seek to ~1 second in (skip the first frame which is often black
 * or has compression artifacts), grab one frame, save as JPEG.
 *
 * For very short videos (<1 second), seek to 0 instead.
 *
 * This is generally not a meaningful trade-off — the parameters here are
 * standard. NOT a user contribution point.
 */
export async function extractPoster(
  inputPath: string,
  outputPath: string,
  durationSeconds: number,
): Promise<string> {
  const seekTime = durationSeconds < 1 ? '0' : '1';
  const args: string[] = [
    '-y',
    '-ss', seekTime,
    '-i', inputPath,
    '-vframes', '1',
    '-q:v', '2', // JPEG quality (1=best, 31=worst; 2 is high-quality)
    outputPath,
  ];

  console.log(`Running ffmpeg (poster): ${FFMPEG_BIN} ${args.join(' ')}`);
  await execFileP(FFMPEG_BIN, args, { maxBuffer: 50 * 1024 * 1024 });
  return outputPath;
}
