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
 * HISTORY:
 *   2026-04-07: Originally shipped as TWO separate ffmpeg invocations (transcodeHls
 *               + transcodeMp4Fallback), both at preset=medium. This meant the
 *               x264 encoder did the work TWICE for every video — once for HLS
 *               output, once for MP4 fallback — and preset=medium was slow on
 *               short content.
 *
 *   2026-04-08: Consolidated into a single ffmpeg invocation using the `-f tee`
 *               muxer, which produces both HLS and MP4 outputs from ONE x264
 *               encode. Preset changed from medium → fast (~30% faster encode,
 *               ~20% larger files, still visually indistinguishable at crf=23).
 *               Measured: ~2 minutes wall-clock → target ~40-50 seconds for
 *               short videos, matching the architecture spec.
 */
export async function transcodeHlsAndMp4(
  inputPath: string,
  hlsOutputDir: string,
  mp4FallbackPath: string,
  options: { isHdr: boolean } = { isHdr: false },
): Promise<{ manifestPath: string }> {
  await fs.promises.mkdir(hlsOutputDir, { recursive: true });
  const manifestPath = `${hlsOutputDir}/manifest.m3u8`;
  const segmentPattern = `${hlsOutputDir}/segment_%03d.ts`;

  // Tee muxer spec — two outputs from one encoder pass:
  //   [f=hls:hls_time=N:hls_playlist_type=vod:hls_segment_filename=PATH]MANIFEST|[f=mp4:movflags=+faststart]FALLBACK
  //
  // Options within a single tee output are `:`-separated. Outputs are
  // `|`-separated. The string after `]` is the output path.
  //
  // Linux-only paths (no Windows drive letters) means no `:` inside the
  // filename values, so no escaping required.
  const teeSpec =
    `[f=hls:hls_time=${HLS_SEGMENT_DURATION}:hls_playlist_type=vod:hls_segment_filename=${segmentPattern}]${manifestPath}` +
    `|[f=mp4:movflags=+faststart]${mp4FallbackPath}`;

  // Video filter chain. Two concerns:
  //
  // 1. HDR→SDR tone-mapping. If the source is HDR (HEVC iPhone captures with
  //    BT.2020 primaries + SMPTE 2084 PQ transfer), we run it through a
  //    zscale → tonemap (Hable) → zscale chain to produce SDR BT.709 output.
  //    Without this, libx264 happily encodes HDR pixel values into an H.264
  //    stream with BT.2020 VUI metadata, which ExoPlayer and AVPlayer can't
  //    decode correctly on most mobile devices — the output plays on nothing.
  //
  // 2. Forced 8-bit output. libx264 preserves the source's pixel format by
  //    default. HDR sources are 10-bit (yuv420p10le), and libx264 will happily
  //    encode to 10-bit High10 profile H.264 — which almost no mobile player
  //    supports. `format=yuv420p` + explicit `-pix_fmt yuv420p` force 8-bit.
  //
  // The zscale + tonemap filters are provided by libzimg. Confirmed present
  // in jrottenberg/ffmpeg:6-alpine via `ffmpeg -filters` (2026-04-08).
  //
  // SDR sources skip the zscale+tonemap chain (overhead for no benefit) and
  // only get scale + format=yuv420p.
  const hdrToSdrChain = options.isHdr
    ? 'zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,'
    : '';
  const videoFilter = `${hdrToSdrChain}scale=-2:min(ih\\,${MAX_OUTPUT_HEIGHT}),format=yuv420p`;

  const args: string[] = [
    '-y', // overwrite output
    '-i', inputPath,
    '-c:v', 'libx264',
    // 2026-04-08: bumped 'fast' → 'veryfast' to cut HDR re-encode time.
    // veryfast is ~25-30% faster than fast for libx264, files ~15-20% larger
    // but well within budget for short clips. The HDR tone-mapping path
    // (zscale + tonemap=hable) is the dominant cost; preset reduction helps
    // amortize it.
    '-preset', 'veryfast',
    '-crf', '23',         // visually indistinguishable from source
    '-profile:v', 'high', // H.264 High profile — universally supported on mobile
    '-level', '4.0',      // compatible with all iOS/Android devices from ~2015+
    '-pix_fmt', 'yuv420p', // force 8-bit output (prevents 10-bit High10 encode)
    // Explicit BT.709 SDR metadata in the output stream's VUI parameters.
    // Decoders look at these tags to decide how to interpret the YUV values;
    // without them, an HDR-source → re-encode may carry BT.2020/PQ tags through.
    '-colorspace', 'bt709',
    '-color_primaries', 'bt709',
    '-color_trc', 'bt709',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-vf', videoFilter,
    // Tee muxer requires explicit stream mapping
    '-map', '0:v?',
    '-map', '0:a?',
    '-f', 'tee',
    teeSpec,
  ];

  console.log(`Running ffmpeg (HLS + MP4 tee, hdr=${options.isHdr}): ${FFMPEG_BIN} ${args.join(' ')}`);
  await execFileP(FFMPEG_BIN, args, { maxBuffer: 50 * 1024 * 1024 });
  return { manifestPath };
}

// ====================================================================================
// Stream-copy fast path — remux compatible sources without re-encoding
// ====================================================================================

/**
 * Fast path: re-mux compatible source directly to HLS + MP4 fallback without
 * re-encoding. Audio and video streams are copied bit-exact from the source;
 * only the container structure changes.
 *
 * Prerequisites (caller must verify via canStreamCopy()):
 *   - Video codec is h264
 *   - Not HDR
 *   - Height ≤ 1080
 *   - Container is mp4 or mov
 *   - Audio is aac (or no audio)
 *
 * Note on HLS segmentation: with -c copy, hls_time=4 cuts at the NEAREST
 * keyframe before the target. Phone captures typically have keyframes every
 * 1-2 seconds, so segment lengths vary (3-5 sec is typical). This is valid
 * per the HLS spec — the playlist EXTINF tag declares actual segment duration
 * and modern AVPlayer + ExoPlayer handle variable-length VOD segments fine.
 *
 * Measured wall-clock target: ~2-5 seconds for a 30-second 1080p phone capture,
 * vs. ~15-25 seconds for libx264 preset=fast on the same hardware.
 */
export async function remuxHlsAndMp4(
  inputPath: string,
  hlsOutputDir: string,
  mp4FallbackPath: string,
): Promise<{ manifestPath: string }> {
  await fs.promises.mkdir(hlsOutputDir, { recursive: true });
  const manifestPath = `${hlsOutputDir}/manifest.m3u8`;
  const segmentPattern = `${hlsOutputDir}/segment_%03d.ts`;

  const teeSpec =
    `[f=hls:hls_time=${HLS_SEGMENT_DURATION}:hls_playlist_type=vod:hls_segment_filename=${segmentPattern}]${manifestPath}` +
    `|[f=mp4:movflags=+faststart]${mp4FallbackPath}`;

  const args: string[] = [
    '-y',
    '-i', inputPath,
    '-c:v', 'copy',        // bit-exact passthrough, no re-encoding
    '-c:a', 'copy',        // bit-exact audio passthrough
    '-map', '0:v:0',       // explicit single-video stream map (drop subtitles/extra tracks)
    '-map', '0:a:0?',      // optional single audio stream
    '-f', 'tee',
    teeSpec,
  ];

  console.log(`Running ffmpeg (stream-copy remux): ${FFMPEG_BIN} ${args.join(' ')}`);
  await execFileP(FFMPEG_BIN, args, { maxBuffer: 50 * 1024 * 1024 });
  return { manifestPath };
}

/**
 * Decide whether an ffprobe result qualifies for the stream-copy fast path.
 * Must be called AFTER the ffprobe `valid: true` discriminant has been checked.
 *
 * Criteria (ALL must hold):
 *   - videoCodec === 'h264'               → libx264-compatible only, no HEVC
 *   - !isHdr                              → SDR only, HDR needs tone-mapping
 *   - height <= MAX_OUTPUT_HEIGHT (1080)  → no upscale/downscale required
 *   - container is mp4 or mov             → mov/mp4 atoms are re-muxable to TS
 *   - audioCodec is null or 'aac'         → AAC copies straight into MPEG-TS
 */
export function canStreamCopy(
  probe: Extract<FfprobeResult, { valid: true }>,
): boolean {
  if (probe.videoCodec !== 'h264') return false;
  if (probe.isHdr) return false;
  if (probe.height > MAX_OUTPUT_HEIGHT) return false;
  if (probe.container !== 'mp4' && probe.container !== 'mov') return false;
  if (probe.audioCodec !== null && probe.audioCodec !== 'aac') return false;
  return true;
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
