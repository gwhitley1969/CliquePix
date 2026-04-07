// HLS manifest rewriter — fetches a stored .m3u8 from blob storage and
// rewrites segment URLs with fresh per-blob User Delegation SAS URLs.
//
// Why this exists:
//   The transcoder writes HLS output to blob storage as a manifest + many
//   segment files. The client needs to fetch the manifest, see segment URLs,
//   and request each segment. Because we use per-blob short-lived SAS for
//   security (CLAUDE.md rule), every segment URL needs its own SAS — and
//   they expire 15 minutes after generation.
//
//   The client cannot generate SAS URLs (it doesn't have storage credentials).
//   So the API rewrites the manifest at request time, baking in fresh SAS
//   URLs for each segment, and returns the rewritten manifest as opaque text.
//
// Cache:
//   Rewriting requires a blob read (the original manifest) plus N SAS
//   generations. To amortize this across many concurrent viewers of the
//   same video, we cache the rewritten manifest in-process for 60 seconds.
//   At MVP scale this is fine; if memory pressure becomes an issue post-v1,
//   swap the Map for `lru-cache` with a max-entries limit.

import * as path from 'path';
import { downloadBlob } from './blobService';
import { generateViewSas } from './sasService';

const CACHE_TTL_MS = 60 * 1000;
const SAS_EXPIRY_SECONDS = 15 * 60;

interface CacheEntry {
  manifest: string;
  expiresAt: number;
}

const manifestCache = new Map<string, CacheEntry>();

function getCached(videoId: string): string | null {
  const entry = manifestCache.get(videoId);
  if (!entry) return null;
  if (entry.expiresAt < Date.now()) {
    manifestCache.delete(videoId);
    return null;
  }
  return entry.manifest;
}

function setCached(videoId: string, manifest: string): void {
  manifestCache.set(videoId, {
    manifest,
    expiresAt: Date.now() + CACHE_TTL_MS,
  });
}

/**
 * Fetch the HLS manifest from blob storage and rewrite segment URLs with
 * fresh User Delegation SAS URLs (15-min expiry).
 *
 * @param videoId - used as the cache key (one entry per video)
 * @param manifestBlobPath - blob path to the .m3u8 file
 *                            (e.g., "{cliqueId}/{eventId}/{videoId}/hls/manifest.m3u8")
 * @returns the rewritten manifest as a string, with absolute SAS URLs in place of relative segment names
 */
export async function rewriteHlsManifest(
  videoId: string,
  manifestBlobPath: string,
): Promise<string> {
  // Cache hit path — most playback requests come here
  const cached = getCached(videoId);
  if (cached) {
    return cached;
  }

  // Cache miss — read manifest from blob and rewrite
  const manifestBuffer = await downloadBlob(manifestBlobPath);
  const manifestText = manifestBuffer.toString('utf-8');

  // The HLS manifest is in the same directory as its segments. We need each
  // segment's full blob path (e.g., "{cliqueId}/{eventId}/{videoId}/hls/segment_000.ts")
  // to generate a SAS URL for it. Compute the directory prefix from the
  // manifest's blob path.
  const segmentDirPrefix = path.posix.dirname(manifestBlobPath);

  const rewritten = await rewriteManifestText(manifestText, segmentDirPrefix);

  setCached(videoId, rewritten);
  return rewritten;
}

/**
 * ★ USER CONTRIBUTION POINT 2 — HLS manifest text rewriter
 * ====================================================================
 *
 * This is the core string-manipulation function. Given the raw .m3u8
 * manifest text and the directory prefix where its segments live in
 * blob storage, return a new manifest where every relative segment URL
 * has been replaced with an absolute SAS URL.
 *
 * Example input (manifestText):
 *   #EXTM3U
 *   #EXT-X-VERSION:3
 *   #EXT-X-TARGETDURATION:5
 *   #EXT-X-PLAYLIST-TYPE:VOD
 *   #EXT-X-MEDIA-SEQUENCE:0
 *   #EXTINF:4.000,
 *   segment_000.ts
 *   #EXTINF:4.000,
 *   segment_001.ts
 *   #EXTINF:3.500,
 *   segment_002.ts
 *   #EXT-X-ENDLIST
 *
 * Example output (each segment line replaced with a full SAS URL):
 *   #EXTM3U
 *   #EXT-X-VERSION:3
 *   ...
 *   #EXTINF:4.000,
 *   https://stcliquepixprod.blob.core.windows.net/photos/.../segment_000.ts?sv=...&se=...&sr=b&sp=r&sig=...
 *   ...
 *
 * RULES:
 *   - Lines starting with `#` are HLS directives — pass them through unchanged
 *   - Lines that don't start with `#` and are not empty are SEGMENT URLs
 *     (in our single-rendition output, these always end in `.ts`)
 *   - For each segment line, compute the segment's blob path:
 *       const segmentBlobPath = `${segmentDirPrefix}/${segmentLine.trim()}`;
 *   - Generate a fresh SAS URL via:
 *       const sasUrl = await generateViewSas(segmentBlobPath, SAS_EXPIRY_SECONDS);
 *   - Replace the segment line with the SAS URL in the output
 *   - Preserve line ordering (segments must stay in their original sequence)
 *   - Join the result with `\n`
 *
 * IMPLEMENTATION CHOICES:
 *   You can implement this two ways:
 *
 *   (A) LINE-BY-LINE LOOP (recommended for v1 — simpler, easier to debug):
 *       const lines = manifestText.split('\n');
 *       const rewritten: string[] = [];
 *       for (const line of lines) {
 *         if (line.startsWith('#') || line.trim() === '') {
 *           rewritten.push(line);
 *           continue;
 *         }
 *         // It's a segment line
 *         const segmentBlobPath = `${segmentDirPrefix}/${line.trim()}`;
 *         const sasUrl = await generateViewSas(segmentBlobPath, SAS_EXPIRY_SECONDS);
 *         rewritten.push(sasUrl);
 *       }
 *       return rewritten.join('\n');
 *
 *   (B) REGEX REPLACEMENT (faster, harder to debug):
 *       Use a regex to match segment lines (e.g., /^([^#].*\.ts)$/gm) and
 *       use replaceAsync (since generateViewSas is async). More compact but
 *       requires careful regex tuning if non-.ts segments ever appear.
 *
 * For our v1 single-rendition manifest with ~75 segments per 5-min video,
 * the line-by-line loop runs in <100ms total (mostly waiting on SAS
 * generation, not the loop overhead). Pick whichever you prefer.
 *
 * @param manifestText - raw .m3u8 contents
 * @param segmentDirPrefix - blob path prefix to the segment directory
 *                            (e.g., "{cliqueId}/{eventId}/{videoId}/hls")
 * @returns the rewritten manifest text
 */
async function rewriteManifestText(
  manifestText: string,
  segmentDirPrefix: string,
): Promise<string> {
  // Approved default: line-by-line loop (Option A from the comment block above).
  // Simple, readable, easy to debug. Performance is fine for our v1
  // single-rendition manifests with ~75 segments per 5-min video.
  const lines = manifestText.split('\n');
  const rewritten: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    // HLS directives and blank lines pass through unchanged
    if (trimmed === '' || trimmed.startsWith('#')) {
      rewritten.push(line);
      continue;
    }
    // Anything else is a segment URL (relative filename like "segment_000.ts")
    const segmentBlobPath = `${segmentDirPrefix}/${trimmed}`;
    const sasUrl = await generateViewSas(segmentBlobPath, SAS_EXPIRY_SECONDS);
    rewritten.push(sasUrl);
  }

  return rewritten.join('\n');
}
