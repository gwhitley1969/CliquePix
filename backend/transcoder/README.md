# CliquePix Video Transcoder

FFmpeg-based video transcoding service that runs as an Azure Container Apps Job. Triggered by messages on the `video-transcode-queue` Storage Queue.

## What it does

For each queued message:
1. Downloads the original video from blob storage
2. Validates with ffprobe (container, codec, duration, HDR detection)
3. Transcodes to:
   - HLS package (`.m3u8` manifest + `.ts` segments)
   - Progressive MP4 fallback
   - Poster JPEG
4. Uploads outputs to blob storage at `photos/{cliqueId}/{eventId}/{videoId}/`
5. Moves the original master to Cool storage tier
6. Posts a callback to the Function App with results
7. Deletes the queue message and exits

## Architecture

This is a one-shot Container Apps Job — each execution processes exactly one message and exits. KEDA's Azure Storage Queue scaler triggers a new replica when messages arrive.

| Component | Detail |
|---|---|
| Image base | `jrottenberg/ffmpeg:6-alpine` (pinned by SHA in Dockerfile) |
| Runner runtime | Node.js 20 (alpine pkg) |
| Concurrency | 1 message per replica, up to 10 replicas in parallel |
| Replica timeout | 15 minutes (hard ceiling — videos exceeding this fail) |
| Auth | System-assigned managed identity (Storage Blob/Queue + AcrPull) |

## Local development

### Prerequisites

- Docker Desktop running
- Node.js 20+ (for the non-Docker `transcode-local` flow)
- Azure CLI logged in (for `az acr login` when pushing)

### Install dependencies

```bash
cd backend/transcoder
make install
```

### Get sample test videos

See `sample-videos/README.md` for the recommended sample set and how to source it.

### Run a single transcode locally (Docker)

```bash
make docker-test INPUT=sample-videos/iphone-h264-1080p.mov
```

This builds the container image, runs it in `LOCAL_MODE=true` against your sample video, and writes outputs to `test-output/`. Inspect with:

```bash
ls -la test-output/
ls -la test-output/hls/
cat test-output/hls/manifest.m3u8
```

Open the MP4 fallback in any video player to verify it plays:

```bash
# Windows
start test-output/fallback.mp4
# macOS
open test-output/fallback.mp4
```

### Run the runner directly via node (no Docker)

Faster iteration when you're tweaking TypeScript code, since you skip the Docker build cycle:

```bash
make transcode-local INPUT=sample-videos/iphone-h264-1080p.mov
```

Requires FFmpeg to be installed locally and in `PATH`.

### Tuning FFmpeg parameters

The encoding parameters are in `src/ffmpegService.ts`. The main knobs are:

- `-preset` — speed vs compression efficiency (`fast` / `medium` / `slow`)
- `-crf` — visual quality (18 = lossless, 23 = standard, 28 = visible artifacts)
- `-b:a` — audio bitrate (`96k` / `128k` / `192k`)
- `-hls_time` — segment duration in seconds (4 = standard for VOD)

After changing parameters, run `make docker-test` against multiple sample videos to confirm:

1. Transcoding completes without errors
2. The HLS manifest references the segment files correctly
3. The MP4 fallback plays in a video player
4. The poster JPEG is a reasonable representative frame
5. Total transcoding time is acceptable (target: ≤ 5 min for a 5-min source)
6. Output file sizes are reasonable (1080p H.264 typically: ~5-15 MB per minute)

## Deploying to Azure

### One-time: build and push the first image

```bash
make push
```

This builds the image, logs into ACR, tags it as `cracliquepix.azurecr.io/cliquepix-transcoder:latest`, and pushes.

### Update the Container Apps Job to use the new image

```bash
make deploy
```

This runs `make push` AND updates the Container Apps Job to use the latest image. Subsequent executions of the job will pull the new image on first cold start.

### Verify the deployment

Trigger a manual test execution:

```bash
az containerapp job execution start \
  --name caj-cliquepix-transcoder \
  --resource-group rg-cliquepix-prod
```

Then watch the logs in App Insights:

```kql
traces
| where cloud_RoleName == "caj-cliquepix-transcoder"
| order by timestamp desc
| take 50
```

Or follow the Container Apps Job execution logs in the Azure Portal under `caj-cliquepix-transcoder → Execution history`.

## Environment variables

These are set on the Container Apps Job in `Phase 2` of the implementation plan:

| Variable | Source | Purpose |
|---|---|---|
| `STORAGE_ACCOUNT_NAME` | env | Storage account hosting blobs and queue |
| `STORAGE_QUEUE_NAME` | env | Queue to dequeue from (`video-transcode-queue`) |
| `BLOB_CONTAINER_NAME` | env | Blob container hosting media (`photos`) |
| `FUNCTION_CALLBACK_URL` | env | Function endpoint to POST results to |
| `FUNCTION_APP_AUDIENCE` | env | Audience claim for managed identity token request |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | secret | App Insights for telemetry (shared with Function App) |

For local mode, set `LOCAL_MODE=true`, `LOCAL_INPUT_FILE`, and `LOCAL_OUTPUT_DIR` instead.

## Troubleshooting

### Transcoder times out at 15 minutes
The Container Apps Job's `--replica-timeout` is 900 seconds. If FFmpeg takes longer than that, the replica is killed and the message is retried. If this becomes common:
- Try a faster preset (`fast` or `veryfast`) in `ffmpegService.ts`
- Increase the timeout if you have a specific reason
- Verify the source isn't pathological (e.g., super-slow-motion at high bitrate)

### Callback POST fails consistently
Check that:
1. `FUNCTION_CALLBACK_URL` is correct and the Function App is running
2. The Container Apps Job's MI has permission to call the Function (not enforced via RBAC; the Function-side `validateInternalCallerIdentity` checks the token's `oid` claim)
3. `FUNCTION_APP_AUDIENCE` matches what the Function expects in `TRANSCODER_MI_PRINCIPAL_ID` and `FUNCTION_APP_AUDIENCE` env vars

### Image pull fails on Container Apps Job
Verify the AcrPull RBAC role is on the Container Apps Job's MI for the ACR scope. See `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md`.

### "Queue is empty" but I just enqueued a message
KEDA polling interval is 30 seconds. New messages can take up to 30 seconds to trigger a new replica. To force-trigger immediately:

```bash
az containerapp job execution start --name caj-cliquepix-transcoder -g rg-cliquepix-prod
```

## Files

```
backend/transcoder/
├── Dockerfile              # Container image definition (FFmpeg base + Node runner)
├── .dockerignore           # Files excluded from the image build context
├── .gitignore              # Files excluded from git
├── Makefile                # Dev convenience targets (install, build, test, push, deploy)
├── README.md               # This file
├── package.json            # Node deps (Azure SDKs, App Insights)
├── tsconfig.json           # TypeScript compiler config
├── sample-videos/          # Local test videos (gitignored)
│   └── README.md           # How to populate this directory
├── src/
│   ├── runner.ts           # Main entry point (queue mode + local mode)
│   ├── ffmpegService.ts    # ffprobe + transcoding wrappers
│   ├── blobService.ts      # Blob download/upload via managed identity
│   ├── queueService.ts     # Storage Queue dequeue/delete
│   ├── callbackService.ts  # POST callback to Function App
│   └── types.ts            # Shared TypeScript types
└── dist/                   # Compiled output (gitignored)
```
