# Sample test videos

This directory holds reference videos for local FFmpeg testing. **The video files themselves are gitignored** — only this README is tracked. You need to populate the directory yourself before running `npm run transcode-local`.

## Why not commit them?

Sample videos are 5-10 MB each, totaling ~30-50 MB. Committing them would bloat the git repo and pollute history. Better to source them from a known location.

## Recommended sample set

Place these files in `backend/transcoder/sample-videos/`:

| Filename | Purpose | Recording method |
|---|---|---|
| `iphone-h264-1080p.mov` | Standard iPhone capture | Settings → Camera → Formats → "Most Compatible" |
| `iphone-hevc-1080p.mov` | iPhone HEVC capture (default) | Settings → Camera → Formats → "High Efficiency" |
| `android-h264-1080p.mp4` | Standard Android capture | Default Camera app on most Android phones |
| `iphone-hdr-1080p.mov` | HDR source for SDR normalization testing | iPhone 12+ with HDR Video enabled |
| `oversized-4k.mp4` | 4K source for downscale testing | iPhone 12+ recording at 4K, OR any camera capable of 4K |

Each file should be ~30 seconds or less (to keep transcoding tests fast).

## How to source them

**Option A: Record them yourself.** Easiest if you have an iPhone and Android device. Trim each clip to ~30 seconds with QuickTime / Photos / Files app.

**Option B: Pull from a shared dev assets blob.** If you've created the dev-assets blob container in `stcliquepixprod` (per the runbook follow-up), use:

```bash
az storage blob download-batch \
  --source dev-assets \
  --destination ./sample-videos \
  --account-name stcliquepixprod \
  --auth-mode login \
  --pattern "transcoder-samples/*"
```

**Option C: Public test videos.** Any 1080p H.264 / HEVC / HDR sample from the internet works. Suggested sources:
- https://test-videos.co.uk/bigbuckbunny/mp4-h264 (free, unencumbered, various resolutions)
- https://media.xiph.org/video/derf/ (research test sequences, raw and encoded)

## Verifying the sample set

After populating, run:

```bash
cd backend/transcoder
ls -la sample-videos/
```

You should see at least the four core files (iphone-h264, iphone-hevc, android-h264, iphone-hdr). The 4K file is optional but useful for downscale testing.
