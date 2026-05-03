# Video Architecture Decisions — Clique Pix

## Context

This document records the CliquePix-specific architectural decisions for the video feature, locked before implementation begins. It translates the generic requirements in `docs/CliquePix_Video_Feature_Spec.md` into concrete choices that match CliquePix's existing Azure stack, security posture, and operating constraints.

**Source documents:**
- `docs/CliquePix_Video_Feature_Spec.md` — the generic handoff spec
- `.claude/CLAUDE.md` — CliquePix development guardrails (video was promoted to v1 in the same commit as this doc's creation)
- `docs/ARCHITECTURE.md` — existing technical architecture
- `docs/EVENT_DM_CHAT_ARCHITECTURE.md` — Web PubSub usage pattern that video processing-state push reuses

**Guiding constraints:**
- All originals and derived assets stay in Azure Blob Storage (data sovereignty)
- No storage account keys anywhere — User Delegation SAS only
- Function App is on Consumption (Dynamic SKU) with a 10-minute execution limit — FFmpeg cannot run in-Function
- No managed video services (Cloudflare Stream, Mux) — explicit rejection for privacy and keeping the stack in Azure
- Azure Media Services was retired June 30, 2024, so it's not an option anyway
- Solo-dev / MVP scale — "boring and proven" wins over "most flexible"

**What this document does:**
Locks down the hard calls (transcoder host, schema, HLS delivery, player, upload UX, processing-state propagation, storage tiering) so the implementation plan can focus on building, not deciding.

**What this document does NOT do:**
Specify full API contracts, migration SQL, Dockerfile contents, or Flutter widget structures. Those live in the follow-up implementation plan.

---

## Decision 0: Transcoder host

**The most consequential decision in the entire feature. Shapes every downstream choice.**

### Question

Where does FFmpeg actually run?

### Options evaluated

**A. Azure Container Apps Jobs + Azure Container Registry** — **CHOSEN**
- Custom FFmpeg container image, launched per job, destroyed on completion
- ACR Standard SKU hosts the image (chosen over Basic for throughput headroom — see "ACR SKU selection" below)
- Container Apps Environment (consumption-billed)
- Dispatched via Storage Queue message from the upload-confirm Function
- Scale to zero when idle; up to 1-hour per-job runtime

**B. Functions Premium EP1 (two Function Apps sharing a plan)**
- Migrate Function App from Consumption to Premium EP1
- Second Function App hosts FFmpeg as a bundled static binary, shelled out via `child_process.spawn`
- Both apps share Premium plan workers (soft isolation)
- **Rejected:** ~$126/month baseline vs Container Apps Jobs' ~$8-20/month, and the isolation is "soft" (shared workers) rather than true per-job containers. Cost delta is ~$1200/year forever, and the only compelling advantage (ops familiarity) doesn't outweigh the scaling story.

**C. Azure Container Instances (ACI)**
- One-shot container, pay-per-second, no Environment to manage
- Similar technical shape to Container Apps Jobs, simpler mental model
- **Rejected:** Microsoft is steering investment toward Container Apps for new batch workloads. Adopting ACI now would be learning a primitive that's sliding into maintenance mode.

**D. Azure Batch**
- **Rejected:** overkill for this volume and operational complexity. Batch is designed for HPC workloads, not per-video transcoding at MVP scale.

**E. Functions Consumption with FFmpeg**
- **Rejected:** 10-minute execution limit (verified via `az functionapp show --query sku` returning `Dynamic`). Cannot safely transcode a 5-minute 1080p video in 10 minutes; HEVC source is especially tight.

**F. Managed video services — Cloudflare Stream, Mux, api.video**
- **Rejected:** explicit user call. CliquePix is keeping the entire media pipeline inside Azure for data sovereignty and to avoid third-party trust dependencies beyond what's already accepted (FCM for push transport).

**G. Azure Media Services**
- **Rejected:** retired June 30, 2024.

### Chosen architecture

**Azure Container Apps Jobs + Azure Container Registry + FFmpeg container image**, dispatched via Azure Storage Queue from the video upload-confirm Function endpoint.

### Reasoning (in priority order)

1. **Best cost scaling.** Linear pay-per-use vs Premium's step-wise instance increments. ~$8-20/month at MVP scale, ~$30-60/month at 1000 videos/month. Premium EP1 is $126/month baseline whether you transcode 0 videos or 100.

2. **True workload isolation.** Transcoding is CPU-bound, long-running, bursty. REST API is I/O-bound, short-running, steady. These should not share compute. Container Apps Jobs gives each transcode its own container with zero impact on REST API latency.

3. **Modern Microsoft-recommended direction.** Container Apps is GA, actively developed, supported in Bicep. It's the "proven and boring" path going forward for new batch workloads on Azure.

4. **Stays entirely inside Azure.** Same managed identity pattern for Blob/Key Vault access, same App Insights for telemetry, same region. Matches the security posture of every other backend component.

5. **Easy parallelism without reconfiguration.** If upload volume spikes, Container Apps Jobs schedules multiple parallel jobs automatically. Premium's scale-out model requires provisioning additional $126/month instances.

6. **Scale to zero when idle.** No baseline cost beyond ~$20/month ACR (Standard SKU). You only pay vCPU-seconds of actual transcoding work.

### Trade-offs accepted

- **Cold start per job: ~30-60 seconds.** Container pull + startup. Mitigations:
  - Minimal container image (Alpine + FFmpeg static, target ~100MB)
  - Optional `minReplicas: 1` config to keep one container warm (adds a small always-on cost but eliminates cold start for the first job)
  - UX reality: users see a "processing" placeholder and get a push notification when ready; they are NOT blocking on real-time completion. Cold start is cosmetic, not UX-breaking.
- **New Azure primitives to learn.** ACR and Container Apps are both GA and well-documented. The user is familiar with Azure Functions; Container Apps has analogous deployment patterns (`az containerapp job create`, `az containerapp job start`).
- **Container image build/push pipeline.** Dockerfile + either GitHub Actions or manual `docker build` + `az acr build`. One more thing to version and maintain.
- **Callback wiring.** Container Apps Job needs to call back to a Function endpoint with managed-identity authentication.

### Architecture diagram (ASCII)

```
Client
  │
  │ 1. POST /api/events/{eventId}/videos/upload-url
  ▼
APIM → Function App (upload-url handler)
  │ returns N block SAS URLs + commit URL
  ▼
Client
  │
  │ 2. PUT each block → Blob Storage
  │
  │ 3. POST /api/events/{eventId}/videos (commit)
  ▼
APIM → Function App (commit handler)
  │
  │ 4. Put Block List (finalize blob)
  ▼
Blob Storage
  │
  │ 5. Enqueue message on video-transcode-queue
  ▼
Storage Queue
  │
  │ 6. Queue message triggers
  ▼
Container Apps Job (FFmpeg transcoder container)
  │
  │ 7. Read original from blob, validate with ffprobe
  │ 8. Transcode: HDR→SDR, 1080p, H.264, HLS + MP4 + poster
  │ 9. Write HLS manifest, segments, MP4 fallback, poster to blob
  │
  │ 10. POST /api/internal/video-processing-complete
  ▼
Function App (callback handler, managed-identity auth)
  │
  │ 11. Update photos row: status=active, blob paths populated
  │ 12. Push video_ready via Web PubSub + FCM
  ▼
Client (updated feed + optional push notification)
```

### ACR SKU selection

ACR has three SKUs: Basic (~$5/mo), Standard (~$20/mo), Premium (~$50/mo). **CliquePix uses Standard.**

**What matters for this workload:** only image pull latency when a Container Apps Job cold-starts. Container Apps caches pulled images on the environment infrastructure, so ACR is only touched on the first cold start after cache eviction — not on every transcode job.

**Why not Basic:**
- Basic's ~1,000 ReadOps/min ceiling is technically sufficient at MVP scale
- But throughput headroom is cheap insurance against future scale and burst scenarios (e.g., 10 users uploading videos within the same minute, all cold-starting jobs in parallel)
- Basic's 10 GB storage ceiling is tight if image versions accumulate over time

**Why not Premium:**
- Premium's extra features (geo-replication, private endpoints, content trust, customer-managed keys, retention policies) are for enterprise / compliance scenarios CliquePix doesn't need
- CliquePix runs in East US only, so geo-replication is wasted
- No VNet setup exists, so private endpoints don't apply
- $30/month premium over Standard for features that won't get exercised

**Standard gives:**
- 3x ReadOps/min throughput vs Basic (~3,000 vs ~1,000)
- 10x included storage (100 GB vs 10 GB)
- 5x webhook quota (10 vs 2) — useful if CI/CD automation is added later

**Upgrade path:** ACR SKU upgrades are non-destructive. `az acr update --name cracliquepix --sku Premium` works instantly without recreating the registry or re-pushing images. If Standard ever becomes insufficient, Premium is one command away.

### Open follow-ups for implementation

- **Container image base:** `jrottenberg/ffmpeg:6-alpine` (pre-built, trusted maintainer, well-known) vs custom Dockerfile built on `alpine:3` with FFmpeg static binary. First pass will try `jrottenberg/ffmpeg:6-alpine` and swap only if size or supply-chain concerns arise.
- **ACR name:** `cracliquepix` (no hyphens — ACR naming rule). SKU: **Standard**.
- **Container Apps Environment name:** `cae-cliquepix-prod`
- **Container Apps Job name:** `caj-cliquepix-transcoder`
- **Storage Queue name:** `video-transcode-queue` (inside existing `stcliquepixprod` storage account)
- **Job concurrency:** start with `parallelism: 5`, `replicaTimeout: 900s` (15 min hard ceiling), scale based on telemetry
- **Dead-letter handling:** Storage Queue has built-in DLQ after 5 failed dequeues. Cleanup job processes the DLQ hourly, marks affected videos as `rejected` with the error details.
- **Cost ceiling alarm:** Azure budget alert at $50/month on the resource group to catch runaway usage early
- **Local dev story:** Docker Desktop + FFmpeg container runs locally for transcoder testing; Function App runs locally via `func start`; queue dispatch tested via Azurite storage emulator
- **Managed identity callback auth:** Container Apps Job acquires a token for the Function App's App Service audience via the Azure Identity SDK (`DefaultAzureCredential().getToken('api://...')`); Function validates the token on `/api/internal/video-processing-complete`

---

## Decision 1: Schema model — extend photos table vs rename to media

### Question

Where does video metadata live and how does it relate to the existing `photos` table?

### Options

- **A.** Extend `photos` table — add `media_type` enum column and nullable video-specific columns. **CHOSEN for v1.**
- **B.** Rename `photos` to `media`, then add the same columns
- **C.** New separate `videos` table with parallel FK relationships

### Chosen: A — extend `photos` table

### Reasoning

1. **Smallest migration.** One ALTER TABLE, no data move, no code-wide table name rename. Lower risk of breaking existing photo flows.
2. **Unified feed query.** The event feed is a single SELECT across all media in an event, ordered by `created_at`. Keeping everything in one table means no UNION, no complex joins.
3. **Unified cleanup path.** The timer Function already iterates `photos` for expiration. Adding `media_type` branching inside the existing loop is simpler than maintaining two parallel cleanup paths.
4. **Reactions table is already generic.** It references `photo_id` (to be renamed `media_id` in the same migration). Works for both media types without schema changes beyond the rename.

### Trade-off accepted

**`photos` becomes a misnomer.** The table name will lie about its contents. This is explicitly noted in `CLAUDE.md` as "will be renamed to `media` post-v1 once the dust settles." The rename is a refactor we can do when the codebase has stabilized around the dual-media reality and we have time to carefully migrate all foreign keys, indexes, and code references.

### New columns (provisional — exact types/constraints finalized in the migration SQL)

Added to `photos`:

```sql
media_type            TEXT NOT NULL DEFAULT 'photo'
                      CHECK (media_type IN ('photo', 'video'))

-- Video-specific (all nullable for photo rows)
duration_seconds        INTEGER
source_container        TEXT      -- 'mp4' | 'mov'
source_video_codec      TEXT      -- 'h264' | 'hevc'
source_audio_codec      TEXT
is_hdr_source           BOOLEAN
normalized_to_sdr       BOOLEAN
hls_manifest_blob_path  TEXT      -- photos/{cliqueId}/{eventId}/{videoId}/hls/manifest.m3u8
mp4_fallback_blob_path  TEXT
poster_blob_path        TEXT
processing_status       TEXT      -- 'pending' | 'queued' | 'running' | 'complete' | 'failed' | 'rejected'
processing_error        TEXT
```

The existing `status` column stays as the high-level lifecycle (`pending` → `active` → `deleted`). `processing_status` is a separate finer-grained state specific to video transcoding.

### Migration file

`backend/src/shared/db/migrations/007_add_video_support_to_photos.sql`

Also rename the `reactions.photo_id` column to `reactions.media_id` in the same migration (the table already references `photos(id)` so there's no FK change needed, only a column rename).

### Open follow-ups

- Index on `(event_id, media_type)` for feed queries filtering by type
- Index on `(processing_status, created_at)` for orphan cleanup of failed transcodes
- Retention on `processing_error`: keep indefinitely for forensics until the row is cleaned up

---

## Decision 2: HLS delivery via User Delegation SAS

### Question

How do clients consume HLS manifests when every blob URL must be a short-lived User Delegation SAS?

### Options

- **A.** Manifest rewriting at request time. Function reads `.m3u8`, rewrites each segment URL with a fresh per-blob SAS, returns rewritten manifest. **CHOSEN.**
- **B.** Container-scoped SAS granting read access to the entire HLS prefix. **Rejected** — violates CLAUDE.md's "scoped to single blob" rule.
- **C.** Front Door with managed identity origin auth, unsigned CDN URLs to client. **Deferred to v1.5** as a performance optimization once baseline playback works.
- **D.** Function streams segments through to the client. **Rejected** — burns Function execution time per segment, defeats the purpose of blob storage.

### Chosen: A — Manifest rewriting, with 60-second in-memory cache

### How it works

1. Client calls `GET /api/videos/{videoId}/playback`
2. Function checks in-memory cache keyed on `video_id`. If hit and not stale, returns cached rewritten manifest (skip to step 7).
3. Function reads the raw `.m3u8` manifest from blob storage via managed identity
4. Function parses the manifest (simple line-based `#EXT-X-TARGETDURATION`, `#EXTINF`, segment URL per line)
5. For each segment URL (relative path like `segment_000.ts`), Function generates a fresh 15-minute User Delegation SAS scoped to that specific blob path, rewrites the manifest line with the full SAS URL
6. Function stores rewritten manifest in in-memory cache with 60-second TTL
7. Function returns the rewritten manifest (content-type `application/vnd.apple.mpegurl`) + MP4 fallback URL (also a 15-min SAS) + poster URL in the response body

### Why manifest rewriting and not broader SAS

- **Security posture stays unchanged.** Per-blob, short-lived, scoped — same as photos today.
- **Manifests are tiny.** ~1-2 KB of text, ~30 SAS generations per rewrite, total work <100ms.
- **Client doesn't need awareness that URLs are signed.** The manifest looks like any HLS playlist.
- **Cache hit path avoids blob read entirely** — most concurrent viewers of the same video share the rewritten manifest.

### Implementation notes

- User Delegation Key cached in the Function process for up to 1 hour, reused across many manifest-rewrite calls
- Segment SAS expiry: **15 minutes** (longer than photos' 5 minutes because playback sessions can last several minutes; 15 min covers most viewing without needing a refresh)
- Content-type header: `application/vnd.apple.mpegurl` for HLS
- `Cache-Control: no-store` on the HTTP response (the in-Function cache is ours; we don't want downstream caches holding stale SAS URLs)
- When the 15-min SAS expires mid-playback, `video_player` / ExoPlayer / AVPlayer errors on the next segment request. **Implemented 2026-04-10:** the player's `_onPlaybackError` listener detects the error, calls `_recoverFromSasExpiry()` which re-fetches `/playback` for a fresh manifest with new SAS URLs, reinitializes the player, and seeks to the saved position. Only triggers for cloud HLS/MP4 playback (not local file or instant-preview paths). Falls back to a user-facing error message if recovery fails.
- In-memory cache is per-Function-instance. With multiple instances (if the Function App scales out), each instance has its own cache. Cache miss rate is acceptable at MVP scale.

### Open follow-ups

- **Test HEVC source on real Android devices.** ExoPlayer HEVC support is device-dependent; some older Android devices cannot decode HEVC segments even though the manifest is valid.
- **Longer SAS expiry?** If playback-session UX proves janky with 15-min expiry (viewer pauses mid-video, resumes 20 min later), consider 30 min. Trade-off is that a leaked SAS URL is usable for longer.
- **Front Door caching for v1.5.** Origin auth via managed identity, rewritten manifests cached at the edge with a short TTL. Significantly improves playback start time for popular videos.

---

## Decision 3: Single rendition vs adaptive bitrate ladder

### Question

Does HLS deliver one quality (1080p) or multiple (360p / 720p / 1080p)?

### Options

- **A.** Single 1080p rendition. Simplest, cheapest, fastest transcode. Mobile users on slow networks suffer stalls. **CHOSEN for v1.**
- **B.** Two-rung ladder: 720p + 1080p. ~2x storage, ~1.5-2x transcode time, better mobile-network grace.
- **C.** Three-rung ladder: 360p + 720p + 1080p. Standard streaming service setup, ~3x storage, ~3x transcode time. Overkill for a group media sharing app.

### Chosen: A — single 1080p for v1

### Reasoning

- Matches CLAUDE.md's "boring and proven" and "leave it out if in doubt" principles
- Storage cost is meaningful on self-hosted infrastructure — single rendition gives breathing room while we learn real usage patterns
- Most Clique Pix viewers will be on WiFi or high-speed LTE (friends looking at event media, not commuters on subways)
- Single rendition keeps the Container Apps Job simple: one FFmpeg invocation, one HLS manifest, one MP4 fallback, one poster. A ladder doubles or triples the work per video.
- **Adaptive ladder can be added later without breaking single-rendition clients.** The HLS manifest format supports ladder upgrades transparently — we keep the originals and re-transcode into a ladder format when v1.5 lands.

### v1.5 upgrade trigger

If telemetry (`video_playback_stall` event) shows a meaningful percentage of playback sessions stalling or abandoning on mobile networks, add 720p as a second rung. We keep the original master specifically so we can re-transcode existing videos without re-uploading.

### FFmpeg invocation for v1 (post-launch state, 2026-04-08)

The original v1 ship used two sequential FFmpeg calls (one HLS, one MP4 fallback). Real-device testing revealed three problems that drove a multi-round refactor:

1. ~120s wall-clock for short videos (two sequential libx264 encodes at preset=medium)
2. HDR HEVC sources from modern iPhones produced unplayable output (10-bit High10 H.264 with BT.2020 metadata)
3. Even after consolidation to a single tee-muxer call, ~95% of phone uploads were being re-encoded unnecessarily (they were already H.264 SDR ≤1080p mp4/mov AAC)

**Current state (transcoder v0.1.6, image `cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.6`):**

The transcoder now has TWO paths chosen by `canStreamCopy(probeResult)` in `runner.ts`:

#### Fast path — `remuxHlsAndMp4` (compatible sources, ~95% of phone uploads)

Eligibility (ALL must hold):
- `videoCodec === 'h264'`
- `!isHdr`
- `height <= 1080`
- `container === 'mp4' | 'mov'`
- `audioCodec === null | 'aac'`

Command:
```
ffmpeg -y -i input.mp4 \
  -c:v copy -c:a copy \
  -map 0:v:0 -map 0:a:0? \
  -f tee \
  "[f=hls:hls_time=4:hls_playlist_type=vod:hls_segment_filename=segment_%03d.ts]manifest.m3u8|[f=mp4:movflags=+faststart]fallback.mp4"
```

Bit-exact stream copy of both video and audio into HLS (MPEG-TS segments) AND a faststart MP4 from a single FFmpeg invocation via the tee muxer. **No re-encode.** Wall-clock: ~2-5 seconds for a 30s phone capture. HLS segment lengths are variable (cut at nearest keyframe before `hls_time=4` boundary) — valid per HLS spec, modern AVPlayer + ExoPlayer handle this fine. On any failure (rare edge case like an unusual AAC profile), the runner catches the exception and falls through to the slow path automatically.

#### Slow path — `transcodeHlsAndMp4` (HDR / HEVC / >1080p / non-AAC sources)

Used when `canStreamCopy` rejects the source. Includes a proper HDR→SDR pipeline:

```
ffmpeg -y -i input.mp4 \
  -c:v libx264 \
  -preset veryfast \
  -crf 23 \
  -profile:v high -level 4.0 \
  -pix_fmt yuv420p \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 128k \
  -vf "<HDR_TO_SDR_CHAIN><SCALE>,format=yuv420p" \
  -map 0:v? -map 0:a? \
  -f tee \
  "[f=hls:hls_time=4:hls_playlist_type=vod:hls_segment_filename=segment_%03d.ts]manifest.m3u8|[f=mp4:movflags=+faststart]fallback.mp4"
```

Where `<HDR_TO_SDR_CHAIN>` is conditional on `probeResult.isHdr`:
- HDR source: `zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,`
- SDR source: `` (empty — no tonemap needed)

And `<SCALE>` is always `scale=-2:min(ih\,1080)`.

Key changes from the original v1 invocation:
- **`-preset veryfast`** (was `medium`, then `fast`, now `veryfast`) — ~25-30% faster encoding than `fast`, files ~15-20% larger but well within budget for short clips
- **`-pix_fmt yuv420p`** — forces 8-bit output. Without this, libx264 preserves the source's pixel format and produces 10-bit High10 H.264 for HDR sources, which most mobile devices can't decode
- **`-profile:v high -level 4.0`** — universally compatible with all iOS/Android devices from ~2015+
- **`-colorspace bt709 -color_primaries bt709 -color_trc bt709`** — explicit SDR metadata in the H.264 VUI parameters
- **`zscale + tonemap=hable` chain** — proper HDR→SDR tone-mapping (provided by libzimg in `jrottenberg/ffmpeg:6-alpine`, confirmed via `ffmpeg -filters`)
- **Single tee-muxer invocation** — produces both HLS and MP4 outputs from one encoder pass instead of two sequential libx264 runs

Wall-clock: ~21s for an 11.5-second HEVC HDR 1080p source (was ~29s at `preset=fast`, ~50s at `preset=medium`).

#### Poster frame (unchanged):
```
ffmpeg -y -ss 1 -i input.mp4 -vframes 1 -q:v 2 poster.jpg
```

#### Telemetry on the callback payload

`CallbackSuccessPayload` (`backend/transcoder/src/types.ts`) includes:
- `processing_mode: 'transcode' | 'stream_copy'` — required, observed via App Insights `customEvents | where name == 'video_transcoding_completed'`
- `fast_path_failure_reason?: string | null` — only set when `canStreamCopy` matched but `remuxHlsAndMp4` threw and we fell through to the slow path (rare; investigate if non-empty)

---

## Decision 4: Flutter video player library

### Question

Which Flutter package handles video playback?

### Options

- **A.** `video_player` (official Flutter team) + `chewie` (UI wrapper). **CHOSEN.**
- **B.** `better_player`. More features, spotty maintenance, features we don't need (subtitles, DRM).
- **C.** `media_kit`. Newer, more cross-platform, but iOS/Android still use platform players under the hood — similar capabilities with a newer API surface.

### Chosen: A — `video_player` + `chewie`

### Reasoning

- **Official Flutter team package.** First-party maintenance and fastest access to platform updates.
- **HLS supported out of the box** via AVPlayer (iOS) and ExoPlayer (Android). No extra configuration.
- **Smallest dependency footprint.** `video_player` is minimal; `chewie` adds basic UI (play/pause, scrub, fullscreen, buffering spinner) without extra native code.
- **Matches CLAUDE.md's "proven and boring" principle.**
- **`chewie` is mature enough for v1 UI.** For post-v1 polish, custom controls on top of `video_player` directly become viable (chewie has had maintenance lulls, but the `video_player` layer underneath is solid).

### Implementation notes

- Versions pinned exactly during implementation (`video_player: ^2.9.x`, `chewie: ^1.8.x` expected)
- `pubspec.yaml` update adds both packages
- **HEVC source playback on Android is device-dependent.** ExoPlayer supports HEVC on most modern devices but not all. Needs testing on a real Android device with a HEVC-encoded iPhone video as input.
- Web playback (if/when the web client exists): `video_player` has web support but HLS is limited. Revisit when a web client is in scope.

### Open follow-ups

- Custom player UI for v1.5 polish (gradient branding, larger controls, reaction overlays)
- Playback analytics: reuse `video_played` / `video_playback_stall` telemetry events from CLAUDE.md

---

## Decision 5: Resumable + background upload UX

### Question

How does a user upload a 100MB video over flaky mobile data without losing progress when the connection drops or the app is backgrounded?

### Sub-decision 5a: Resumability

#### Options

- **A.** **Azure Blob block uploads** — multi-part upload, client splits into 4MB blocks, commits block list when done. Resumable at block boundary. Native to Azure. **CHOSEN.**
- **B.** TUS protocol — industry-standard resumable upload. Requires a TUS server in front of blob storage. **Rejected** — adds a new compute layer we don't need for self-hosted.
- **C.** Single-shot upload with restart-on-failure. **Rejected** — restart from zero on a dropped connection is brutal UX for 100MB files.

#### Chosen: A — Azure Blob block uploads

#### How it works

1. Client calls `POST /api/events/{eventId}/videos/upload-url` with metadata: filename, expected size in bytes, expected duration
2. Function calculates `block_count = ceil(size / 4MB)`, generates a write-only User Delegation SAS for each block with a 30-minute expiry, returns:
   ```json
   {
     "video_id": "...",
     "block_upload_urls": [
       { "block_id": "0001", "url": "https://.../blob?blockid=MDAwMQ==&sv=...&sig=..." },
       { "block_id": "0002", "url": "..." },
       ...
     ],
     "commit_url": "/api/events/{eventId}/videos"
   }
   ```
3. Client uploads each block with HTTP PUT (`x-ms-blob-type: BlockBlob`, content-length per block). Retry-on-failure per block (exponential backoff, 3 attempts).
4. Client persists block-success state to local storage as it goes (shared_preferences or a dedicated upload state file) — if the app is killed or connection drops, the next launch picks up at the first incomplete block
5. On all blocks succeeded, client calls `POST /api/events/{eventId}/videos` (the commit URL) with the video ID and the ordered block ID list
6. Function calls `Put Block List` on blob storage via managed identity to stitch the final blob from the committed blocks
7. Function proceeds with server-side validation and transcoding dispatch (see Decision 0)

#### Client-side architecture

A small block-upload service on top of `dio`:

```
VideoBlockUploader
  ├── chunkFile(path, blockSizeBytes) → List<Block>
  ├── uploadBlock(block, sasUrl) → Future<void> (with retry)
  ├── persistProgress(videoId, completedBlockIds) → writes to shared_preferences
  ├── loadProgress(videoId) → reads completed block state on resume
  └── uploadAll(videoId, blocks, sasUrls) → iterates blocks, skips completed ones
```

#### Implementation notes

- **Block size: 4MB.** Standard Azure default. Gives ~25-40 blocks for a 100MB video. Small enough for decent retry granularity, large enough to avoid chattiness.
- **Block ID encoding:** base64-encoded strings of fixed length (Azure requirement). Use zero-padded sequence numbers like `000001` → base64.
- **Max block list size:** Azure Blob supports up to 50,000 blocks per blob — nowhere near a concern.
- **SAS URL strategy:** issue all block SAS URLs up front in the `upload-url` response. N is ~25-40 for a 100MB video, which is a manageable response payload (~10KB). Alternative is issuing in batches on-demand; simpler to do all at once for v1.
- **Resume on new device:** not supported in v1. Block progress is stored locally on the device that started the upload. Resume only works on the same device. If you start on phone A and switch to phone B, you restart.
- **Orphaned blocks:** if the client never commits, the uncommitted blocks are cleaned up by Azure Blob automatically after 7 days. The CliquePix orphan cleanup job additionally deletes the `photos` row and any committed-but-incomplete blob after 30 minutes.

### Sub-decision 5b: Backgrounding

#### Options

- **A.** Android foreground service + iOS `URLSession` background tasks. Lets uploads continue when the app is backgrounded. ~1-2 weeks of work for native plumbing. **Rejected for v1.**
- **B.** Restrict uploads to foreground only. Show "keep app open while uploading" UI, retry on next launch via the block-resume mechanism from 5a. **CHOSEN for v1.**

#### Chosen: B — foreground-only with block-level resume

#### Reasoning

- Matches CLAUDE.md's "leave it out if in doubt" principle. True background uploads are a v1.1 nice-to-have.
- Combined with block-upload resumability from sub-decision A, an interrupted upload (app backgrounded, connection dropped, phone locked) resumes from the next incomplete block on next launch. The user loses progress only on the block they were in the middle of — not the entire upload.
- Native plumbing for true background uploads is platform-specific and test-heavy. Deferring it keeps v1 focused on the core loop.

#### v1.1 upgrade trigger

If telemetry (`video_upload_failed` + a new `video_upload_abandoned` event) shows a meaningful percentage of uploads being abandoned due to backgrounding, add platform-native background upload in v1.1.

---

## Decision 6: Processing-state propagation

### Question

How does the client know when a video has finished processing and is ready to play?

### Options

- **A.** Polling — client calls `GET /api/videos/{id}/status` every N seconds. Simple, wastes battery, latency depends on poll interval.
- **B.** **Reuse Web PubSub** — backend pushes a `video_ready` event to the user when processing completes. Web PubSub is already provisioned for DMs.
- **C.** Push notification only — FCM push when video is ready. Works when backgrounded but unreliable for foreground.

### Chosen: B + C in combination

### Reasoning

- **Zero new infrastructure.** The Web PubSub service (`backend/src/shared/services/webPubSubService.ts`) already exists and supports the `sendToUser` pattern from the DM implementation.
- **Foreground gets instant updates** via Web PubSub — no polling, no latency, no battery waste.
- **Backgrounded/terminated apps get FCM push** — the standard Clique Pix notification flow handles tap-to-navigate.

### How it works

**When processing completes** (Container Apps Job calls `/api/internal/video-processing-complete`):

1. Function updates the `photos` row: `status='active'`, populates `hls_manifest_blob_path`, `mp4_fallback_blob_path`, `poster_blob_path`
2. Function calls `sendToUser(uploaderId, { type: 'video_ready', event_id, video_id })` — uploader sees their own upload transition from "processing" to "ready" in real-time if the app is open
3. Function calls `sendToUser` for each other clique member who is actively connected to Web PubSub — they see the new video appear in the feed without refresh
4. Function sends FCM push to all other clique members (not just connected ones) — backgrounded and terminated apps still get notified

**Client-side handling:**

- Foreground with Web PubSub connected: listener for `video_ready` event type → update the feed item's state in Riverpod → card transitions from placeholder to ready
- Backgrounded / terminated: FCM push delivers the `video_ready` type → tap navigates to `/events/{eventId}?mediaId={videoId}` which deep-links into the event feed scrolled to the video

### Implementation notes

- Web PubSub event type names are added to a shared enum in `webPubSubService.ts`
- Client listener for `video_ready` is added to the existing Web PubSub connection that DMs already maintain (one socket, multiple event types)
- FCM payload structure matches the existing notification pattern (both `notification` block for OS display and `data` block for tap routing)

---

## Decision 7: Storage tier for video originals

### Question

Hot, Cool, or Archive storage tier for the master originals?

### Chosen: Cool tier

### Reasoning

- Video originals are **write-once, read essentially never.** The only read scenarios are (1) reprocessing if we change transcoding settings, (2) if we add a bitrate ladder in v1.5, (3) forensics on a transcoding failure.
- Cool tier is **~50% cheaper than Hot** for storage with a small per-read cost we'll basically never pay.
- Archive tier is cheaper still but has **1-15 hours retrieval latency** — too painful if we ever need to reprocess in a hurry.
- HLS segments, MP4 fallback, and posters stay on **Hot tier** because they're the active playback path and need low-latency access.

### Implementation notes

- Set blob access tier during upload: `x-ms-access-tier: Cool` on the original master blob, default (Hot) for derived assets
- The Container Apps Job writes derived assets (`hls/*`, `fallback.mp4`, `poster.jpg`) with no explicit tier header — they inherit Hot from the container default
- **Bonus:** Cool tier egress cost on read is ~$0.01/GB, so even reprocessing a 100MB original costs fractions of a cent

### Open follow-ups

- **Lifecycle policy:** eventually, once a video has aged past the longest event retention (7 days), the original can be hard-deleted along with the rest of the assets. The expiration timer handles this already for both photos and videos.
- **Archive tier for cold storage of very old data?** Not applicable — videos are deleted on event expiration, never aged beyond 7 days.

---

## Decision 8: Stream-copy fast path for compatible sources

**Added 2026-04-08 after first round of post-launch performance work.**

### Question

Re-encoding every video with libx264 takes 15-25 seconds for short phone captures even at `preset=fast`. ~95% of phone uploads (modern iPhones with "Most Compatible" setting and all modern Android captures) are already H.264 SDR ≤1080p MP4/MOV with AAC audio — exactly the format the slow path produces. Should we skip the re-encode entirely for those?

### Chosen: Yes — branch in the runner on `canStreamCopy(probeResult)`

### How it works

`backend/transcoder/src/ffmpegService.ts` exports two helpers:

- `remuxHlsAndMp4(input, hlsDir, mp4)` — uses FFmpeg `-c copy -c:a copy` with the existing `-f tee` muxer to bit-exact remux the source into HLS (MPEG-TS) + MP4 (faststart) outputs. Wall-clock: ~2-5 seconds for a 30-second 1080p phone capture.
- `canStreamCopy(probe)` — predicate that returns true if ALL of: `videoCodec === 'h264'`, `!isHdr`, `height <= 1080`, container is `'mp4' | 'mov'`, audio is `null | 'aac'`.

`backend/transcoder/src/runner.ts` branches right after ffprobe:

```typescript
if (canStreamCopy(probeResult)) {
  try {
    await remuxHlsAndMp4(localInput, hlsDir, fallbackPath);
    processingMode = 'stream_copy';
  } catch (err) {
    fastPathFailureReason = err.message;
    // Clean up partial HLS, then fall through:
    await transcodeHlsAndMp4(localInput, hlsDir, fallbackPath, { isHdr: false });
  }
} else {
  await transcodeHlsAndMp4(localInput, hlsDir, fallbackPath, { isHdr: probeResult.isHdr });
}
```

### Why stream-copy is safe for HLS in MPEG-TS

- `-f hls` with `hls_time=4` cuts at the **nearest keyframe before** the target duration, so segments are variable-length (typically 2-5 sec for phone captures with sub-2-second keyframe intervals). This is valid per the HLS spec — `EXTINF` declares actual duration per segment.
- AAC-LC streams in MP4/MOV containers re-mux cleanly into MPEG-TS without bitstream filter changes. FFmpeg auto-applies `h264_mp4toannexb` for the H.264 NAL format conversion.
- Tested on real iPhone H.264 SDR captures — works on both AVPlayer (iOS) and ExoPlayer (Android).

### Why HEVC / HDR / >1080p still go through the slow path

- HEVC isn't H.264 — it requires re-encoding to H.264 for our delivery contract.
- HDR sources need tone-mapping to SDR (see Decision 3's slow path command).
- >1080p sources need downscaling.
- Non-AAC audio (rare — mostly older Android Opus or AMR captures) needs transcoding to AAC.

### Why NOT a single re-encode-everything path

- libx264 software encoding on 2 vCPU is the dominant cost. Avoiding it on the common case is the biggest single performance win available without architectural change.
- Stream-copy preserves the source's bitrate and visual quality exactly — better than any re-encode.

### Telemetry

`processing_mode: 'transcode' | 'stream_copy'` is sent in the callback payload and logged via `trackEvent('video_transcoding_completed')`. Adoption rate query:

```kql
customEvents
| where name == "video_transcoding_completed"
| summarize count() by tostring(customDimensions.processingMode)
```

Expect ~95% `stream_copy` on a representative sample of phone uploads. If `transcode` is dominant, investigate which sources are escaping the fast-path predicate.

---

## Decision 9: Instant preview for the uploader

**Added 2026-04-08. Drives perceived "polishing" wait time on the uploader's device from minutes to ~zero.**

### Question

Even with the stream-copy fast path, transcoding still takes ~15-65 seconds. For the uploader's own device, this is ~zero perceived value because they captured the video and already know what's in it. Can we let them play it instantly?

### Chosen: Yes — return a SAS read URL for the original blob in the commit response

### How it works

1. Client commits the upload via `POST /api/events/{eventId}/videos`
2. Backend (`commitVideoUpload` in `videos.ts`) marks the row `processing`, enqueues the transcode job, AND generates a 15-minute read SAS for the original blob via `generateViewSas(video.blob_path, 15 * 60)`
3. Backend returns the preview URL in the response body:
   ```json
   { "video_id": "...", "status": "processing", "preview_url": "https://stcliquepixprod.blob.core.windows.net/photos/.../original.mp4?sv=..." }
   ```
4. The Flutter `videos_repository.uploadVideo` returns `({ String videoId, String? previewUrl })` to the upload screen
5. The video card widget for processing-state videos becomes tappable when `video.previewUrl != null` (label changes from "Polishing your video" to "Tap to preview")
6. Tap navigates to `/events/{eventId}/videos/{videoId}` with `extra: previewUrl` (GoRouter `extra` so the SAS URL never appears in the address bar)
7. `VideoPlayerScreen` checks `widget.previewUrl != null` in `_initializePlayer` — if set, skips `/playback` entirely and constructs `VideoPlayerController.networkUrl(Uri.parse(widget.previewUrl!))` directly. Bottom banner reads "Playing preview while we finish processing..."
8. Background: transcoder runs normally. When complete, `video_ready` fires via Web PubSub to ALL members **including the uploader** (this is a behavior change — see Decision 10). Feed providers invalidate; the card silently upgrades from "processing + preview" to the standard active state with poster + play icon. Future taps go through the normal `/playback` HLS pipeline.

### Why this is safe

- **Only the uploader ever sees the preview URL.** The backend gates the field generation in `enrichVideoWithUrls`:
  ```typescript
  const isUploader = video.uploaded_by_user_id === userId;
  const isNotYetActive = video.status === 'processing' || video.status === 'pending';
  if (isUploader && isNotYetActive && Boolean(video.blob_path)) { /* generate preview SAS */ }
  ```
- **HEVC compatibility is tautological** for the uploader's device — it captured the video, so it can decode the original by definition. No risk of an iPhone HEVC source failing to play on someone else's older Android.
- **Stale-after-active is handled.** Once `status='active'`, the backend stops returning `preview_url` from the GET endpoints, so a feed refresh upgrades the card automatically.
- **SAS expiry of 15 minutes** is plenty of headroom. If a user pauses mid-preview for >15 min, the player errors and they back out — by then the transcode has completed and a fresh `/playback` call serves the proper HLS URL.

### Why preview, not "instant publish"

We could mark the video `active` immediately and publish to other clique members against the original blob URL — but we don't, because:
- iPhone HEVC originals would fail playback on some Android devices (the whole reason we transcode to H.264)
- Original MP4s often lack `+faststart` moov atom positioning, hurting first-frame latency
- Original file sizes are 2-5x larger than the H.264 transcode, wasting bandwidth for other viewers

So the rule is: instant preview is **uploader-only**, transcoded HLS/MP4 is what other members see.

### Failure handling

`generateViewSas` for the preview URL is wrapped in try/catch in both the commit endpoint and `enrichVideoWithUrls`. If SAS generation fails (rare — would only happen if the User Delegation Key request itself fails), the response returns `preview_url: null`, the client falls back to the standard "Polishing your video" non-tappable card, and the user sees the same UX as the original v1 ship. Telemetry: `video_preview_sas_failed` event with the error.

---

## Decision 10: Web PubSub video_ready fanout includes the uploader

**Added 2026-04-08 — corollary of Decision 9.**

### Question

Originally, `pushVideoReady` excluded the uploader from BOTH Web PubSub and FCM (`WHERE cm.user_id != $2`). The reasoning was: "the uploader already knows they uploaded it." But with instant preview (Decision 9), the uploader has a "processing + preview" card that needs to upgrade to the "active" state when transcoding finishes. Without a Web PubSub signal to their device, they keep seeing the processing card until the 30-second feed poll fires.

### Chosen: Split the channels

- **Web PubSub `video_ready`:** sent to uploader AND all other clique members. Uploader's `EventFeedScreen.onVideoReady` listener invalidates `eventVideosProvider(eventId)` and the card upgrades immediately.
- **FCM push `video_ready`:** sent to OTHER clique members only. The uploader doesn't get an FCM push — they already saw their upload complete and a "Your video is ready" notification on their own upload would be redundant noise.

### Implementation

`pushVideoReady` in `videos.ts:284-348`:

```typescript
// Web PubSub: include the uploader
await sendToUser(uploaderUserId, payload).catch(...);

// Find OTHER members for the rest of the fanout
const otherMembers = await query<{ user_id: string }>(
  `SELECT DISTINCT cm.user_id FROM events e
   JOIN clique_members cm ON cm.clique_id = e.clique_id
   WHERE e.id = $1 AND cm.user_id != $2`,
  [eventId, uploaderUserId],
);

// Web PubSub broadcast to other members
await Promise.all(otherMembers.map((m) => sendToUser(m.user_id, payload).catch(...)));

// FCM push for backgrounded other members (NOT the uploader)
const tokens = await query<...>(`SELECT pt.token FROM push_tokens pt WHERE pt.user_id = ANY($1::uuid[])`, [otherMembers.map((m) => m.user_id)]);
await sendToMultipleTokens(tokens.map((t) => t.token), 'New video ready', '...', payload);
```

### Why not also send FCM to the uploader

The uploader's instant-preview UX already covers the "I want to know when my video is ready" need without a notification. Sending FCM to the uploader would:
- Show an Android heads-up banner saying "New video ready" about a video they themselves just uploaded — UX noise
- Potentially fire while they're still tapping around in the app, making them wonder what just happened
- Burn an FCM quota slot for zero value

Web PubSub on the uploader's open WebSocket connection is the right channel — it silently flips a Riverpod provider without any visible notification.

### Update 2026-04-30: connection lifecycle shift incidentally repaired a latent gap

When this decision shipped, the WebSocket connection was opened lazily by `DmChatScreen.initState`. That meant `video_ready` Web PubSub delivery only worked for users currently on `EventFeedScreen` (the screen that subscribed to `onVideoReady`) AND who happened to have the WebSocket open via a recent DM session. Other clique members (uploader on Home, viewer on Cliques tab, etc.) received `video_ready` via FCM only — losing the sub-second feed-card upgrade promised by this decision.

The `new_event` real-time fan-out (2026-04-30) promoted the WebSocket connection to **always-on while signed in** — opened from `AuthNotifier._startLifecycle`, closed from `_stopLifecycle`, reconnected on `AppLifecycleState.resumed`. As a side effect, all clique members now receive `video_ready` real-time regardless of which screen they're on. The `RealtimeProviderInvalidator` widget at the root of `ShellScreen` could be extended in the future to subscribe to `onVideoReady` for app-wide video card refresh, but the existing `EventFeedScreen.onVideoReady` listener is sufficient because that's the only screen where stale video state matters.

See `docs/NOTIFICATION_SYSTEM.md` "New Event Real-Time Fan-Out" and `docs/EVENT_DM_CHAT_ARCHITECTURE.md` "Connection model" for the lifecycle details.

---

## Decision 11: Stable cacheKey for SAS-backed images in feed cards

**Added 2026-04-08 after observing card flicker on every 30-second poll cycle.**

### Question

The event feed has a 30-second poll timer (`event_feed_screen.dart:56-63`) that invalidates `eventPhotosProvider` and `eventVideosProvider`. Each invalidation triggers a backend refetch, and `enrichVideoWithUrls` / `enrichPhotoWithUrls` regenerate fresh User Delegation SAS URLs every call (different `se=` and `sig=` query params each time). `CachedNetworkImage` keys its disk cache on the URL by default, so a new SAS URL = cache miss = image re-fetch and re-decode = visible flicker every 30 seconds. Bad UX.

### Chosen: Set explicit `cacheKey` based on photo/video ID

`cached_network_image` accepts an explicit `cacheKey` parameter that overrides URL-based caching. When set, the cache lookup uses the key — not the URL — so a refreshed SAS URL is treated as the same image. First load fetches via the network using the URL; subsequent loads with the same key (but different URL) are served from the disk cache.

Applied in two places:
- `app/lib/features/videos/presentation/video_card_widget.dart`:
  ```dart
  CachedNetworkImage(
    imageUrl: video.posterUrl ?? '',
    cacheKey: 'video_poster_${video.id}',
    ...
  )
  ```
- `app/lib/features/photos/presentation/photo_card_widget.dart`:
  ```dart
  CachedNetworkImage(
    imageUrl: photo.thumbnailUrl ?? photo.originalUrl ?? '',
    cacheKey: 'photo_thumb_${photo.id}',
    ...
  )
  ```

### Why ID-based cache keys are safe

- Photo and video IDs are immutable UUIDs — never reused.
- The image bytes a given ID points to never change (we never re-upload to the same blob path with different content).
- If a photo or video is deleted, the row is gone and the cache entry is harmless leftover memory until the next LRU eviction.

### Why this isn't a backend-side fix

The "right" fix on paper would be to cache the generated SAS URLs in the backend for several minutes so successive feed refetches return the same URL. But:
- The in-Function memory cache is per-instance (not shared across scaled-out workers)
- TTL tuning is fiddly (too short = no benefit; too long = SAS expires before the cache does)
- The client-side `cacheKey` fix is a one-line change that completely eliminates the flicker

Backend SAS caching is deferred indefinitely. The client-side fix is sufficient.

---

## Decision 12: KEDA polling interval and min-executions tuning

**Added 2026-04-08 after queue dispatch latency was measured at ~53s for HDR videos.**

### Question

The default Container Apps Job KEDA scaler polls the queue every 30 seconds. For a queued message that arrived right after a poll, the worst-case detection latency is 30s. Combined with ~15-25s of Container Apps Job cold start (Consumption workload profile), total queue→runner-start latency was ~50-55 seconds. For an 11.5-second source video, this completely dominates the wall-clock budget.

### Chosen: pollingInterval=5, min-executions=1, retain Consumption profile

```bash
az containerapp job update \
  --name caj-cliquepix-transcoder \
  --resource-group rg-cliquepix-prod \
  --polling-interval 5 \
  --min-executions 1
```

- **`polling-interval=5`** cuts worst-case detection latency from 30s to 5s (average from 15s to 2.5s). The marginal cost of 6x more polls against the storage queue is negligible (Storage Queue bills per million transactions).
- **`min-executions=1`** ensures KEDA always has at least one execution running per polling interval, which keeps the image cached on the compute node and reduces (but doesn't eliminate) container cold-start time. Caveat: this is misleadingly named — it doesn't keep a container "warm" in the traditional sense. Container Apps Jobs are one-shot by definition; each new message spawns a fresh container.

### What this still doesn't fix

~15-25 seconds of Container Apps Jobs cold start per execution (container scheduling + image load + node.js init) is irreducible on the Consumption workload profile. Eliminating it requires migrating from a Container Apps Job (one-shot per message) to a Container Apps **Service** with a long-running queue processor (always-on container that polls and processes in a loop, scaling on queue depth via KEDA). That's a meaningful refactor: ~1-2 days of work, new health checks, different deployment model. **Deferred to v1.5.** Current ~55-65s wall clock for HDR HEVC re-encodes is acceptable for the v1 launch window now that:
- Stream-copy fast path covers the common case in 2-5s
- Instant preview makes the uploader's perceived wait ~zero
- Web PubSub `video_ready` signals other members the moment processing completes

### Telemetry

App Insights query to track queue dispatch latency:

```kql
let commits = traces
  | where operation_Name == "commitVideoUpload" and message contains "Succeeded"
  | project commit_t = timestamp, video_id = extract("Id=([0-9a-f-]+)", 1, message);
let starts = traces
  | where message startswith "[runner] Processing video"
  | project start_t = timestamp, video_id = extract("video ([0-9a-f-]+)", 1, message);
commits | join kind=inner starts on video_id
| extend dispatch_latency_s = datetime_diff('second', start_t, commit_t)
| summarize avg(dispatch_latency_s), percentiles(dispatch_latency_s, 50, 95)
```

Target after the bump: p50 < 25s, p95 < 40s.

### Container Apps Service migration — cost analysis (researched 2026-04-09)

The following cost analysis captures the pricing research for the v1.5 migration from Container Apps Jobs to a Container Apps Service (long-running queue processor). Preserved here so the decision doesn't need to be re-researched.

**Current architecture (Container Apps Job, Consumption plan):**

The transcoder is a one-shot container (2 vCPU / 4 GiB) that spins up per queue message and terminates on completion. KEDA polling at 5s, min-executions=1. Each execution incurs ~15-25s of cold start (container scheduling + image pull + node.js init) that is irreducible on the Consumption workload profile.

**Proposed architecture (Container Apps Service):**

A long-running container (2 vCPU / 4 GiB) that boots once and polls the queue in a loop. The container stays warm between jobs — no cold start. KEDA scales replicas (0→1→N) based on queue depth.

**Consumption plan rates (East US, as of April 2026):**

| Meter | Active rate | Idle rate |
|---|---|---|
| vCPU-second | ~$0.000024 | ~$0.000008 |
| GiB-second | ~$0.000003 | ~$0.000001 |

Free grants: 180,000 vCPU-seconds + 360,000 GiB-seconds + 2M requests per subscription per month.

**Cost comparison:**

| Approach | Monthly cost | Cold start? | Complexity |
|---|---|---|---|
| **Current Jobs** (pay-per-execution) | ~$3-11 at 50-200 videos/day (+ free tier covers ~1,500 transcodes) | Yes, ~15-25s every time | Low (current state) |
| **Service, minReplicas=1** (always-on) | ~$52-55/month (idle rate 24/7) | No — fully eliminated | Medium (queue loop, health checks, graceful shutdown) |
| **Service, peak-hours only** (8h/day warm, scale-to-zero overnight) | ~$17-20/month | Eliminated during peak hours only | Medium-High (scheduling + queue loop) |
| **Service, minReplicas=0** (scale-to-zero) | Same as Jobs | Yes — back to cold starts | Medium (no benefit) |

**Advantages of Service over Jobs:**
- Eliminates 15-25s cold start (dominant latency for fast-path transcodes)
- Consistent latency — no variance from container scheduling
- Simpler KEDA config — no min-executions/max-executions/replica-completion-count
- No KEDA scaler identity workaround (the `az rest` PATCH hack documented in `VIDEO_INFRASTRUCTURE_RUNBOOK.md`)
- Graceful shutdown — can finish current transcode before termination

**Disadvantages:**
- Always-on cost (~$52/month at minReplicas=1) vs near-zero cost with Jobs
- Must write the queue-polling loop (dequeue, process, visibility timeout, poison-message handling)
- Health checks (liveness/readiness probes) required
- More complex deployment (rolling updates, graceful drain)
- minReplicas=0 defeats the purpose (cold starts return)

**Recommendation for v1.5:** The ~$52/month always-on cost becomes justifiable when the user base is large enough that the 15-25s "Processing for sharing..." delay is a retention concern. For pre-launch MVP, the current Jobs approach is fine — the local-first architecture (Decision 13) already makes the uploader's experience instant. The $52/month is purely for how fast *other clique members* see the processed version.

**Alternative quick win (no architecture change):** Bump Container Apps Job CPU from 2 to 4 vCPU. This roughly halves FFmpeg encode time on the slow path (~21s → ~11s) but doesn't address cold start. ~$0.002 per transcode (double current), still negligible at MVP scale.

---

## Decision 13: Local-first uploader video playback

**Added 2026-04-09 after implementing `docs/VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md`.**

### Problem

Even with the instant-preview SAS URL (Decision 9), the uploader's playback still depended on a successful upload + backend commit before they could watch their own video. The preview_url path required a network round-trip to Azure Blob Storage. The uploader already has the file on their device — we should use it.

### Chosen: Client-side local-first playback with server reconciliation

The uploader's device creates a **local pending video item** immediately after validation (before any network work begins), making the video available for local file playback in the event feed with zero wait.

**Key architectural components:**

1. **`LocalPendingVideo` model** (`app/lib/features/videos/domain/local_pending_video.dart`) — client-side state with `UploadStage` enum: `localOnly → uploading → committing → processing → failed → complete`. Tracks `localFilePath`, `serverVideoId` (set after commit), and `previewUrl`.

2. **`localPendingVideosProvider`** (`app/lib/features/videos/presentation/videos_providers.dart`) — `StateNotifierProvider.family<..., String>` keyed on `eventId`. Not autoDispose — survives navigation. In-memory only (lost on app restart; backend state takes over).

3. **Feed merge with deduplication** (`app/lib/features/photos/presentation/event_feed_screen.dart`) — `_MediaListItem` extended with a third variant for `LocalPendingVideo`. Merge logic: local item suppresses server processing item by `serverVideoId`; auto-retires when server item reaches `active` status via `Future.microtask()`.

4. **3-tier player precedence** (`app/lib/features/videos/presentation/video_player_screen.dart`):
   - **Local file** (`VideoPlayerController.file()`) — zero network, guaranteed codec compat
   - **Preview URL** (`VideoPlayerController.networkUrl()`) — fallback if local file is missing
   - **Cloud HLS + MP4 fallback** — standard shared playback path

5. **Reconciliation** — three paths, any one triggers local item retirement:
   - Web PubSub `video_ready` → `reconcileComplete(videoId)` in the listener
   - 30-second poll → merge logic detects `serverVideo.isReady` → auto-retire via `Future.microtask()`
   - Pull-to-refresh → same as poll
   
   The `UploadStage.complete` state (vs. outright removal) prevents a visual gap between local item retirement and server item fetch completing.

6. **Local pending video card** (`app/lib/features/videos/presentation/local_pending_video_card.dart`) — dedicated card widget with upload-stage-specific subtitles, always-present play button, progress bar during upload, and retry affordance for failed uploads.

### What `preview_url` becomes

`preview_url` (Decision 9) is retained as a **secondary fallback**. Its role changes:
- Previously: primary uploader playback path while processing
- Now: fallback when the local file has been cleaned up by the OS (temp directory)

### Router migration

The video player route's `extra` parameter was migrated from `String?` (bare previewUrl) to `Map<String, dynamic>?` with keys `localFilePath` and `previewUrl`. All callers updated (`video_card_widget.dart`, `local_pending_video_card.dart`).

### What this does NOT change

- Backend pipeline (upload, transcode, HLS, video_ready) — unchanged
- Clique member playback — unchanged (cloud-only)
- Delete behavior — unchanged
- Preview URL generation on commit — unchanged (still returned, used as fallback)

---

## Decision 14: Video save-to-device and share promoted to v1

**Added 2026-04-09. Previously deferred to v1.5 (see Decision 9 follow-ups).**

### Why now

The video player's PopupMenuButton already had the delete action. The `StorageService` already had `saveVideoToGallery()` (line 56) using `Gal.putVideo()` — written in anticipation but never wired up. Promoting save/share to v1 was a wiring job, not new infrastructure.

### Implementation

**`StorageService.downloadToTempFile()`** — generalized with a named `extension` parameter (default `'jpg'`). Existing photo callers are backward-compatible. Video share calls it with `extension: 'mp4'`.

**Video player PopupMenu** — dynamic item list based on playback mode:

| Playback mode | Save | Share | Delete |
|---|---|---|---|
| Local file (`_usedLocalFile`) | Hidden | Hidden | Show if `_playbackInfo != null` |
| Instant preview (`_usedInstantPreview`) | Hidden | Hidden | Show |
| Normal HLS/MP4 (`_playbackInfo != null`) | Show | Show | Show |

Save uses `StorageService.saveVideoToGallery()` with the MP4 fallback URL. Share uses `downloadToTempFile(extension: 'mp4')` + `Share.shareXFiles()`. Both mirror the photo detail screen pattern (`photo_detail_screen.dart:49-84`).

**`_playbackInfo` state field** — `VideoPlaybackInfo` is now stored as a class field in the player (previously a local variable in `_initializePlayer()`), making `mp4FallbackUrl` available for save/share after init.

### Files modified

| File | Change |
|---|---|
| `app/lib/services/storage_service.dart` | `downloadToTempFile` gains `extension` parameter |
| `app/lib/features/videos/presentation/video_player_screen.dart` | Save/share handlers, `_playbackInfo` state, dynamic menu items |

---

## Decision 15: iOS bypasses HLS in v1 (uses MP4 directly)

**Added 2026-05-03 after a user-reported iPhone video hang revealed a documented AVFoundation limitation.**

### Question

iPhone users reported that every cloud video tap resulted in a forever spinner. Same code worked on Android. What's the iOS-specific failure mode and what's the fix?

### Root cause

`VideoPlayerController.networkUrl(Uri.file(<m3u8 path>), formatHint: VideoFormat.hls)` with a manifest whose segment lines are absolute `https://*.blob.core.windows.net/...` SAS URLs (the shape produced by the backend's `rewriteHlsManifest` at `backend/src/shared/services/hlsManifestRewriter.ts`) leaves `AVPlayerItem` in `Status: Unknown` indefinitely on iOS. `controller.initialize()` returns a `Future` that **NEVER resolves and NEVER throws** — so the existing `try/catch` HLS-then-MP4-fallback flow never engaged. ExoPlayer (Android) handles cross-scheme manifest→segment fine, which masked the bug for the entire video v1 ship cycle.

This is a documented (but not previously hit) iOS AVPlayer constraint. AVURLAsset value-loading hangs when the playlist URL scheme (`file://`) doesn't match the segment URL scheme (`https://`) AND the manifest is loaded from a local sandboxed path. The "offline HLS" pattern (`AVAssetDownloadURLSession`) downloads segments to disk and works correctly because BOTH manifest and segments are `file://`. Streaming HLS (`https://` manifest + `https://` segments) also works correctly. **Mixed schemes are unsupported.**

### Chosen: iOS skips HLS entirely on the cloud tier — uses MP4 fallback as the primary path

In `app/lib/features/videos/presentation/video_player_screen.dart::_initializePlayer`, after `repo.getPlayback()` resolves and before the HLS attempt:

```dart
if (Platform.isIOS) {
  _iosForcedMp4 = true;
  await _initWithMp4(playback);
  return;
}
// Android continues with HLS-first flow unchanged
```

`_iosForcedMp4` is a new state flag distinct from `_usedFallback`. The caption logic in `_buildBody` gates the misleading "Playing standard quality" caption on `!_iosForcedMp4` so iOS users don't see degraded-service messaging on their primary path.

### Why this is safe for v1

- v1 is **single-rendition HLS** — one quality level, one bitrate. MP4 progressive download with `+faststart` (per Decision 3 / FFmpeg `movflags=+faststart`) starts playback after a few hundred KB, functionally equivalent UX to single-rendition HLS.
- The MP4 fallback URL (`mp4_fallback_blob_path`) is already produced by the transcoder for both fast and slow paths (per Decision 3's tee-muxer invocation). No backend change required.
- Local-first uploader (`VideoPlayerController.file(file)`) and instant-preview (`VideoPlayerController.networkUrl(Uri.parse(previewUrl))`) tiers work on iOS unchanged — they don't go through the HLS path.
- Android continues to use HLS-first with MP4 fallback unchanged.

### Universal init-timeout safety net (shipped same commit)

In addition to the iOS branch, every `controller.initialize()` site is now wrapped in a `_initWithTimeout(controller, duration, tier)` helper:
- **8 second timeout** for local file (no network excuse for a longer wait)
- **15 second timeout** for instant-preview / HLS / MP4 (covers slow LTE)
- **On any exception** (including TimeoutException): disposes the controller before rethrowing — critical on iOS where an orphaned `AVPlayerItem` can wedge subsequent attempts by holding the AVPlayer slot
- **Outer catch differentiates** TimeoutException ("Playback didn't start in time. Tap back and try again.") from generic init failure ("We couldn't play this video. Please try again later.")
- **Mounted-race fix** on both `_wireChewie` and `_wireChewieFromController` — disposes the controller cleanly when the user navigates away during init (was a real bug pre-fix: ChewieController was constructed before the mounted check, then state mutation was skipped, leaving `_chewieController == null` which renders SizedBox.shrink — blank screen)
- **`[VPS]` `debugPrint` markers** at every step so future iOS playback regressions can be triaged with `flutter run --release` + Xcode device console in minutes instead of hours

### What this does NOT change

- Backend pipeline (transcoder, manifest rewriter, blob storage layout, /playback endpoint) — completely unchanged
- Web client — uses `hls.js`, not affected by AVPlayer's cross-scheme limitation
- Android playback — HLS still primary
- Adaptive bitrate readiness — when v1.5 ships ladder support, the iOS branch remains because the AVPlayer limitation is independent of rendition count. The proper architectural fix (raw-m3u8 backend endpoint serving manifest over HTTPS) is needed before iOS can use HLS again

### v1.5 follow-up (deferred)

Track 2 from the original plan: add `GET /api/videos/{videoId}/playback.m3u8` returning the rewritten HLS manifest as raw text with `Content-Type: application/vnd.apple.mpegurl`. Client constructs:
```dart
VideoPlayerController.networkUrl(
  Uri.parse('https://api.clique-pix.com/.../playback.m3u8'),
  formatHint: VideoFormat.hls,
  httpHeaders: {'Authorization': 'Bearer $token'},
)
```

AVPlayer handles HTTPS-manifest + HTTPS-segments cleanly. Required for adaptive bitrate ladders (v1.5+). Has auth-token-staleness complications because `VideoPlayerController` bypasses the Dio `AuthInterceptor` — needs explicit `tokenStorage.isTokenStale()` check + 401-retry path before player init. **Once Track 2 ships, the iOS branch in this Decision becomes a Platform.isIOS-conditional URL choice (m3u8 endpoint vs raw playback JSON) rather than a complete HLS bypass.**

### Investigation cost (recorded for future maintainers)

The bug was hard to triage because:
- The symptom was "spinner spins forever" — no error, no crash, no exception in any catch path
- `flutter run --debug` on iOS 26.x triggers the LLDB launch-watchdog issue (per BETA_OPERATIONS_RUNBOOK), so live diagnosis required `--release` + Xcode device console
- "Blank white screen on profile-mode launch" was a red herring — slow profile-mode startup + VM service detection failure, NOT a `main()` hang. The cold-start refactor (commit 3f882a3) was briefly suspected but cleared
- iOS device testing in beta had primarily exercised the local-first uploader path (which works on iOS without HLS), so the cloud HLS hang was latent for the entire video v1 ship cycle

Wall-clock from first symptom report to verified fix: ~3 hours. The `[VPS]` debugPrint scaffolding shipped with this fix means any future iOS playback regression should triage in under 30 minutes.

---

## Decisions deferred to the implementation plan

These are known-unknowns that will be resolved when we write the implementation plan, not now:

- **Full API request/response schemas** — exact field names, error codes, pagination for video feed queries
- **Exact migration SQL** — `backend/src/shared/db/migrations/007_add_video_support_to_photos.sql` with ALTER TABLE, new columns, indexes, check constraints, column renames (`reactions.photo_id` → `reactions.media_id`)
- **Container image Dockerfile** — base image choice (jrottenberg/ffmpeg vs custom), transcoder runner script language (Node.js vs Python), entrypoint, env var contract
- **Dispatcher Function wiring** — exact Storage Queue message format, queue poll vs HTTP trigger on Container Apps Job
- **Callback endpoint authentication details** — managed identity token validation, required claims, audience config
- **Processing-state placeholder card UI** — Flutter widget design for the "Processing…" state in the event feed, error state UI for rejected/failed transcodes
- **Expiration cleanup mechanics for HLS prefix** — how to enumerate and batch-delete N segment blobs without hitting Function execution timeout on large events
- **Push notification payload format** — exact keys in `data` block, collapse key strategy for multiple rapid `video_ready` events
- **Budget alert thresholds** — specific dollar amounts for Azure Monitor alerts on Container Apps Jobs, ACR, and Storage egress
- **Bicep IaC for the new resources** — ACR, Container Apps Environment, Container Apps Job, Storage Queue, role assignments
- **CI/CD for the container image** — GitHub Actions workflow or manual `az acr build` documented in a runbook

---

## Locked answers (resolved before implementation)

All 7 open questions were resolved in the conversation that approved this doc. The answers below are binding inputs to the implementation plan.

### Q1: Container image base — `jrottenberg/ffmpeg:6-alpine`

Use the public `jrottenberg/ffmpeg:6-alpine` image as the transcoder base. Pin to a specific image SHA in the Dockerfile for reproducibility. Switch to a custom Dockerfile only if a specific issue arises (CVE, missing codec, etc.). Trusted maintainer with steady release cadence.

### Q2: Local dev workflow — Docker Desktop installed locally

Docker Desktop runs the transcoder container locally for fast iteration. Test FFmpeg invocations on real video files (sample iPhone MOVs, Android MP4s, HDR sources) without round-tripping through ACR + Container Apps. The implementation plan includes a `make transcode-local INPUT=sample.mov` style developer command. Cloud-only testing only happens for the integration test of the queue dispatch + callback round-trip.

### Q3: ffprobe validation strictness — Reject cleanly with specific error codes

Server-side ffprobe runs first inside the transcoder container. On failure, the video is rejected with a specific error code and user-facing message:
- `UNSUPPORTED_CONTAINER` — "We can't process this video format. Please use MP4 or MOV."
- `UNSUPPORTED_CODEC` — "This video uses a codec we can't process. Try re-recording or exporting to H.264."
- `DURATION_EXCEEDED` — "Videos must be 5 minutes or shorter."
- `CORRUPT_MEDIA` — "We couldn't read this video file. It may be damaged."
- `HDR_CONVERSION_FAILED` — "We couldn't convert this HDR video for playback. Try re-recording in standard mode."

No transcode-and-hope. Rejected videos move to `status='rejected'` and the user gets the error in the upload-confirm response.

### Q4: Cost ceiling — $50/month Azure budget alert

Azure budget alert configured on the resource group at $50/month. At MVP scale (~$8-25/month total expected), $50 represents a real anomaly (~2-3x normal usage), not noise. Catches both runaway transcoding scenarios and configuration mistakes (e.g., a job stuck in retry loop). Threshold is reviewable as usage patterns become clear.

### Q5: Delete during transcoding — Mark row deleted, callback discards results

When a user deletes a video (or its event) while a transcode is in progress:
1. The `photos` row is immediately marked `status='deleted'`
2. The Container Apps Job continues running (not cancelled — no cancellation plumbing needed)
3. When the job completes and POSTs to `/api/internal/video-processing-complete`, the Function sees the row is already `deleted`, discards the results, and prefix-deletes any blobs the job already wrote
4. Wasted compute is a few minutes of FFmpeg time (~$0.01 per discarded transcode at MVP scale) — acceptable cost for not having to build job cancellation

**Updated 2026-04-28 — organizer-delete also follows this path.** As of the moderation feature, the event organizer (`events.created_by_user_id`) can also trigger a delete during transcoding. The `deleteVideo` handler intentionally does NOT filter on `status` (it accepts deletes at any status) so the same Q5 mechanics apply unchanged — the row flips to `deleted`, the in-flight job's eventual callback sees the deleted state and discards. Authorization is computed via `canDeleteMedia` (`backend/src/shared/utils/permissions.ts`); the deleter's role (`'uploader' | 'organizer'`) is recorded on the `video_deleted` telemetry alongside `uploaderId` and `eventOrganizerId`. See `docs/ARCHITECTURE.md` §6 + this file's referencing entries below for moderation context.

### Q6: HEVC fallback on Android — Rely on video_player auto-fallback + telemetry

The transcoder always outputs **H.264** for both HLS and MP4 fallback (HEVC is the input format we accept, not the output we deliver — see Decision 3). This means the HEVC-on-old-Android problem is largely a non-issue at the playback layer because we never serve HEVC.

For the edge case where some other playback failure occurs:
- `video_player` attempts HLS first
- On any HLS error, the client automatically retries with the MP4 fallback URL from the playback response
- Add telemetry: `video_playback_fallback_used` event with `reason` field
- If telemetry shows this happens often, revisit during v1.5

### Q7: Per-user video limits — Soft cap of (currently 10, originally 5) videos per user per event

Each user is limited to a fixed number of **currently non-deleted videos in any single event**. Counting semantics:
- Counts videos in `status IN ('pending', 'processing', 'active')` for this user in this event
- Deleted videos (`status='deleted'`) **do NOT count** — deletion frees a slot, encouraging cleanup
- Rejected videos (`status='rejected'`) do NOT count
- Limit is enforced at the `POST /api/events/{eventId}/videos/upload-url` endpoint
- Error response: `VIDEO_LIMIT_REACHED` — "You've reached the N-video limit for this event. Delete a video to upload another."

Photos remain unlimited per user per event — this cap is video-specific because video has dramatically higher per-item cost (transcoding compute + multi-asset storage) than photos.

**Current value: `PER_USER_VIDEO_LIMIT = 10`** (`backend/src/functions/videos.ts:39`).

**History:** originally shipped at 5. Bumped to 10 on 2026-04-08 as an emergency unblock when a tester piled up 5 broken videos in a test event from earlier HDR re-encode failures and couldn't clean them up via the (then-missing) in-app delete UI. With the delete UI now shipping (`video_player_screen.dart` PopupMenuButton — see Decision 8 below), 10 is also a reasonable steady-state value: typical clique events rarely exceed a handful of videos per user, and the higher ceiling reduces the chance of a tester or power user getting wedged again. The Flutter friendly-error string in `_friendlyError` is hard-coded to "5-video limit" as of the bump — update it if the limit is changed again, or refactor it to read from a backend-supplied number.

---

## Original "Open questions" — preserved for history

1. **Container image maintenance policy** → Q1 above
2. **Local dev workflow for the transcoder** → Q2 above
3. **ffprobe validation strictness** → Q3 above
4. **Transcoding cost ceiling** → Q4 above
5. **Video deletion while transcoding** → Q5 above
6. **HEVC support on low-end Android devices** → Q6 above
7. **Per-member video limits** → Q7 above

The implementation plan can now be written with enough specificity to execute without further clarification rounds.
