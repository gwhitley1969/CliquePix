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
- ACR Basic SKU hosts the image
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

6. **Scale to zero when idle.** No baseline cost beyond ~$5/month ACR. You only pay vCPU-seconds of actual transcoding work.

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

### Open follow-ups for implementation

- **Container image base:** `jrottenberg/ffmpeg:6-alpine` (pre-built, trusted maintainer, well-known) vs custom Dockerfile built on `alpine:3` with FFmpeg static binary. First pass will try `jrottenberg/ffmpeg:6-alpine` and swap only if size or supply-chain concerns arise.
- **ACR name:** `cracliquepix` (no hyphens — ACR naming rule) or `cliquepixacr`. First pass: `cracliquepix`.
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
- When the 15-min SAS expires mid-playback, `video_player` / ExoPlayer / AVPlayer will error on the next segment request. The client catches the error, re-calls `/playback` for a fresh manifest, and reloads the player at the current position. This is ugly UX for a session paused near the end of a 5-min video; v1 accepts the edge case, v1.5 addresses it with either a longer SAS expiry or Front Door CDN caching.
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

### FFmpeg invocation for v1

```
ffmpeg -i input.mp4 \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  -vf "scale=-2:min(ih\,1080)" \
  -hls_time 4 \
  -hls_playlist_type vod \
  -hls_segment_filename "segment_%03d.ts" \
  manifest.m3u8
```

Key parameters:
- `-preset medium` — balance between speed and compression efficiency
- `-crf 23` — "visually indistinguishable" quality target
- `-b:a 128k` — AAC audio at 128kbps
- `scale=-2:min(ih\,1080)` — downscale only when source height exceeds 1080 (no upscaling below)
- `-hls_time 4` — 4-second segments (standard for VOD)
- `-hls_playlist_type vod` — VOD playlist (no sliding window)

Separate FFmpeg invocation for the MP4 fallback:
```
ffmpeg -i input.mp4 -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k \
  -vf "scale=-2:min(ih\,1080)" -movflags +faststart fallback.mp4
```

And for the poster:
```
ffmpeg -i input.mp4 -ss 00:00:01 -vframes 1 -q:v 2 poster.jpg
```

(Exact parameters will be verified during implementation on real iPhone/Android source footage.)

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

## Open questions for the user before implementation begins

These need explicit answers before the implementation plan gets written:

1. **Container image maintenance policy.** Are we OK using `jrottenberg/ffmpeg:6-alpine` as the base image (trusted public maintainer), or do you want a custom Dockerfile with pinned FFmpeg version for supply-chain control? Trade-off: custom is more work and more upkeep, public is easier but depends on a third party.

2. **Local dev workflow for the transcoder.** Running the transcoder locally requires Docker Desktop or a Docker alternative installed. Do you have Docker set up, or should the implementation plan include setup steps? Or do you want to do transcoder development in the cloud (push to ACR and test on Azure) and skip local development entirely?

3. **ffprobe validation strictness.** When a user uploads a "weird" video (e.g., an MOV with a non-standard audio codec), do we (a) reject it cleanly with an error message, or (b) attempt to transcode and see if FFmpeg can handle it, or (c) transcode anyway and mark the result as "best effort"? Recommendation: (a) for v1 simplicity.

4. **Transcoding cost ceiling.** What's your monthly spend comfort zone for the new infrastructure? The architecture assumes MVP scale (~$8-20/month) but you should set an Azure budget alert at a number you'd want to know about. Suggest $50/month as the first alarm threshold.

5. **Video deletion while transcoding.** If a user deletes a video (or the event containing it) while transcoding is in progress, what should happen? Options: (a) let the transcode finish then delete everything, (b) send a cancel signal to the Container Apps Job, (c) mark the row as `deleted` and let the callback discard its results. Recommendation: (c) — simplest, no job-cancellation plumbing needed, transcoder work is a small waste but low cost.

6. **HEVC support on low-end Android devices.** Some older Android devices cannot decode HEVC in ExoPlayer even though ExoPlayer advertises HEVC support. How do we want to handle playback failure on these devices? Options: (a) always show MP4 fallback, (b) rely on video_player to auto-fallback, (c) accept the edge case and show an error. Recommendation: (b) — let `video_player` handle it and add telemetry to track how often it happens.

7. **Per-member video limits.** Do we want to cap how many videos a user can upload to a single event, or a daily limit, to prevent runaway costs from a misbehaving client? Not in the spec but worth considering. Recommendation: soft-cap at 10 videos per user per event for v1.

Once these are answered, the implementation plan can be written with enough specificity to execute without further clarification rounds.
