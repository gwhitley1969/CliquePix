// Regression tests for TQ-2: when videoProcessingComplete finds NO photos row
// (event hard-deleted mid-transcode), it must prefix-delete the per-video blob
// dir so the transcoder's outputs are not orphaned. deriveVideoDir computes that
// dir from whatever derivative path the callback reports — the subtle bit is
// stripping a trailing 'hls/' so we land on {video}/ (covering poster+fallback),
// not {video}/hls/.

import { deriveVideoDir } from '../functions/videos';

describe('deriveVideoDir — TQ-2 orphan blob dir derivation', () => {
  const PREFIX = 'photos/c1/e1/vid1/';

  it('derives {video}/ from poster_blob_path', () => {
    expect(deriveVideoDir({ poster_blob_path: 'photos/c1/e1/vid1/poster.jpg' })).toBe(PREFIX);
  });

  it('derives {video}/ from mp4_fallback_blob_path', () => {
    expect(deriveVideoDir({ mp4_fallback_blob_path: 'photos/c1/e1/vid1/fallback.mp4' })).toBe(PREFIX);
  });

  it('strips trailing hls/ when only the manifest path is present', () => {
    // manifest lives in {video}/hls/ — must resolve to {video}/ so fallback.mp4 +
    // poster.jpg are also covered, not left orphaned.
    expect(deriveVideoDir({ hls_manifest_blob_path: 'photos/c1/e1/vid1/hls/manifest.m3u8' })).toBe(
      PREFIX,
    );
  });

  it('prefers poster > fallback > manifest', () => {
    expect(
      deriveVideoDir({
        poster_blob_path: 'photos/c1/e1/vid1/poster.jpg',
        hls_manifest_blob_path: 'photos/c1/e1/OTHER/hls/manifest.m3u8',
      }),
    ).toBe(PREFIX);
  });

  it('returns null when no path is provided (defensive no-op)', () => {
    expect(deriveVideoDir({})).toBeNull();
  });

  it('always ends in a slash so a sibling {video}X/ prefix cannot match', () => {
    const dir = deriveVideoDir({ poster_blob_path: 'photos/c1/e1/vid1/poster.jpg' });
    expect(dir).not.toBeNull();
    expect(dir!.endsWith('/')).toBe(true);
    expect('photos/c1/e1/vid1x/original.mp4'.startsWith(dir!)).toBe(false);
  });
});
