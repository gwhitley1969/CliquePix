import { extractRotation, canStreamCopy, computeOutputDimensions } from '../ffmpegService';
import type { FfprobeResult } from '../types';

// Minimal builder for the valid-ffprobe variant used by canStreamCopy.
// All fields default to the most-permissive fast-path-eligible values; the
// caller overrides only what the test cares about.
function buildProbe(
  overrides: Partial<Extract<FfprobeResult, { valid: true }>> = {},
): Extract<FfprobeResult, { valid: true }> {
  return {
    valid: true,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    isHdr: false,
    videoCodec: 'h264',
    audioCodec: 'aac',
    container: 'mp4',
    rotation: 0,
    ...overrides,
  };
}

describe('extractRotation', () => {
  it('returns 0 for a stream with no tags and no side_data_list', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        width: 1920,
        height: 1080,
      }),
    ).toBe(0);
  });

  it('reads legacy mov tag tags.rotate = "90"', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        tags: { rotate: '90' },
      }),
    ).toBe(90);
  });

  it('reads legacy mov tag tags.rotate = "180"', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        tags: { rotate: '180' },
      }),
    ).toBe(180);
  });

  it('reads modern Display Matrix rotation = -90 (typical iPhone portrait, normalizes to 270)', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        side_data_list: [
          { side_data_type: 'Display Matrix', rotation: -90 },
        ],
      }),
    ).toBe(270);
  });

  it('reads modern Display Matrix rotation = -270 (rare; normalizes to 90)', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        side_data_list: [
          { side_data_type: 'Display Matrix', rotation: -270 },
        ],
      }),
    ).toBe(90);
  });

  it('Display Matrix takes precedence over tags.rotate when both present', () => {
    // Modern iOS sometimes writes both. Display Matrix is canonical.
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        tags: { rotate: '90' }, // legacy reading
        side_data_list: [
          { side_data_type: 'Display Matrix', rotation: -90 }, // canonical → 270
        ],
      }),
    ).toBe(270);
  });

  it('returns 0 for non-cardinal angles (e.g. 47°)', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        side_data_list: [{ side_data_type: 'Display Matrix', rotation: 47 }],
      }),
    ).toBe(0);
  });

  it('returns 0 for unparseable tags.rotate', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        tags: { rotate: 'banana' },
      }),
    ).toBe(0);
  });

  it('ignores side_data entries that are not Display Matrix', () => {
    expect(
      extractRotation({
        codec_type: 'video',
        codec_name: 'h264',
        side_data_list: [{ side_data_type: 'Spherical Mapping', rotation: -90 }],
      }),
    ).toBe(0);
  });
});

describe('canStreamCopy — rotation gating (added with rotation fix)', () => {
  it('rejects fast-path-eligible source when rotation = 90', () => {
    expect(canStreamCopy(buildProbe({ rotation: 90 }))).toBe(false);
  });

  it('rejects fast-path-eligible source when rotation = 270', () => {
    expect(canStreamCopy(buildProbe({ rotation: 270 }))).toBe(false);
  });

  it('rejects fast-path-eligible source when rotation = 180', () => {
    expect(canStreamCopy(buildProbe({ rotation: 180 }))).toBe(false);
  });

  it('accepts fast-path-eligible source when rotation = 0 (regression)', () => {
    expect(canStreamCopy(buildProbe({ rotation: 0 }))).toBe(true);
  });

  it('accepts source with no audio when rotation = 0 (regression)', () => {
    expect(canStreamCopy(buildProbe({ audioCodec: null, rotation: 0 }))).toBe(true);
  });

  it('rejects HEVC source regardless of rotation (existing rule preserved)', () => {
    expect(canStreamCopy(buildProbe({ videoCodec: 'hevc', rotation: 0 }))).toBe(false);
  });
});

describe('computeOutputDimensions', () => {
  it('1080p landscape, no rotation, no scale', () => {
    expect(computeOutputDimensions(1920, 1080, 0)).toEqual({ width: 1920, height: 1080 });
  });

  it('1080p iPhone portrait (storage 1920x1080 + rotation 270) swaps to 1080x1920', () => {
    expect(computeOutputDimensions(1920, 1080, 270)).toEqual({ width: 1080, height: 1920 });
  });

  it('1080p iPhone portrait (rotation 90) swaps to 1080x1920 — same as 270', () => {
    expect(computeOutputDimensions(1920, 1080, 90)).toEqual({ width: 1080, height: 1920 });
  });

  it('180° rotation does not swap dimensions', () => {
    expect(computeOutputDimensions(1920, 1080, 180)).toEqual({ width: 1920, height: 1080 });
  });

  it('4K landscape downscales to 1920x1080', () => {
    expect(computeOutputDimensions(3840, 2160, 0)).toEqual({ width: 1920, height: 1080 });
  });

  it('4K portrait (storage 3840x2160 + rotation 270) swaps then downscales to 1080x1920', () => {
    expect(computeOutputDimensions(3840, 2160, 270)).toEqual({ width: 1080, height: 1920 });
  });

  it('720p landscape stays 1280x720 (no upscale)', () => {
    expect(computeOutputDimensions(1280, 720, 0)).toEqual({ width: 1280, height: 720 });
  });

  it('odd source dimensions round down to even', () => {
    // 1921×1081 source — autorotate 0, scale by min(1, 1920/1921) = ~0.99948
    // Output: floor(1921*0.99948/2)*2 = floor(960.0/2)*2 = 1920;
    //         floor(1081*0.99948/2)*2 = floor(540.22/2)*2 = 1080
    expect(computeOutputDimensions(1921, 1081, 0)).toEqual({ width: 1920, height: 1080 });
  });

  it('all returned dimensions are even (libx264 requirement)', () => {
    const cases: Array<[number, number, 0 | 90 | 180 | 270]> = [
      [1920, 1080, 0],
      [1920, 1080, 90],
      [1080, 1920, 0],
      [3840, 2160, 270],
      [1281, 721, 0],
      [999, 999, 90],
    ];
    for (const [w, h, rot] of cases) {
      const out = computeOutputDimensions(w, h, rot);
      expect(out.width % 2).toBe(0);
      expect(out.height % 2).toBe(0);
    }
  });
});
