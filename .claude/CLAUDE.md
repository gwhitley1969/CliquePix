# CLAUDE.md – Clique Pix Development Guardrails

## What This File Is

This is the authoritative reference for Claude Code while developing Clique Pix. When any question arises about scope, architecture, patterns, or priorities — this file wins. Read it before generating code, making architectural decisions, or suggesting features.

If anything in this file conflicts with PRD.md or ARCHITECTURE.md, this file takes precedence for development decisions. Raise the conflict so the other docs can be updated.

---

## Product Identity

Clique Pix is a **private, event-based photo and video sharing** mobile app. Users create Cliques (persistent groups), start Events (temporary media sessions), and share photos and videos that auto-expire from the cloud.

**It is not** a social network, messaging app, content discovery platform, or photo editing suite.

### The Core Loops

Every line of code must serve one of these two loops. Photos and videos are both first-class media types but have asymmetric processing needs, so they have parallel sub-loops.

#### Photo Loop

1. User signs in
2. User creates an Event (picks or creates a Clique during creation)
3. User takes or uploads a photo
4. User edits the photo (crop, draw, stickers, filters)
5. Photo is compressed on-device and uploaded directly to Blob Storage
6. Other event members are notified via push
7. Event feed displays the photo (thumbnail in feed, full-size on tap)
8. Members view, react, save to device, or share externally
9. Photos auto-delete from the cloud after the event duration expires

#### Video Loop

1. User signs in
2. User creates or opens an Event
3. User captures (in-app camera) or uploads a video from device library
4. Client-side validation (extension, duration ≤ 5 min, file size estimate). **No in-app editing in v1** — videos skip the editor entirely
5. Video uploads to Blob Storage via resumable block uploads (native Azure multi-part)
6. Backend validates server-side, dispatches transcoding to a Container Apps Job (FFmpeg container)
7. Backend marks media as `processing` and renders a placeholder card in the event feed
8. When transcoding completes, backend marks media as `ready`, poster is generated, push notification sent to event members
9. Members tap the card to open the in-app player; playback streams via HLS with MP4 fallback
10. Members can react, save to device, or share externally — same model as photos
11. Video assets (original master + HLS delivery assets + MP4 fallback + poster) auto-delete with the event

If a feature does not directly support one of these loops, it does not belong in v1.

---

## v1 Scope — Hard Boundaries

### Build These

**Core + Photos (existing)**
- Authentication via Entra External ID (email OTP / magic link, minimal friction)
- 5-layer token refresh defense for the Entra 12-hour timeout bug
- Cliques: create, join via invite link / SMS / QR, list, view members, leave
- Deep linking for Clique invites (Universal Links on iOS, App Links on Android)
- Events: create Event first (pick or create Clique during creation), duration locked to three presets (24h / 3 days / 7 days default), list, expire, manual deletion by event organizer (with confirmation dialog)
- In-app camera capture (photo + video)
- Upload from camera roll (photo + video)
- Client-side image compression before upload (strip EXIF, resize to max 2048px, JPEG quality 80, convert HEIC to JPEG)
- Photo upload via User Delegation SAS (two-phase: get upload URL, then confirm)
- Event feed: vertical scroll, large photo/video cards, user attribution, timestamp, thumbnails/posters
- Lightweight reactions: ❤️ 😂 🔥 😮 (unique constraint per user per media item per type)
- Save individual photo/video to device, multi-select batch download with progress
- External share via native OS share sheet (no direct third-party API integrations)
- Auto-deletion: timer-triggered cloud cleanup when event duration expires
- Orphan cleanup: pending uploads not confirmed within 10 minutes (photos) / 30 minutes (videos — larger files need more time)
- Push notifications via FCM: new photo added, new video ready, event expiring in 24 hours
- Thumbnail generation (in-process `sharp`, 400px longest edge, JPEG quality 70)

**Video (v1)**
- Video upload: in-app camera recording and upload from device library
- Client-side video validation: extension (MP4, MOV), duration ≤ 5 min, file size estimation
- Server-side authoritative video validation: container, codec, duration, HDR metadata via ffprobe
- Video transcoding pipeline: TWO paths chosen by `canStreamCopy(probeResult)`:
  - **Fast path (`remuxHlsAndMp4`):** stream-copy compatible sources (H.264 SDR ≤1080p mp4/mov AAC) directly to HLS + MP4 with `-c copy -f tee`. ~2-5 sec wall-clock. Covers ~95% of phone uploads.
  - **Slow path (`transcodeHlsAndMp4`):** full re-encode for HDR / HEVC / >1080p / non-AAC sources. Includes `zscale + tonemap=hable` HDR→SDR pipeline, `-pix_fmt yuv420p`, `-profile:v high -level 4.0`, `-colorspace bt709 -color_primaries bt709 -color_trc bt709`. preset=`veryfast`. ~21 sec for an 11s HDR HEVC source.
  - Both paths use the same single tee-muxer FFmpeg invocation (HLS + MP4 from one pass).
  - Runs in Container Apps Job with `jrottenberg/ffmpeg:6-alpine` base image. KEDA polling 5s, min-executions=1.
- **Instant preview for the uploader:** commit endpoint returns a 15-min read SAS for the original blob in `preview_url`. Uploader's processing card is tappable ("Tap to preview") and plays the original MP4 immediately. When transcode completes, Web PubSub `video_ready` upgrades the card silently. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 9.
- Resumable video uploads using Azure Blob block uploads (4MB blocks, client-side block state persistence for resume-on-restart)
- Video playback: in-app player using `video_player` + `chewie`, HLS preferred (with `formatHint: VideoFormat.hls` via `VideoPlayerController.networkUrl(Uri.file(...))`), MP4 fallback. **`VideoPlayerController.file()` does NOT support `formatHint` — must use `.networkUrl` even for local file:// URIs.**
- **Video delete UI:** PopupMenuButton in the video player AppBar, mirroring `photo_detail_screen.dart:43-124`. Delete-only for now (Save/Share deferred). Calls `videosRepositoryProvider.deleteVideo` and invalidates `eventVideosProvider(eventId)` so the card disappears immediately.
- Video processing-state UX: placeholder card in the event feed while transcoding, push notification + Web PubSub signal when ready
- Processing-state propagation: Web PubSub `video_ready` event (foreground, **including the uploader** so their instant-preview card upgrades) + FCM push (backgrounded, **excluding the uploader** to avoid redundant notification noise about their own upload)
- HLS delivery via User Delegation SAS: backend rewrites `.m3u8` manifests at request time with per-segment signed URLs (60s in-Function cache, 15-min SAS expiry per segment)
- Video assets auto-delete with the event: original master + HLS package (prefix-delete) + MP4 fallback + poster
- **Per-user video cap:** `PER_USER_VIDEO_LIMIT = 10` (originally 5; bumped 2026-04-08 — see Decision Q7 in `docs/VIDEO_ARCHITECTURE_DECISIONS.md`). Counts videos in `pending`/`processing`/`active`. Backend enforces at the upload-url endpoint with `VIDEO_LIMIT_REACHED` error code.
- **Backend error code propagation to client:** the Flutter `_friendlyError` in `video_upload_screen.dart` reads `e.response?.data['error']['code']` from a `DioException` and switches on the structured backend error code — NOT on `e.toString()` (which only contains the message field). Pattern: switch on the canonical code, fall through to `errorMap['message']` for unknown codes, then to network/socket checks, then to a generic fallback. Mirror this pattern wherever client UX maps backend error codes.

### Do Not Build

- ~~Chat, comments, or threads~~ (event-centric 1:1 DMs implemented — no group chat, no global inbox, no attachments)
- Followers / following
- Public feeds or discovery
- Custom photo editor UI (use `pro_image_editor` package — do not build editor from scratch)
- ~~Video capture or playback~~ (promoted to v1 — see Video Loop above and `docs/VIDEO_ARCHITECTURE_DECISIONS.md`)
- Video editing (trim, crop, filters, captions, effects) — videos in v1 are upload-and-share, no in-app modification
- 4K video delivery
- HDR video playback preservation (HDR sources are normalized to SDR)
- Live streaming
- Video DM attachments (event DMs stay text-only)
- Per-video adaptive bitrate ladders beyond what's required for reliable 1080p delivery (two-rung 720p+1080p is a post-v1 upgrade)
- Background upload continuation when app is backgrounded (foreground service Android, `URLSession` iOS) — v1 requires keeping app open during video upload; block-upload resumability handles connection drops
- True managed video services (Cloudflare Stream, Mux, Azure Media Services) — v1 is self-hosted on Azure Container Apps Jobs for data sovereignty
- AI features of any kind
- Monetization, subscriptions, or paywalls
- Printed albums
- User search or directory
- Read receipts or typing indicators
- Stories or ephemeral content beyond the event model
- Firebase backend services (Auth, Firestore, etc.) — FCM is used for push transport only
- Redis, SignalR, Service Bus, Notification Hubs (Web PubSub is used for DMs and video processing-state push)

### When In Doubt

Leave it out. A missing feature can be added later. A cluttered v1 cannot be un-cluttered.

---

## Tech Stack — Locked Decisions

### Frontend
- **Flutter** (Dart) — single codebase for iOS and Android
- **State management:** Riverpod
- **HTTP client:** Dio
- **Image picker:** image_picker (also handles video picking — unified media picker)
- **Image compression:** flutter_image_compress
- **Secure token storage:** flutter_secure_storage
- **Non-sensitive flags:** shared_preferences
- **Push notifications:** firebase_messaging (FCM transport only)
- **Image caching:** cached_network_image
- **Image editor:** pro_image_editor (^5.1.4 — crop, draw, stickers, filters, text). **Callback rule:** v5.x calls `onCloseEditor` after `onImageEditingComplete` completes. Only pop in `onCloseEditor`, never in `onImageEditingComplete`, or you get a double-pop. **Photos only** — videos skip the editor in v1.
- **Video player:** `video_player` (official) + `chewie` (UI controls). HLS via AVPlayer (iOS) and ExoPlayer (Android). Versions pinned during implementation.
- **Video metadata probing (client-side validation):** `video_player` plus a small duration/dimension pre-check, or `video_compress` if deeper metadata is needed. Final choice locked during implementation.
- **Deep links:** app_links
- **QR code generation:** qr_flutter
- **MSAL authentication:** msal_auth (^3.3.0, v2 embedding, custom API scope `access_as_user`)

Do not introduce dependencies not listed here without discussing the tradeoff first.

### Backend (Azure)

| Layer | Service | Purpose |
|-------|---------|---------|
| Entry point | Azure Front Door | Global load balancing, SSL termination, WAF |
| API gateway | Azure API Management | Rate limiting, API versioning, policy enforcement |
| Compute (API) | Azure Functions (TypeScript, Node.js) | REST API, timer cleanup, photo thumbnail generation, video upload orchestration |
| Compute (video transcode) | Azure Container Apps Jobs | Runs FFmpeg transcoder per-video (HDR→SDR, 1080p HLS package, MP4 fallback, poster). Scale-to-zero. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 0. |
| Container registry | Azure Container Registry (Standard SKU) | Hosts the FFmpeg transcoder image (`cracliquepix`). Standard chosen over Basic for throughput headroom (3x ReadOps/min) and 10x storage (100 GB vs 10 GB) — performance insurance at ~$15/month premium over Basic. |
| Job dispatch | Azure Storage Queue | Queues video transcoding jobs. Triggered by video upload-confirm endpoint; polled by Container Apps Job |
| Database | PostgreSQL Flexible Server | Relational data |
| Object storage | Azure Blob Storage | Photo and video originals, photo thumbnails, HLS segments, MP4 fallbacks, video posters |
| Identity (consumer) | Microsoft Entra External ID | User auth (email OTP / magic link) |
| Identity (infra) | System-assigned managed identity | Function App + Container Apps Job → Blob Storage, Key Vault |
| Secrets | Azure Key Vault | DB connection string, FCM credentials |
| Observability | Application Insights | Telemetry, errors, dependencies (shared by Function App and Container Apps Job) |
| Realtime messaging | Azure Web PubSub | Real-time DM delivery + video processing-state push (`video_ready` event) via WebSocket |

### Architecture Pattern

All API traffic flows: **Flutter → Front Door → APIM → Azure Functions → PostgreSQL / Blob Storage**

No exceptions for the API control plane. No direct Function App URLs exposed to the client. APIM is the single published API surface.

**Async video transcoding path (control plane stays inside the pattern):**
Function API endpoint (`POST /api/events/{eventId}/videos`) → enqueues message on Azure Storage Queue → Container Apps Job triggered → FFmpeg transcodes → Job calls back to internal Function endpoint with results → Function updates DB, pushes `video_ready` via Web PubSub + FCM. The client only talks to the Function API; the Container Apps Job is an internal backend component.

**Video playback path:**
Client calls `GET /api/videos/{videoId}/playback` → Function reads stored HLS manifest from Blob, rewrites segment URLs with fresh 15-minute User Delegation SAS per segment, returns rewritten manifest. Client plays HLS through `video_player`. Manifest is cached in-Function for 60 seconds to amortize blob reads across concurrent viewers.

Front Door and APIM are included from day one. This matches the production pattern used in My AI Bartender and avoids the pain of retrofitting API gateway infrastructure after the fact.

---

## Project Structure (Flutter)

```
/lib
  /app                    # App entry point, root widget
  /core
    /theme                # Colors, text styles, gradients, design tokens
    /routing              # Route definitions, deep link handling
    /constants            # API endpoints, duration presets
    /utils                # Date formatting, image helpers, validators
    /errors               # Error types, failure classes
  /features
    /auth                 # Login, signup, token management, 5-layer refresh
      /data
      /domain
      /presentation
    /cliques              # Clique CRUD, invites, membership
      /data
      /domain
      /presentation
    /events               # Event CRUD, duration presets, expiration
      /data
      /domain
      /presentation
    /photos               # Photo upload pipeline, feed, reactions, save, share
      /data
      /domain
      /presentation
    /videos               # Video upload (block-based), player, processing-state UI, save, share
      /data
      /domain
      /presentation
    /notifications        # Push token registration, notification list
      /data
      /domain
      /presentation
    /profile              # User profile, settings
      /data
      /domain
      /presentation
  /models                 # Shared data models
  /services               # API client, storage service, notification service
  /widgets                # Reusable UI components
```

Keep this structure. Do not flatten it. Do not invent alternative organizations.

---

## Design System

### Reference Materials

The app icon concept (camera with aqua→blue→violet gradient, white body, prominent lens, pink/magenta accent dot) is the approved direction. The mockup screenshots are **color scheme references only** — do not implement specific UI elements, navigation structures, or features shown in the mockups. The actual UI will be designed and built from scratch following these design tokens.

### Color Palette

| Token                | Hex       | Usage                                    |
|----------------------|-----------|------------------------------------------|
| Electric Aqua        | #00C2D1   | Primary accent, gradient start           |
| Deep Blue            | #2563EB   | Primary action, gradient middle          |
| Violet Accent        | #7C3AED   | Gradient end, secondary highlights       |
| Soft Aqua Background | #E6FBFF   | Light background, cards                  |
| White Surface        | #FFFFFF   | Content surfaces, cards                  |
| Primary Text         | #0F172A   | Headlines, body text                     |
| Secondary Text       | #64748B   | Timestamps, captions, labels             |

### Primary Gradient

`#00C2D1 → #2563EB → #7C3AED` (left to right, or top to bottom depending on context)

Use for: app bar accents, CTA buttons, event headers, splash screen, onboarding highlights.

Do not overuse. Most surfaces should be white or soft aqua. The gradient is an accent, not a background.

### Typography

- Use system fonts (San Francisco on iOS, Roboto on Android) via Flutter defaults
- Do not import custom fonts for v1
- Headings: bold, 18–24sp
- Body: regular, 14–16sp
- Captions/timestamps: regular, 12sp, secondary text color

### Iconography

- Use Material Icons or Lucide as icon set
- Consistent weight and size throughout
- Camera icon is the brand's visual anchor

### Spacing & Layout

- Base unit: 8px
- Standard padding: 16px
- Card border radius: 12px
- Photo cards should be large and dominant — the feed is photo-first, not text-first
- Minimum tap target: 48x48px

### Brand Personality

Vibrant, modern, social, premium but approachable. Not overly feminine, not corporate.

---

## API Design

### Style

RESTful JSON APIs over HTTPS. No GraphQL. No event-driven patterns in v1.

### Endpoints

```
POST   /api/auth/verify
GET    /api/users/me
DELETE /api/users/me

POST   /api/cliques
GET    /api/cliques
GET    /api/cliques/{cliqueId}
POST   /api/cliques/{cliqueId}/invite
POST   /api/cliques/{cliqueId}/join
GET    /api/cliques/{cliqueId}/members
DELETE /api/cliques/{cliqueId}/members/me
DELETE /api/cliques/{cliqueId}/members/{userId}

POST   /api/cliques/{cliqueId}/events
GET    /api/cliques/{cliqueId}/events
GET    /api/events/{eventId}
DELETE /api/events/{eventId}

POST   /api/events/{eventId}/photos/upload-url
POST   /api/events/{eventId}/photos
GET    /api/events/{eventId}/photos
GET    /api/photos/{photoId}
DELETE /api/photos/{photoId}

POST   /api/events/{eventId}/videos/upload-url    # returns block-upload URLs + commit URL
POST   /api/events/{eventId}/videos               # confirm upload, enqueue transcoding job
GET    /api/events/{eventId}/videos
GET    /api/videos/{videoId}                       # metadata + processing status
GET    /api/videos/{videoId}/playback              # returns rewritten HLS manifest URL + MP4 fallback URL + poster URL (15-min SAS)
DELETE /api/videos/{videoId}

POST   /api/internal/video-processing-complete     # Container Apps Job callback (managed-identity authenticated)

POST   /api/photos/{photoId}/reactions
DELETE /api/photos/{photoId}/reactions/{reactionId}
POST   /api/videos/{videoId}/reactions
DELETE /api/videos/{videoId}/reactions/{reactionId}

GET    /api/notifications
PATCH  /api/notifications/{notificationId}/read
DELETE /api/notifications/{notificationId}
DELETE /api/notifications
POST   /api/push-tokens

POST   /api/events/{eventId}/dm-threads
GET    /api/events/{eventId}/dm-threads
GET    /api/dm-threads/{threadId}
GET    /api/dm-threads/{threadId}/messages
POST   /api/dm-threads/{threadId}/messages
PATCH  /api/dm-threads/{threadId}/read
POST   /api/realtime/dm/negotiate
```

### Photo Upload Flow

**User Delegation SAS — RBAC-backed, no storage account keys.**

1. Client compresses image (see Media Handling Pipeline)
2. Client calls `POST /api/events/{eventId}/photos/upload-url`
3. Function validates Entra token and confirms user is a member of the event's clique
4. Function generates a photo ID and blob path (`photos/{cliqueId}/{eventId}/{photoId}/original.jpg`), creates a photo record with status `pending`
5. Function uses managed identity to request a **User Delegation Key**, generates a **write-only User Delegation SAS** scoped to that exact blob path, 5-minute expiry
6. Function returns the SAS upload URL and photo ID to the client
7. Client uploads compressed image directly to Blob Storage using the SAS URL
8. Client calls `POST /api/events/{eventId}/photos` with photo ID and metadata (dimensions, MIME type)
9. Function verifies blob exists, reads blob properties (content type, file size), updates photo record to status `active`
10. Function triggers async thumbnail generation (in-process via `sharp`)
11. Function sends push notifications to event members
12. Function returns complete photo record to client

If the client does not confirm upload (step 8) within 10 minutes, the orphan cleanup process removes the blob and pending record.

### Video Upload Flow

**Multi-block upload via User Delegation SAS per block. No storage account keys. Resumable at block boundary.**

1. Client performs local validation: extension (MP4/MOV), duration ≤ 5 min, approximate file size
2. Client calls `POST /api/events/{eventId}/videos/upload-url` with video metadata (filename, size, duration)
3. Function validates Entra token and clique membership, generates a video ID and blob path (`photos/{cliqueId}/{eventId}/{videoId}/original.mp4` — container name `photos` retained for all media), creates a `photos` table row with `media_type='video'` and `status='pending'`
4. Function calculates block count = `ceil(file_size / 4MB)`, generates a **block-level write-only User Delegation SAS** for each block with a 30-minute expiry, returns the ordered array of block upload URLs + a commit URL
5. Client uploads each 4MB block via individual HTTP PUT with retry-on-failure. Client persists block-success state to local storage as it goes — if the app is killed or connection drops, resume picks up at the next incomplete block
6. On all blocks uploaded, client calls the commit URL: `POST /api/events/{eventId}/videos` with the video ID and its block list. Function calls `Put Block List` on blob storage to stitch the final blob
7. Function runs server-side authoritative validation via ffprobe equivalent in a separate job step (queued alongside transcoding): container, codec, duration, HDR metadata. If validation fails, the video record is marked `rejected` and the blob is deleted
8. Function enqueues a message on the transcoder Storage Queue with `{video_id, blob_path, event_id, clique_id}`
9. Function marks the video row as `processing` and returns the record to the client
10. **Container Apps Job** is triggered by the queue message, pulls the original blob via managed identity, runs FFmpeg:
   - HDR→SDR normalization (if source is HDR)
   - Downscale to max 1080p (preserves aspect ratio, no upscaling)
   - Encode H.264 HLS with 4-second segments, single rendition (no ladder in v1)
   - Produce MP4 fallback (single file, progressive download)
   - Extract poster frame (first I-frame or 1-second mark)
11. Container Apps Job writes HLS segments, manifest, MP4 fallback, and poster to blob storage at `photos/{cliqueId}/{eventId}/{videoId}/{hls/|fallback.mp4|poster.jpg}`
12. Container Apps Job calls `POST /api/internal/video-processing-complete` with results (managed identity authenticated)
13. Function updates video row to `status='active'`, stores manifest/fallback/poster blob paths, pushes `video_ready` event via Web PubSub + sends FCM push to event members
14. Client receives push → navigates to event feed → video card transitions from placeholder to ready state

If the client does not call the commit URL (step 6) within **30 minutes** (longer than photo's 10 min because video uploads take longer), the orphan cleanup process deletes any uploaded blocks and the pending record.

**User Delegation SAS Rules:**
- Photo upload SAS expiry: 5 minutes maximum
- Video block upload SAS expiry: 30 minutes (covers slow connections mid-upload)
- Photo view SAS expiry: 5 minutes
- Video HLS segment view SAS expiry: 15 minutes (covers longer playback sessions)
- Upload SAS permissions: write-only (client cannot read, list, or delete)
- View SAS permissions: read-only
- SAS scope: single blob path only, never container-level, even for HLS (manifest rewriting signs each segment individually)
- User Delegation Key: cache and reuse for up to 1 hour (valid for up to 7 days, but rotate frequently)

### Photo View / Download

- Feed endpoints return photo metadata with short-lived read-only User Delegation SAS URLs for both thumbnail and original
- Feed cards load thumbnails only
- Full-size loads on photo detail view / full-screen tap

### Video Playback

- Feed endpoints return video metadata with: poster SAS URL, duration, processing status, and a `playback_url` pointing at `/api/videos/{videoId}/playback`
- Feed cards show the poster image + duration overlay + play icon
- Tapping a video opens the in-app player (`video_player` + `chewie`)
- Player fetches the playback manifest by calling `/api/videos/{videoId}/playback` — Function reads the stored HLS manifest, rewrites each segment URL with a fresh 15-minute User Delegation SAS, returns the rewritten manifest
- Player attempts HLS first; on any HLS failure, falls back to the MP4 progressive URL (also a fresh 15-minute SAS)
- If the 15-minute SAS expires mid-playback (long session, paused for 20 minutes), the player errors → client re-calls `/playback` → receives a fresh manifest → reloads player at current position
- Manifest rewrite cost is amortized by a 60-second in-Function cache keyed on `video_id`

### Response Format

Success:
```json
{
  "data": { ... },
  "error": null
}
```

Error:
```json
{
  "data": null,
  "error": {
    "code": "CLIQUE_NOT_FOUND",
    "message": "The requested clique does not exist."
  }
}
```

Use consistent error codes. Never return raw exception messages or stack traces to the client.

---

## Data Architecture

### PostgreSQL Tables

**users**: id (UUID PK), external_auth_id, display_name, email_or_phone, avatar_url (nullable), created_at, updated_at

**cliques**: id (UUID PK), name, invite_code (unique), created_by_user_id (FK → users), created_at, updated_at

**clique_members**: id (UUID PK), clique_id (FK), user_id (FK), role (owner/member), joined_at — unique constraint on (clique_id, user_id)

**events**: id (UUID PK), clique_id (FK), name, description (nullable), created_by_user_id (FK), retention_hours (24/72/168 — three presets only), status (active/expired), created_at, expires_at (computed: created_at + retention_hours)

**photos** (hosts both photo and video rows — the name is historical; will be renamed to `media` post-v1 once dust settles):
- Core: id (UUID PK, generated server-side at upload-url step), event_id (FK), uploaded_by_user_id (FK), blob_path, original_filename, mime_type, width, height, file_size_bytes, status (pending/active/deleted/processing/rejected), created_at, expires_at (inherits from event), deleted_at (nullable)
- **media_type** enum: `'photo' | 'video'` — NEW for video v1
- Photo-specific: thumbnail_blob_path (nullable until generated)
- Video-specific (all nullable for photo rows): duration_seconds, source_container (mp4/mov), source_video_codec (h264/hevc), source_audio_codec, is_hdr_source (boolean), normalized_to_sdr (boolean), hls_manifest_blob_path, mp4_fallback_blob_path, poster_blob_path, processing_status (pending/queued/running/complete/failed), processing_error (nullable text)

**reactions**: id (UUID PK), media_id (FK → photos.id — works for both photos and videos since they share the table), user_id (FK), reaction_type (heart/laugh/fire/wow), created_at — unique constraint on (media_id, user_id, reaction_type)

**push_tokens**: id (UUID PK), user_id (FK), platform (ios/android), token (FCM registration token), created_at, updated_at

**notifications**: id (UUID PK), user_id (FK), type (new_photo/new_video/video_ready/event_expiring/event_expired/member_joined/event_deleted), payload_json (JSONB), is_read (boolean, default false), created_at

### Media Status Flow

**Photo:** `pending` (upload-url issued) → `active` (client confirmed upload) → `deleted` (cleanup job ran)

**Video:** `pending` (upload-url issued) → `processing` (blocks committed, transcoding in progress) → `active` (Container Apps Job reported success, manifest/fallback/poster stored) → `deleted` (cleanup job ran). Alternative terminal state: `rejected` (server-side ffprobe validation failed — bad codec, corrupt, etc.)

### Blob Storage

Single container named `photos` (hosts both photos and videos — name is historical) with virtual path hierarchy:

```
photos/{cliqueId}/{eventId}/{photoId}/original.jpg         # photo original
photos/{cliqueId}/{eventId}/{photoId}/thumb.jpg            # photo thumbnail

photos/{cliqueId}/{eventId}/{videoId}/original.mp4         # video master (Cool tier)
photos/{cliqueId}/{eventId}/{videoId}/hls/manifest.m3u8    # HLS playlist
photos/{cliqueId}/{eventId}/{videoId}/hls/segment_000.ts   # HLS segments
photos/{cliqueId}/{eventId}/{videoId}/hls/segment_001.ts
...
photos/{cliqueId}/{eventId}/{videoId}/fallback.mp4         # progressive MP4
photos/{cliqueId}/{eventId}/{videoId}/poster.jpg           # video poster frame
```

**Storage tiering:**
- Photo originals + thumbnails: Hot tier (frequently read from feed)
- Video HLS segments + MP4 fallback + poster: Hot tier (active playback)
- Video originals (master): **Cool tier** — written once, read essentially never (only for reprocessing scenarios). Cool is ~50% cheaper than Hot for storage with a small per-read cost we'll basically never pay. Archive tier rejected due to retrieval latency.

**Expiration cleanup:**
- Photo cleanup: delete `original.jpg` + `thumb.jpg` (two blob deletes per photo)
- Video cleanup: **prefix-delete** all blobs under `photos/{cliqueId}/{eventId}/{videoId}/` — this includes HLS manifest + all segments (possibly 30+ files) + MP4 fallback + poster + original master. The timer Function must enumerate and delete, not just target specific paths.

---

## Entra External ID — Known Bug & Required Workaround

### The Problem

Entra External ID (CIAM) tenants have a **hardcoded 12-hour inactivity timeout** on refresh tokens. This is a confirmed Microsoft bug — standard Entra ID tenants get 90-day lifetimes. No portal-based configuration options exist.

Error signature: `AADSTS700082: The refresh token has expired due to inactivity... inactive for 12:00:00`

### Required: 5-Layer Token Refresh Defense

This pattern is proven in production on My AI Bartender. Implement all five layers.

| Layer | Mechanism | Trigger | Reliability | Purpose |
|-------|-----------|---------|-------------|---------|
| 1 | Battery Optimization Exemption | First login (Android only) | Critical | Allows background tasks on Samsung/Xiaomi/Huawei |
| 2 | AlarmManager Token Refresh | Every 6 hours | Very High | Fires even in Doze mode via `exactAllowWhileIdle` |
| 3 | Foreground Refresh on App Resume | Every app open | Very High | Safety net — catches all background failures |
| 4 | WorkManager Background Task | Every 8 hours | Medium | Backup mechanism |
| 5 | Graceful Re-Login UX | When all else fails | N/A | "Welcome back" dialog with stored user hint, one-tap re-auth |

### Layer Details

**Layer 1 — Battery Optimization Exemption (Android)**
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` must be requested at **runtime**, not just declared in the manifest
- Show a user-facing dialog after first login: "To keep you signed in, Clique Pix needs permission to run in the background"
- Without this, Samsung/Xiaomi/Huawei will kill background tasks
- Service: `BatteryOptimizationService` (singleton)

**Layer 2 — AlarmManager (Android)**
- Use `zonedSchedule` with `AndroidScheduleMode.exactAllowWhileIdle`
- Schedule every 6 hours (half the 12-hour timeout = safe margin)
- Use a silent notification channel (`Importance.min`, `Priority.min`, `silent: true`)
- Filter `TOKEN_REFRESH_TRIGGER` payloads in main.dart to prevent navigation errors if user taps the notification
- Reschedule after each successful refresh
- Cancel on logout

**Layer 3 — Foreground Refresh (Both platforms, most reliable)**
- On `AppLifecycleState.resumed`, check token age via `lastRefreshTime` in secure storage
- If token is > 6 hours old, proactively refresh before it expires
- If refresh succeeds, reschedule AlarmManager
- If refresh fails, trigger Layer 5 (graceful re-login)
- This is the primary iOS defense since iOS lacks reliable background task guarantees

**Layer 4 — WorkManager (Backup)**
- `registerPeriodicTask` every 8 hours with `NetworkType.connected` constraint
- With Layer 1 exemption granted, reliability improves on Android
- This is a backup, not the primary mechanism

**Layer 5 — Graceful Re-Login UX (Fallback)**
- When all background mechanisms fail, show a "Welcome back, [Name]!" dialog instead of a full login screen
- Store `lastKnownUser` before clearing auth state
- Use `loginHint` to pre-fill email in the MSAL interactive flow
- Try silent acquisition first, fall back to interactive with hint

### Android Permissions Required

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

### iOS Considerations

- `BGAppRefreshTask` via BGTaskScheduler — request 6-hour intervals, but iOS controls actual timing
- Foreground refresh (Layer 3) is the most reliable mechanism on iOS
- Users who disable Background App Refresh will need to re-login after 12 hours — Layer 5 handles this gracefully

### Token Storage

- Auth tokens and refresh tokens: `flutter_secure_storage` only — **never** `shared_preferences`
- Track `lastRefreshTime` in secure storage for proactive refresh decisions
- Store `lastKnownUser` profile for the graceful re-login dialog
- Clear all stored tokens, user data, and cancel all background refresh jobs on logout

### Key Timing

- Microsoft inactivity timeout: 12 hours (hardcoded, not configurable)
- AlarmManager interval: 6 hours
- Foreground refresh threshold: 6 hours since last refresh
- WorkManager interval: 8 hours (backup)
- Safety margin: 6 hours (half the timeout)

### Reference

Full implementation details, code samples, and debug log tags are in `ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

---

## Media Handling Pipeline

Media uploads are the most performance-critical path in Clique Pix. Photos and videos have radically different shapes — photos can be compressed cheaply client-side to 500KB–1.5MB, while videos are 50–150MB even after sensible encoding and must be transcoded server-side.

### Photo Pipeline — Client Side (Before Upload)
1. User selects or captures photo
2. Strip EXIF data (removes GPS coordinates, device info, timestamps)
3. Resize: longest edge max 2048px, maintain aspect ratio
4. Compress: JPEG quality 80
5. Convert HEIC to JPEG on-device before upload
6. Reject files over 10MB after compression (safety net)
7. Use `flutter_image_compress` for this pipeline

### Photo Pipeline — Why These Numbers

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max dimension | 2048px | Covers all current phone screens. This is a group photo app, not a stock photography service. |
| JPEG quality | 80 | Industry standard for "visually indistinguishable." Quality 90+ wastes bytes; quality 70 shows artifacts on gradients and skin tones. |
| Max file size | 10MB | Post-compression safety net. At 2048px / quality 80, photos land around 500KB–1.5MB. |
| Format | JPEG | Universal compatibility. HEIC converted client-side. |

### Photo Pipeline — Server Side (After Client Upload to Blob)

The Function never touches photo bytes during the upload flow. At the confirmation step:

1. Verify blob exists at expected path via managed identity
2. Read blob properties to validate content type (JPEG, PNG only) and file size (reject > 15MB)
3. Update photo metadata in PostgreSQL
4. Trigger async thumbnail generation

### Photo Thumbnail Generation

- Triggered inline (fire-and-forget async) inside the upload-confirm endpoint — see `backend/src/functions/photos.ts`
- Function reads original blob via managed identity (`DefaultAzureCredential`), uses `sharp` to generate a 400px longest edge / JPEG quality 70 thumbnail, writes it back to Blob Storage
- Updates `thumbnail_blob_path` in the record
- Target thumbnail size: ~30–80KB
- If thumbnail generation fails, the feed falls back to loading the original (slower but not broken)

### Video Pipeline — Client Side (Before Upload)

Videos cannot be meaningfully compressed on the client (mobile transcoding is slow, battery-killing, and unpredictable). The client's job is validation only.

1. User selects or records video
2. Extract basic metadata: extension, approximate duration, file size
3. Reject if extension is not MP4 or MOV
4. Reject if duration exceeds 5 minutes
5. Show estimated upload time to the user ("~3 min on WiFi, ~12 min on LTE") before starting
6. No EXIF-equivalent stripping in v1 — video metadata isn't stripped client-side (could be added later)

### Video Pipeline — Why These Numbers

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max duration | 5 minutes | Matches the spec. Balances "long enough for meaningful moments" against transcoding cost and storage. |
| Accepted containers | MP4, MOV | Covers 99% of phone captures. iPhone records MOV (QuickTime), Android records MP4. |
| Accepted source codecs | H.264, HEVC | Modern phones default to H.264 or HEVC. Other codecs (VP9, AV1) rejected server-side. |
| Max output resolution | 1080p | No 4K delivery in v1. Source above 1080p is downscaled; source below is not upscaled. |
| Output codec | H.264 | Best compatibility across `video_player` platforms and HLS clients. |
| HDR policy | Normalize to SDR | Consistent playback across devices; HDR preservation is a post-v1 concern. |

### Video Pipeline — Server Side (After Client Commits Upload)

1. Function verifies all blocks committed successfully (blob exists with expected size)
2. Function generates a 15-min read SAS for the original blob and returns it as `preview_url` in the commit response (instant preview for the uploader — Decision 9)
3. Function enqueues a transcoding job on Azure Storage Queue
4. **Container Apps Job** picks up the queue message (KEDA polling 5s, min-executions=1) and runs FFmpeg:
   - ffprobe first: authoritative validation of container/codec/duration/HDR. Reject if invalid.
   - `canStreamCopy(probeResult)` predicate decides between fast and slow path:
     - **Fast path (`remuxHlsAndMp4`)** for H.264 SDR ≤1080p mp4/mov AAC sources: `ffmpeg -c copy -c:a copy -map 0:v:0 -map 0:a:0? -f tee "[f=hls...]manifest.m3u8|[f=mp4:movflags=+faststart]fallback.mp4"` — bit-exact remux, ~2-5s wall-clock, no re-encode. On failure, falls through to slow path.
     - **Slow path (`transcodeHlsAndMp4`)** for HDR / HEVC / >1080p / non-AAC: `-c:v libx264 -preset veryfast -crf 23 -profile:v high -level 4.0 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -b:a 128k -vf "<HDR_CHAIN>scale=-2:min(ih\,1080),format=yuv420p" -map 0:v? -map 0:a? -f tee "[f=hls...]manifest.m3u8|[f=mp4:movflags=+faststart]fallback.mp4"`. The HDR chain is `zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,` (only when `probeResult.isHdr`; empty for SDR).
   - Both paths produce HLS manifest + segments + MP4 fallback from a SINGLE FFmpeg invocation via the tee muxer.
   - Extract poster frame separately (`-ss 1 -vframes 1`).
5. Container Apps Job writes all outputs to blob storage via managed identity, plus a separate call to set the original master to Cool tier
6. Container Apps Job calls `POST /api/internal/video-processing-complete` with results, including `processing_mode: 'transcode' | 'stream_copy'` and `fast_path_failure_reason?: string | null` for telemetry
7. Function updates video row, pushes `video_ready` via Web PubSub to ALL clique members **including the uploader** (so their instant-preview card upgrades) + FCM push to OTHER members only

**Locked parameters (do not change without measuring):**
- libx264 preset: `veryfast` (slow path only — fast path uses `-c copy`)
- CRF: 23
- AAC bitrate: 128k
- HLS segment duration: 4 seconds (variable in fast path, exactly 4 in slow path)
- Forced 8-bit output: `-pix_fmt yuv420p` — REQUIRED on the slow path or HDR sources produce 10-bit High10 H.264 that mobile devices can't decode
- Profile/level: high/4.0 — universal mobile compatibility from ~2015+
- Color metadata: bt709 — explicit SDR tags in the H.264 VUI parameters

The full ffmpeg invocations and parameter rationale live in `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 3 (post-launch state) and Decisions 8-12.

### Feed Display

**Photos:**
- Feed cards load thumbnails only
- Full-size loads on photo detail view / full-screen tap
- Use `cached_network_image` for client-side image caching
- Placeholder shimmer animation while images load

**Videos:**
- Feed cards load posters only + duration overlay + play icon
- Tap opens the in-app player (`video_player` + `chewie`)
- While processing, card shows a placeholder with a spinner and "Processing…" label; transitions to the poster state when `video_ready` arrives (via Web PubSub or feed refresh)
- Player prefers HLS; falls back to MP4 on HLS failure

---

## Deep Linking — Clique Invites

Clique invites are core to the product loop. When a user taps an invite link, the app must open directly to the invite acceptance screen.

### Link Format

```
https://clique-pix.com/invite/{inviteCode}
```

QR codes encode the same URL. Generate QR on the client using `qr_flutter`.

### Platform Setup

**iOS — Universal Links:**
- Host `apple-app-site-association` at `https://clique-pix.com/.well-known/apple-app-site-association`
- Configure Associated Domains in Xcode: `applinks:clique-pix.com`
- Handle incoming link via `app_links` package

**Android — App Links:**
- Host `assetlinks.json` at `https://clique-pix.com/.well-known/assetlinks.json`
- Configure intent filter in AndroidManifest with `autoVerify="true"`
- Handle incoming link via `app_links` package

### Hosting Well-Known Files

Serve from Azure Front Door or a simple static web app. Static JSON files that rarely change.

### Flow

1. **App installed:** open app, route to invite acceptance screen, call `POST /api/cliques/{cliqueId}/join` with invite code
2. **App not installed:** open App Store / Play Store listing. Deferred deep linking is a post-v1 enhancement.

---

## Security Rules

### API Authorization — Every Endpoint Must Enforce:
- User is authenticated (valid Entra token verified by the Function)
- User belongs to the clique/event they are accessing (membership check)
- User can only delete their own photos

### Blob Storage Access — RBAC + User Delegation SAS:
- **No storage account keys.** No account-key-based SAS tokens anywhere in the system.
- `allowSharedKeyAccess: false` on the storage account
- Function App managed identity assigned `Storage Blob Data Contributor` + `Storage Blob Delegator` roles
- Client uploads via write-only User Delegation SAS (scoped to single blob, 5-minute expiry)
- Client views via read-only User Delegation SAS (scoped, short-lived)
- All server-side blob access via `DefaultAzureCredential` (managed identity in Azure, developer credentials locally)

### Storage
- No public anonymous access on any container
- Container access policy: private
- Photo URLs are never permanent or publicly accessible (always behind short-lived SAS)

### Privacy
- Private by default — no public feeds, no user directory, no content discovery
- EXIF data stripped client-side before upload (GPS, device info, timestamps)
- Photos only visible to event members

### Client
- Auth tokens and refresh tokens in `flutter_secure_storage` only — **never** `shared_preferences`
- `shared_preferences` acceptable only for non-sensitive flags (e.g., `has_seen_onboarding`, `battery_dialog_shown`)
- No tokens, credentials, or PII in debug logs (even in debug builds)
- Clear all auth state, stored tokens, and cached user data on logout
- Cancel all background refresh mechanisms (AlarmManager, WorkManager) on logout

---

## Error Handling Patterns

### Client
- Wrap all API calls in try/catch
- Map HTTP errors to typed failure classes (NetworkFailure, AuthFailure, NotFoundFailure, etc.)
- Show user-friendly error messages, not technical details
- Retry upload failures with exponential backoff (max 3 retries)
- Handle offline state: show cached content where available, queue actions where possible

### Backend
- Return structured error responses (see Response Format above)
- Log errors to Application Insights with correlation IDs
- Never return stack traces or internal details to the client
- Validate all input — never trust the client

---

## Expiration & Cleanup

### Event & Media Expiration

Timer-triggered Azure Function (every 15 minutes):

1. Query media (photos + videos) where `expires_at < now()` and `status = 'active'`
2. For each media row, delete associated blobs via managed identity:
   - **Photo:** `blob_path` (original) + `thumbnail_blob_path` (thumbnail)
   - **Video:** `blob_path` (original master), `mp4_fallback_blob_path`, `poster_blob_path`, plus **prefix-delete** all blobs under the HLS directory (`photos/{cliqueId}/{eventId}/{videoId}/hls/*` — may be 30+ segment files)
3. Update media records: `status = 'deleted'`, `deleted_at = now()`
4. If all media in an event are deleted, mark event `status = 'expired'`
5. Mark DM threads as `read_only` for expired events
6. Delete any remaining blobs for expired events under `photos/{cliqueId}/{eventId}/*` (safety net covering both photo and video paths)
7. **Hard-delete expired event records** — CASCADE removes photos, videos (same table), reactions, DM threads, and DM messages
8. Log `expired_media_deleted` (with count split by type) and `expired_events_deleted` telemetry with counts

### Orphan Cleanup

Separate scheduled check (every 15 minutes):

1. **Photos:** Query photos where `media_type = 'photo'` AND `status = 'pending'` AND `created_at < now() - 10 minutes`. Delete orphaned blob and pending record.
2. **Videos:** Query photos where `media_type = 'video'` AND `status = 'pending'` AND `created_at < now() - 30 minutes`. Delete any uploaded blob/blocks and pending record. Longer window because video uploads take longer.
3. **Video processing failures:** Query photos where `media_type = 'video'` AND `processing_status = 'failed'` AND `created_at < now() - 1 hour`. Prefix-delete any partially-written HLS outputs, delete the record.
4. Log `orphaned_uploads_cleaned` and `failed_video_processing_cleaned` telemetry with counts

### Important

- Device-saved copies remain untouched — only cloud-managed copies are deleted
- Users are notified 24 hours before expiration via push
- Expired events are fully removed from the database, not soft-deleted
- Video expiration is more expensive than photo expiration because of the HLS prefix-delete — budget accordingly and batch deletes where possible

---

## Notification Architecture

### Delivery

FCM (Firebase Cloud Messaging) for push delivery to both Android and iOS. FCM is a transport mechanism only — no Firebase backend services, no Firebase Auth, no Firestore.

### Push Triggers

| Trigger | Notification Type | Web PubSub Recipients | FCM Recipients | Payload |
|---------|------------------|-----------------------|----------------|---------|
| Photo uploaded to event | `new_photo` | — | All event clique members except uploader | `{ event_id, photo_id }` |
| Video upload started (processing) | *(no push — only feed placeholder update)* | — | — | — |
| Video ready to play | `video_ready` | **All event clique members INCLUDING uploader** | All event clique members **except uploader** | `{ event_id, video_id }` |
| Video processing failed | `video_processing_failed` | — | Uploader only | `{ event_id, video_id, reason }` |
| Someone joins a clique | `member_joined` | — | All existing clique members except joiner | `{ clique_id, clique_name, joined_user_name }` |
| Event expiring in 24h | `event_expiring` | — | All event clique members | `{ event_id }` |
| Event expired | `event_expired` | — | All event clique members | `{ event_id }` |
| Event deleted by organizer | `event_deleted` | — | All clique members except deleter | `{ event_id, event_name }` |

**No notifications sent** for member removals, voluntary departures, or video upload initiation (the feed placeholder card is enough signal to the uploader; other members are notified when the video is ready to play, not when it starts transcoding).

**Video processing-state propagation has two channels with split recipient lists:**
- **Web PubSub** (foreground, app running and connected): backend pushes `video_ready` to ALL clique members including the uploader. The uploader needs this signal so their instant-preview card upgrades from "processing + Tap to preview" to the standard active state with poster + play icon. Without it, the uploader keeps seeing the processing card until the 30-second feed poll fires.
- **FCM** (backgrounded/terminated): backend sends `video_ready` push to OTHER clique members only. The uploader is excluded because they already saw the upload complete and know what they uploaded — a push notification about their own video would be redundant noise.

See `pushVideoReady` in `backend/src/functions/videos.ts:284-348` and `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 10.

### Backend Flow

1. Backend action (photo upload, clique join, timer) queries relevant members' push tokens
2. Function sends push via FCM HTTP v1 API using `sendToMultipleTokens()` with `notification` + `data` payloads
3. Function creates notification records in `notifications` table for in-app display
4. Failed token sends trigger stale token cleanup

### Client Flow

| App State | Handler Location | Display |
|-----------|-----------------|---------|
| **Foreground** | `main.dart` → `FirebaseMessaging.onMessage` | `flutter_local_notifications.show()` heads-up banner |
| **Background** | OS auto-displays from FCM `notification` payload | `onMessageOpenedApp` → GoRouter navigation on tap |
| **Terminated** | OS auto-displays from FCM `notification` payload | `getInitialMessage()` → GoRouter navigation on tap |

**Key pattern:** The `onMessage` listener is set up in `main.dart` immediately after `flutter_local_notifications` plugin initialization — not in a separate service class. This ensures the plugin is always ready when `show()` is called.

### Notification Channel

Created programmatically in `main.dart` at startup:
- Channel ID: `cliquepix_default` (referenced in AndroidManifest)
- Importance: HIGH (heads-up banners)
- Android 13+ permission requested via `requestNotificationsPermission()`

### Token Management

- `PushNotificationService` initializes after auth — gets FCM token, registers via `POST /api/push-tokens`
- Listens to `FirebaseMessaging.instance.onTokenRefresh` and re-registers when tokens rotate
- Backend upserts on conflict (same token → update timestamp)
- Remove on logout
- Failed sends remove stale tokens via `DELETE FROM push_tokens WHERE token = ANY($1)`

### Notification Tap Navigation

All taps navigate via GoRouter using `data` payload:
- `event_id` → `router.push('/events/$eventId')`
- `clique_id` → `router.push('/cliques/$cliqueId')`
- `video_id` + `event_id` (from `video_ready`) → `router.push('/events/$eventId?mediaId=$videoId')` (deep-links into the event feed scrolled to the video)

Foreground taps use a static callback: `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter

---

## Real-Time / Near-Real-Time Feed

### v1 Approach

- Push notification on new photo / clique join → user taps to open relevant screen
- Refresh on app resume via `WidgetsBindingObserver` (`didChangeAppLifecycleState`)
- Pull-to-refresh via `RefreshIndicator` on all list/detail screens
- 30-second polling via `Timer.periodic` while clique list/detail screens are active
- This pattern applies to: event feed, cliques list, clique detail (members)

This is sufficient. Most photo sharing happens in bursts during active events. Do not introduce SignalR, Web PubSub, or event streaming for v1.

---

## Performance Expectations

- Photo capture to visible in feed: < 5 seconds on good connectivity
- Video upload completion to transcoding job started (queue dispatch latency): < 10 seconds (KEDA polling 5s + ~5s container scheduling)
- **Video uploader's perceived "polishing" wait: ~zero** — instant preview lets the uploader play the original blob the moment commit returns
- Video transcoding for compatible source (~95% of phone uploads, fast path): **2-5 seconds FFmpeg work, ~15-25 seconds total wall-clock** including queue dispatch and container cold start
- Video transcoding for HDR / HEVC / >1080p source (slow path with HDR pipeline): **~21 seconds FFmpeg work, ~55-65 seconds total wall-clock** for an 11.5s 1080p HEVC HDR source on 2 vCPU
- Video transcoding for 5-minute 1080p source: target ≤ 5 minutes, hard ceiling ≤ 15 minutes (Container Apps Job timeout)
- Video processing-complete signal to visible "ready" state in feed (other members): < 5 seconds via Web PubSub when foregrounded
- Video playback start (tap to first frame): < 3 seconds on WiFi, < 6 seconds on LTE
- Feed scroll: 60fps, no jank (poster images only on feed cards, full video only loads on tap)
- Feed images stable across 30-second poll cycles — no flicker. Achieved via stable `cacheKey` on `CachedNetworkImage` (see Decision 11). `cacheKey: 'video_poster_${video.id}'` and `cacheKey: 'photo_thumb_${photo.id}'`.
- App cold start to usable: < 3 seconds
- Thumbnail / poster loads: < 500ms on 4G
- Never block the UI thread with image processing, video decoding, or network calls

**Container Apps Jobs cold start (~15-25s on Consumption profile)** is the biggest remaining bottleneck on the slow path. Migrating from Container Apps Jobs to a long-running Container Apps Service queue processor would eliminate it. Deferred to v1.5.

---

## Testing Expectations

### v1 Minimum
- Unit tests for business logic (duration calculations, membership checks, error mapping)
- Widget tests for critical flows (auth, photo upload, feed rendering)
- Manual testing on both iOS and Android devices
- Test on slow networks (throttle to 3G in dev tools)

### Not Required for v1
- Full integration test suite
- Automated E2E tests
- Load testing (do this before public launch, not during MVP)

---

## Observability

### Application Insights Telemetry Events

**Cliques, Events, Auth, Notifications:**
- `clique_created`, `clique_joined`, `clique_left`
- `event_created`, `event_expired`, `event_deleted`, `expired_events_deleted`
- `token_refresh_success`, `token_refresh_failed` (include layer that triggered it)
- `account_deleted`
- `notification_sent`, `notification_send_failed`

**Photos:**
- `photo_upload_started`, `photo_upload_completed`, `photo_upload_failed`
- `photo_saved_to_device`
- `expired_photos_deleted` (include count)
- `orphaned_uploads_cleaned` (include count)

**Videos (new in v1):**
- `video_upload_started` (with file_size_bytes, source_duration_seconds, source_container)
- `video_upload_block_failed` (with block_index, retry_count) — fires per block, not per video
- `video_upload_committed` (with total_block_count, total_time_seconds)
- `video_upload_failed` (with reason)
- `video_validation_rejected` (with reason: duration / container / codec / corrupt)
- `video_transcoding_queued`
- `video_transcoding_started` (Container Apps Job begins)
- `video_transcoding_completed` (with `durationSeconds`, `processingMode: 'transcode' | 'stream_copy'`, `fastPathFailureReason: <error or "none">`)
- `video_transcoding_failed` (with error_class, ffmpeg_exit_code)
- `video_preview_sas_failed` (instant-preview SAS generation failed in commit endpoint)
- `video_played` (with playback_mode: hls | mp4_fallback)
- `video_playback_stall` (with position_seconds, reason)
- `video_saved_to_device`
- `video_hls_manifest_cache_hit`, `video_hls_manifest_cache_miss` — track cache effectiveness
- `expired_video_hls_prefix_deleted` (with blob_count, total_bytes)
- `failed_video_processing_cleaned` (with count)
- `video_ready_push_sent` (with `recipientCount` — includes the uploader on the Web PubSub channel since 2026-04-08)
- `video_deleted` (uploader-initiated delete via the player AppBar PopupMenu)
- `video_commit_size_mismatch` (client/server byte-count divergence — client upload bug)
- `video_commit_block_list_failed` (Put Block List failure on commit)

**Useful App Insights queries:**

```kql
// Stream-copy fast path adoption rate (target ~95% on phone uploads)
customEvents
| where name == "video_transcoding_completed"
| summarize count() by tostring(customDimensions.processingMode)
```

```kql
// Fast-path failure fall-throughs (target empty)
customEvents
| where name == "video_transcoding_completed"
| where customDimensions.fastPathFailureReason != "none"
```

```kql
// Slow-path FFmpeg encoding time (target p50 < 25s for HDR HEVC 1080p)
customEvents
| where name == "video_transcoding_completed"
| extend dur = todouble(customDimensions.durationSeconds), mode = tostring(customDimensions.processingMode)
| where mode == "transcode"
| summarize percentiles(dur, 50, 95)
```

**Reactions (shared across media types):**
- `reaction_added`, `reaction_removed` (with media_type)

**DMs:**
- `dm_thread_created`, `dm_message_sent`, `dm_message_send_failed`
- `dm_push_sent`, `dm_thread_marked_read_only`

### Logging Rules
- Always log: correlation IDs, error codes, function execution duration
- Never log: auth tokens, storage credentials, user PII, raw photo/video bytes
- Container Apps Job logs flow to the same App Insights instance as the Function App via the `APPLICATIONINSIGHTS_CONNECTION_STRING` env var set on the job

---

## Networking (Dio Configuration)

Configure Dio with:
- Base URL pointing to the Front Door endpoint
- Auth interceptor that attaches the Entra access token to every request
- Error interceptor that maps HTTP status codes to typed failure classes
- Retry interceptor for transient failures (5xx, timeouts)

---

## Development Workflow

### Iteration Order
1. **Scaffold** the full project structure and navigation shell
2. **Auth flow** end-to-end (signup → login → token management → 5-layer refresh)
3. **Cliques** CRUD and invite flow with deep linking
4. **Events** creation and listing with duration presets
5. **Photo upload** pipeline (capture → compress → upload-url → blob upload → confirm)
6. **Event feed** with thumbnails and real-time-ish updates
7. **Reactions** and **save/download**
8. **Push notifications** (FCM token registration, new photo alerts, clique join alerts, expiration alerts)
9. **Auto-deletion** cleanup job and orphan cleanup
10. **Event DMs** (done — 1:1 chat per event, Web PubSub delivery)
11. **Video v1** — backend first:
    1. Schema migration (media_type + video columns on photos table)
    2. ACR provisioned, FFmpeg container image built + pushed
    3. Container Apps Environment + Job provisioned
    4. Storage Queue for transcoder dispatch
    5. Video upload-url endpoint (block SAS generation)
    6. Video upload-confirm endpoint (queue dispatch)
    7. Video processing-complete callback endpoint
    8. Video playback endpoint with manifest rewriting
    9. Timer Function updates for prefix-delete on video expiration
    10. Flutter client: video upload (block-based, resumable) + player + processing-state UI
    11. Push notification wiring for video_ready
12. **Polish** UI, transitions, error states, empty states

Do not perfect one screen before the next exists. Get the full loop working end-to-end first, then refine.

### Build Strategy
- Build features vertically: UI + state + API + backend for each feature before moving to the next
- Commit working increments, not half-finished features
- Test on a real device early and often — emulators hide performance issues

---

## Environment Configuration

### Environments
- `dev` — local development, points to dev Azure resources
- `prod` — production Azure resources

Two environments is sufficient for solo development. Add staging before public launch.

### Configuration Separation

Maintain separate config per environment:
- API base URL (Front Door endpoint)
- Entra External ID tenant ID and client ID
- Application Insights instrumentation key
- FCM project credentials

Use Flutter flavor/environment mechanisms. Do not hardcode environment-specific values.

---

## Infrastructure

### Azure Resource Naming

| Resource | Convention |
|----------|-----------|
| Resource Group | `rg-cliquepix-prod` |
| Function App | `func-cliquepix-fresh` |
| Storage Account | `stcliquepixprod` (no hyphens) |
| PostgreSQL | `pg-cliquepixdb` |
| App Insights | `appi-cliquepix-{env}` |
| Key Vault | `kv-cliquepix-{env}` |
| Front Door | `fd-cliquepix-prod` |
| APIM | `apim-cliquepix-002` |
| Web PubSub | `wps-cliquepix-prod` |
| Container Registry | `cracliquepix` (ACR names disallow hyphens) — **new for video v1** |
| Container Apps Environment | `cae-cliquepix-prod` — **new for video v1** |
| Container Apps Job (transcoder) | `caj-cliquepix-transcoder` — **new for video v1** |
| Storage Queue (transcoder dispatch) | `video-transcode-queue` inside `stcliquepixprod` — **new for video v1** |

### Managed Identity & RBAC Role Assignments

**Function App** system-assigned managed identity requires:

| Role | Scope | Purpose |
|------|-------|---------|
| `Storage Blob Data Contributor` | Storage account | Server-side blob read/write/delete (thumbnails, cleanup, validation, HLS manifest read for playback rewriting) |
| `Storage Blob Delegator` | Storage account | Generate User Delegation Keys for SAS tokens |
| `Storage Queue Data Contributor` | Storage account | Enqueue video transcoding jobs on `video-transcode-queue` |
| `Key Vault Secrets User` | Key Vault | Read connection strings and credentials |

**Container Apps Job (transcoder)** system-assigned managed identity requires:

| Role | Scope | Purpose |
|------|-------|---------|
| `Storage Blob Data Contributor` | Storage account | Read video originals, write HLS manifest/segments, MP4 fallback, poster |
| `Storage Queue Data Message Processor` | Storage account | Dequeue and process transcoding job messages |
| `AcrPull` | Container Registry | Pull the FFmpeg transcoder image |
| *(Callback auth to Function)* | — | Via managed identity token for the Function App's audience — Function validates the caller's managed identity token on `/api/internal/video-processing-complete` |

No storage account keys anywhere. `allowSharedKeyAccess: false` on the storage account. Use `DefaultAzureCredential` in all Azure SDK calls (Function App Node.js + Container Apps Job Python/Node). PostgreSQL connection string stored in Key Vault, referenced via Key Vault reference in Function App settings.

### Key Vault Contents

Store in Key Vault:
- PostgreSQL connection string
- FCM server key / service account credentials
- Web PubSub connection string (or use managed identity once WPS supports it fully)

Not stored (managed identity eliminates the need):
- Storage account keys (disabled entirely)
- Storage account connection strings
- ACR credentials (Container Apps Job uses AcrPull via managed identity)

### IaC

Bicep is preferred but must not delay the MVP. Manual deployment is acceptable for initial setup — document what was provisioned. The video v1 infrastructure additions (ACR, Container Apps Environment, Container Apps Job, Storage Queue) should be captured in Bicep during implementation.

---

## Communication Rules for Claude Code

- Explain architectural decisions briefly when they matter. Do not over-explain basics.
- Do not suggest alternative approaches unless asked. Pick the one defined here and implement it.
- Do not introduce dependencies not listed in this document without discussing the tradeoff first.
- When generating code, include only essential comments. No verbose explanations in code.
- If a request conflicts with this document, flag the conflict and ask for clarification.
- If a request is ambiguous, refer to the Core Loop. Does it serve the loop? If yes, proceed. If unclear, ask.

---

## What v1 Success Looks Like

A user can:
1. Sign up and log in with minimal friction
2. Create a Clique and invite friends via link, SMS, or QR code
3. Tap an invite link and land in the app at the right screen
4. Start an Event with a chosen duration (24h / 3 days / 7 days)
5. Take a photo or record a video, or pick either from their gallery
6. See the photo appear in the event feed within seconds
7. See the video upload reliably (even with connection drops), show a processing placeholder, then transition to playable within ~15-25s for compatible sources or ~55-65s for HDR HEVC sources
8. **Tap their own processing video card immediately and play the original via instant preview** while the transcoder runs in the background (uploader-only)
9. Play back a video cleanly via HLS with MP4 fallback
10. React to others' photos and videos
11. Save a photo to their device (video save deferred to v1.5 — see Decision 9 follow-ups)
12. Share a photo externally via the OS share sheet (video share deferred to v1.5)
13. **Delete their own video** via the PopupMenu in the video player AppBar (works even when the player fails to init on a broken blob)
14. Receive push notifications when new photos are added and when videos finish processing (uploader gets the Web PubSub signal but NOT the FCM push for their own video)
15. See backend error codes mapped to friendly messages on the upload screen (`VIDEO_LIMIT_REACHED`, `DURATION_EXCEEDED`, etc. — read from `e.response.data.error.code` on a `DioException`)
16. See photos and videos automatically disappear from the cloud when the event expires

If all sixteen of these work cleanly on both iOS and Android, v1 is done.

---

## Companion Documents

| Document | Purpose |
|----------|---------|
| `docs/PRD.md` | Product requirements, feature definitions, UX principles, branding |
| `docs/ARCHITECTURE.md` | Full technical architecture, data model, security, deployment strategy |
| `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Complete 5-layer token refresh implementation (code samples, debug tags, test procedures) |
| `docs/EVENT_DM_CHAT_ARCHITECTURE.md` | Event-centric 1:1 DM design: Web PubSub delivery, schema, auth rules |
| `docs/CliquePix_Video_Feature_Spec.md` | Generic video feature spec (handoff doc — requirements, acceptance criteria) |
| `docs/VIDEO_ARCHITECTURE_DECISIONS.md` | CliquePix-specific video architecture decisions (12 decisions, including post-launch additions): transcoder host, HLS SAS delivery, schema, player, upload UX, stream-copy fast path, instant preview, HDR pipeline, KEDA tuning, image cache keys |
| `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` | As-built runbook for the Azure infra (ACR, Container Apps Environment, Container Apps Job, Storage Queue, RBAC roles, KEDA scaler config). Source of truth until Bicep IaC catches up. |
| `docs/NOTIFICATION_SYSTEM.md` | Push notification architecture details (FCM transport, channel setup, payload routing) |
