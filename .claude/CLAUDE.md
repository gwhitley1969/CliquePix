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
- Authentication via Entra External ID (email + password, plus Google + Apple federation, minimal friction; existing pre-2026-05-06 OTP users preserved per Microsoft documented behavior)
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
- Save individual photo/video to device, unified multi-select batch download for photos and videos with progress (dynamic label: "Download N Photos" / "N Videos" / "N Items")
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
  - **Fast path (`remuxHlsAndMp4`):** stream-copy compatible sources (H.264 SDR ≤1080p mp4/mov AAC, **AND `rotation === 0`** — see Decision 16) directly to HLS + MP4 with `-c copy -f tee`. ~2-5 sec wall-clock. Covers most landscape phone uploads.
  - **Slow path (`transcodeHlsAndMp4`):** full re-encode for HDR / HEVC / >1080p / non-AAC / **rotated** sources. Includes `zscale + tonemap=hable` HDR→SDR pipeline (HDR sources only), `-pix_fmt yuv420p`, `-profile:v high -level 4.0`, `-colorspace bt709 -color_primaries bt709 -color_trc bt709`, `-metadata:s:v:0 rotate=0` (suppresses residual legacy rotation atom on the MP4 branch), and an orientation-agnostic scale filter `scale=min(1920\,iw):min(1920\,ih):force_original_aspect_ratio=decrease` (caps long edge at 1920 — the original `scale=-2:min(ih,1080)` would have crushed iPhone portrait videos to 608×1080 the moment they hit the slow path). preset=`veryfast`. ~21 sec for an 11s HDR HEVC source; ~10-15 sec for an iPhone portrait H.264 SDR clip.
  - **FFmpeg autorotate is the load-bearing default** that bakes source rotation into the output frames — DO NOT add `-noautorotate` without also adding an explicit `transpose` filter computed from the probed angle. The Dockerfile pin (`jrottenberg/ffmpeg:6-alpine@sha256:464...`) is locked specifically to limit the risk of an autorotate-default change in a future FFmpeg release. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 16 for the rotation handling design.
  - Both paths use the same single tee-muxer FFmpeg invocation (HLS + MP4 from one pass).
  - Runs in Container Apps Job with `jrottenberg/ffmpeg:6-alpine` base image. KEDA polling 5s, min-executions=1.
- **Local-first uploader playback:** uploader can play their video immediately from the device file — zero network, zero wait. A `LocalPendingVideo` item (tracked by `localPendingVideosProvider` per event) is created before any upload begins. The event feed merges local pending items with server items, deduplicating by `serverVideoId`. When `video_ready` arrives, the local item retires and the cloud active card takes over. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 13 and `docs/VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md`.
- **Instant preview (fallback):** commit endpoint returns a 15-min read SAS for the original blob in `preview_url`. Used as a secondary fallback when the local file has been cleaned up by the OS. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 9.
- Resumable video uploads using Azure Blob block uploads (4MB blocks, client-side block state persistence for resume-on-restart)
- Video playback: in-app player using `video_player` + `chewie` with **3-tier precedence**: (1) local file path via `VideoPlayerController.file()` — uploader's device file, zero network; (2) preview URL via `VideoPlayerController.networkUrl()` — fallback if local file cleaned up; (3) cloud HLS + MP4 fallback via `/playback` endpoint. HLS uses `formatHint: VideoFormat.hls` via `VideoPlayerController.networkUrl(Uri.file(...))`. **Note:** `VideoPlayerController.file()` does NOT support `formatHint` but this only matters for HLS manifests — local MP4/MOV files auto-detect correctly.
- **Video player AppBar PopupMenu:** Save to Device, Share, and Delete — mirroring `photo_detail_screen.dart:43-124`. Save uses `StorageService.saveVideoToGallery()` with the MP4 fallback URL. Share uses `downloadToTempFile(extension: 'mp4')` + `Share.shareXFiles`. Save/Share only shown when `_playbackInfo != null` (video is active, not in preview/local mode). Delete calls `videosRepositoryProvider.deleteVideo` and invalidates `eventVideosProvider(eventId)` so the card disappears immediately.
- Video processing-state UX: placeholder card in the event feed while transcoding, push notification + Web PubSub signal when ready
- Processing-state propagation: Web PubSub `video_ready` event (foreground, **including the uploader** so their instant-preview card upgrades) + FCM push (backgrounded, **excluding the uploader** to avoid redundant notification noise about their own upload)
- HLS delivery via User Delegation SAS: backend rewrites `.m3u8` manifests at request time with per-segment signed URLs (60s in-Function cache, 15-min SAS expiry per segment)
- Video assets auto-delete with the event: original master + HLS package (prefix-delete) + MP4 fallback + poster
- **Per-user video cap:** `PER_USER_VIDEO_LIMIT = 10` (originally 5; bumped 2026-04-08 — see Decision Q7 in `docs/VIDEO_ARCHITECTURE_DECISIONS.md`). Counts videos in `pending`/`processing`/`active`. Backend enforces at the upload-url endpoint with `VIDEO_LIMIT_REACHED` error code.
- **Backend error code propagation to client:** the Flutter `_friendlyError` in `video_upload_screen.dart` reads `e.response?.data['error']['code']` from a `DioException` and switches on the structured backend error code — NOT on `e.toString()` (which only contains the message field). Pattern: switch on the canonical code, fall through to `errorMap['message']` for unknown codes, then to network/socket checks, then to a generic fallback. Mirror this pattern wherever client UX maps backend error codes.

**Avatars (v1, migration 010 — shipped 2026-04-24)**
- Profile picture upload replacing initials-in-a-gradient-ring fallback on Profile hero, photo/video feed cards, clique member lists, DM thread + chat headers
- First-sign-in welcome prompt on Home screen — three choices (Yes / Maybe Later / No Thanks) with backend-persisted state (`avatar_prompt_dismissed`, `avatar_prompt_snoozed_until`) so the decision survives reinstall + honors across mobile/web devices
- Square crop via `image_cropper` (mobile) / `react-easy-crop` (web) — native UIs on both platforms
- 4 filter presets (Original / B&W / Warm / Cool) + 5 gradient frame presets (0 = auto-hash from name, 1..4 = explicit palette). Identical filter matrices and gradients across mobile + web
- Compression: 512×512 JPEG q85 (original), 128×128 JPEG q75 (sharp thumb generated synchronously at confirm time)
- Avatar view SAS: 1-hour expiry (longer than photos/videos because avatars render on every screen). Client-side cache key: `avatar_${userId}_v${avatar_updated_at.ms}` — URL churns hourly, cache key only churns on actual avatar change
- Confetti burst on first-ever upload (one-shot via `canvas-confetti` on web / `confetti` package on Flutter, gated on SharedPreferences/localStorage flag)
- `AuthNotifier.updateUserAvatar` is pure in-memory state swap — MUST NOT trigger token refresh (spurious calls would disturb the 5-layer Entra defense counters)
- Full pipeline details: Media Handling Pipeline → Avatar Pipeline below. Schema: `docs/ARCHITECTURE.md` §7 users table

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
- **Push notifications:** firebase_messaging (FCM transport only); `flutter_local_notifications` is also used for foreground heads-up display AND for the **weekly Friday 5 PM local reminder** (the only purely client-scheduled notification in v1 — see Notification Architecture below)
- **Device timezone:** flutter_timezone (^4.0.0) — reads the IANA name in `main.dart` so `tz.setLocalLocation` is correct for DST-aware `zonedSchedule` recurrence. Required by the Friday reminder; do not remove without replacing the IANA-detection path
- **Image caching:** cached_network_image
- **Image editor:** pro_image_editor (^5.1.4 — crop, draw, stickers, filters, text). **Callback rule:** v5.x calls `onCloseEditor` after `onImageEditingComplete` completes. Only pop in `onCloseEditor`, never in `onImageEditingComplete`, or you get a double-pop. **Photos only** — videos skip the editor in v1.
- **Video player:** `video_player` (official) + `chewie` (UI controls). HLS via ExoPlayer (Android only — see iOS note below). Versions pinned during implementation. **iOS bypasses HLS entirely on the cloud playback tier (since 2026-05-03):** `Platform.isIOS` branch in `_initializePlayer` skips `_initWithHls` and calls `_initWithMp4` directly. AVPlayer hangs indefinitely on a `Uri.file(<m3u8 path>)` HLS playlist whose segment lines are absolute `https://*.blob.core.windows.net/...` SAS URLs — `controller.initialize()` returns a `Future` that never resolves and never throws. v1 is single-rendition HLS so MP4 progressive download with `+faststart` is functionally equivalent. Local-first uploader (`VideoPlayerController.file()`) and instant-preview (`VideoPlayerController.networkUrl(<https URL>)`) tiers work on iOS unchanged. Revisit when adaptive bitrate ladders ship in v1.5 — would require a backend raw-m3u8 endpoint serving `Content-Type: application/vnd.apple.mpegurl` over HTTPS so iOS can play HLS without the file:// workaround. **All video player init paths are now wrapped in a `_initWithTimeout` helper (8s for local file, 15s for cloud/preview/HLS/MP4) that disposes the controller on failure** — defense-in-depth so no future iOS regression can produce the forever-spinner symptom again. See `app/lib/features/videos/presentation/video_player_screen.dart` and `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 15.
- **Video metadata probing (client-side validation):** `video_player` plus a small duration/dimension pre-check, or `video_compress` if deeper metadata is needed. Final choice locked during implementation.
- **Deep links:** app_links
- **QR code generation:** qr_flutter
- **MSAL authentication:** msal_auth (^3.3.0, v2 embedding, custom API scope `access_as_user`). **iOS broker MUST be `Broker.msAuthenticator` (NOT `safariBrowser`)** at all 3 PCA-creation sites (`auth_repository.dart`, `main.dart` background isolate, `background_token_service.dart` WorkManager isolate). Reason: msal_auth's iOS bridge sets `prefersEphemeralWebBrowserSession=true` unconditionally (`MsalAuthPlugin.swift:220`) but only honors it when `webviewType` falls into the `default:` case (ASWebAuthenticationSession on iOS 13+). `Broker.safariBrowser` overrides to `webviewType = .safariViewController`, which has a per-app **persistent** cookie jar — sign out then try to sign in as a different user gets trapped on CIAM's "Continue as <previous user>" prompt because the session cookie at `cliquepix.ciamlogin.com` survives `pca.signOut()`. `Broker.msAuthenticator` falls through to ASWebAuthenticationSession ephemeral; cookies are destroyed at session end. For B2C/CIAM, MSAL never brokers via the Authenticator app (B2C unsupported), so the enum name is misleading — the actual behavior is "ephemeral ASWebAuthenticationSession." Fixed 2026-05-04. Do NOT revert without re-introducing the account-switching bug.
- **URL launcher:** url_launcher (^6.2.5) — opens Privacy Policy and Terms of Service in platform-native in-app browser (`LaunchMode.inAppBrowserView` → SFSafariViewController on iOS, Custom Tabs on Android). Points to `https://clique-pix.com/docs/privacy` and `https://clique-pix.com/docs/terms` (the policy docs moved from root when the web client launched; legacy `/privacy.html` and `/terms.html` URLs 301-redirect to `/docs/*`).

Do not introduce dependencies not listed here without discussing the tradeoff first.

### Web Client

- **Framework:** React 18 + Vite 5 + TypeScript 5
- **Styling:** Tailwind CSS with CSS variables mapped to the Clique Pix design tokens (Electric Aqua / Deep Blue / Violet Accent palette matches mobile)
- **Primitives:** Radix UI (Dialog, Dropdown, Toast, Tabs)
- **Routing:** React Router v6 (`createBrowserRouter`)
- **State:** `@tanstack/react-query` for server state, Zustand for UI state
- **Auth:** `@azure/msal-browser` + `@azure/msal-react` (Entra External ID, SPA redirect flow, PKCE). Reuses the mobile app's Entra tenant, client ID (`7db01206-135b-4a34-a4d5-2622d1a888bf`), and custom API scope. MSAL.js uses hidden iframes for silent renewal, so the 12-hour CIAM refresh-token bug does NOT apply to web — no 5-layer defense needed.
- **Real-time:** `@azure/web-pubsub-client` — same Web PubSub hub the mobile app uses for DMs and video-ready events.
- **Media:** `browser-image-compression` + `heic2any` for photo uploads, `hls.js` for HLS playback (code-split), `@azure/storage-blob` for video block uploads (code-split).
- **Icons:** `lucide-react` (matches mobile's stated icon set).
- **Telemetry:** `@microsoft/applicationinsights-web` shares the same App Insights resource as mobile. Event prefix `web_*`.
- **Hosting:** Azure Static Web Apps (same SWA resource that previously hosted only `/privacy.html` + `/terms.html`). Web app at `clique-pix.com` root; static docs at `/docs/*`; deep-link files at `/.well-known/*` preserved byte-for-byte so Universal Links and App Links still work.
- **Domain separation:** web at `clique-pix.com`, API at `api.clique-pix.com` — different origins, so CORS is mandatory (configured at APIM in `apim_policy.xml`).
- **Hard rule:** no Web Push in v1. No background notifications in browsers. Users who want background alerts use the mobile app. Notifications list is in-app (polling + Web PubSub real-time while the tab is open).
- **Hard rule:** no blocking splash at launch. Optimistic-auth philosophy applies here too — sessionStorage cache + React Router redirect + background `/auth/verify` = no spinner blocking the login screen or the app shell.
- **Hard rule:** `setApiMsalInstance(msalInstance)` MUST be called from `main.tsx` AFTER `await msalInstance.initialize()` and BEFORE `ReactDOM.createRoot(...).render(...)`. The axios interceptor in `api/client.ts` needs the same initialized PCA that `<MsalProvider>` uses. A previous regression built a fallback PCA on the fly that was never initialized, causing `acquireTokenSilent` to throw silently and requests to ship unauthenticated — users saw empty Events/Cliques that looked like "no data" instead of "not authenticated." Fix was PR #4. `getPca()` now throws a loud dev error if the wiring is skipped.
- **Hard rule:** response shape conversion happens at the axios interceptor layer (`api/camelize.ts`). Every JSON response body is recursively converted `snake_case → camelCase`. TypeScript interfaces in `api/endpoints/*` reflect the **post-transform** shape. Request bodies stay `snake_case` because that's what the backend validates on. Paginated list endpoints (notifications, photos, videos, DM messages) wrap payloads in envelopes like `{ items: [...], next_cursor }` — endpoint modules must unwrap; don't make callers handle this.
- **Hard rule:** Cliques join endpoint is `POST /api/cliques/_/join` with underscore placeholder — the backend route requires a segment but the handler ignores it, resolving the clique via `invite_code` in the body. Matches mobile (`app/lib/features/cliques/data/cliques_api.dart:39`). `POST /api/cliques/join` returns 404.
- **Hard rule:** the landing page at `/` is public and does NOT auto-redirect authenticated users. It reads `useIsAuthenticated()` and swaps the nav CTA between "Sign in" and "My Events →". Authed users can still read the marketing page.
- **Operational gotcha:** the SWA Free tier caps staging environments at 3 concurrent. Every PR creates one. When the cap is hit, the next deploy fails with `maximum number of staging environments`. Cleanup is manual via `az rest DELETE` on the build resources — see `docs/WEB_CLIENT_ARCHITECTURE.md §13.1`. Automating this cleanup in the GH Actions workflow is a tracked follow-up.

Do not introduce npm dependencies not listed in `docs/WEB_CLIENT_ARCHITECTURE.md` §1 without discussing the tradeoff first.

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
| Identity (consumer) | Microsoft Entra External ID | User auth (email + password, Google, Apple) |
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
GET    /api/photos/{photoId}/reactions      # who-reacted list (Facebook-style sheet)
POST   /api/videos/{videoId}/reactions
DELETE /api/videos/{videoId}/reactions/{reactionId}
GET    /api/videos/{videoId}/reactions      # who-reacted list (Facebook-style sheet)

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

POST   /api/users/me/avatar/upload-url
POST   /api/users/me/avatar               # confirm upload; runs sharp thumb gen
DELETE /api/users/me/avatar               # removes both blobs + nulls DB columns
PATCH  /api/users/me/avatar/frame         # body: { frame_preset: 0..4 }
POST   /api/users/me/avatar-prompt        # body: { action: 'dismiss' | 'snooze' }
```

### Photo Upload Flow

**User Delegation SAS — RBAC-backed, no storage account keys.**

1. Client compresses image (see Media Handling Pipeline)
2. Client calls `POST /api/events/{eventId}/photos/upload-url`
3. Function validates Entra token and confirms user is a member of the event's clique
4. Function generates a photo ID and blob path (`photos/{cliqueId}/{eventId}/{photoId}/original.jpg`), creates a photo record with status `pending`
5. Function uses managed identity to request a **User Delegation Key**, generates a **write+create User Delegation SAS** scoped to that exact blob path, 5-minute expiry. Both permissions are required: `create` lets the client Put Blob at a path where no blob exists yet; `write` permits overwrite on retry of the same path. `write` alone is insufficient for first-time blob creation (see `backend/src/shared/services/sasService.ts`).
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
- Upload SAS permissions: photos use `write+create` (Put Blob requires both for first-time creation); videos use `write` only (Put Block on existing blob). In all cases the client cannot read, list, or delete.
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
- **SAS expiry recovery (implemented):** If the 15-minute SAS expires mid-playback (long session, paused for 20 minutes), `_onPlaybackError` listener detects the error → `_recoverFromSasExpiry()` saves current position → re-calls `/playback` for fresh manifest → reinitializes player at saved position. Only triggers for cloud HLS/MP4 (not local file or instant-preview). Falls back to error message on recovery failure.
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
    "message": "The requested clique does not exist.",
    "request_id": "abc-123-def"
  }
}
```

`request_id` is the Azure Functions `invocationId` — included in every error response for correlation with App Insights logs. Use consistent error codes. Never return raw exception messages or stack traces to the client.

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

## Age Gate (13+) — Claim-based backend enforcement

Clique Pix enforces a 13+ minimum using a claim-based backend check. **DOB is collected by the Entra External ID signup form once**, stored on the Entra user principal, and emitted as a `dateOfBirth` claim on every access token. Our backend (`authVerify` in `backend/src/functions/auth.ts`) reads the claim on first login, computes age server-side, and branches: ≥13 upserts the user with `age_verified_at = NOW()`; <13 returns HTTP 403 and best-effort deletes the Entra account via Microsoft Graph. Returning users are never re-prompted — Entra holds DOB, claim rides the token, backend sees `age_verified_at` is already set and fast-paths.

**Why not a Custom Authentication Extension?** Microsoft's own migration docs state plainly: *"Age gating isn't currently supported in Microsoft Entra External ID."* We tried the CAE-on-`OnAttributeCollectionSubmit` pattern (MAB's approach) and burned multiple days fighting opaque EasyAuth rejections, token `iss` disagreements with Microsoft's own documented format, and the generic "Something went wrong" page with no diagnostics. The claim-based path uses officially-supported Entra features and runs inside code we own, so failures are debuggable. See `docs/AGE_VERIFICATION_RUNBOOK.md` → "Deprecated" appendix for the CAE failure modes.

**The Clique Pix client has NO login-screen DOB picker.** The login screen is unchanged — just the "Get Started" button that triggers MSAL. DOB collection happens inside the Entra-hosted signup form. When the backend returns HTTP 403 `AGE_VERIFICATION_FAILED`, `app/lib/features/auth/presentation/auth_providers.dart:AuthNotifier.signIn` catches the structured `DioException`, reads `error.message` from the response body, calls `resetSession()` to clear the MSAL cache (so subsequent attempts don't re-use the now-invalid token), and emits `AuthError(serverMessage)` — which the login screen renders as a red banner reading *"You must be at least 13 years old to use Clique Pix."*

Backend pieces (CliquePix-controlled):
- `backend/src/functions/auth.ts` — `decideAgeGate(payload, now?)` (pure function, exported for tests), `extractDobFromClaims` (handles GUID-prefixed `extension_<b2cAppId>_dateOfBirth` key form via case-insensitive substring match), `parseAnyDob` (YYYY-MM-DD, MM/DD/YYYY, MMDDYYYY). The `authVerify` handler calls `decideAgeGate` between JWT validation and user upsert; blocks under-13 with HTTP 403 `AGE_VERIFICATION_FAILED`.
- `backend/src/shared/auth/entraGraphClient.ts` — thin Graph client with `deleteEntraUserByOid(oid)`. Uses `DefaultAzureCredential` for managed-identity token acquisition. Best-effort: failure logged as `age_gate_entra_delete_failed` but does not block the 403 response.
- `backend/src/shared/utils/ageUtils.ts` — shared `MIN_AGE = 13`, `parseDob`, `calculateAge`, `ageBucket`. 20 unit tests in `backend/src/__tests__/ageUtils.test.ts`; 16 additional tests for the auth.ts helpers in `backend/src/__tests__/auth.test.ts`.
- `backend/src/shared/db/migrations/008_user_age_verification.sql` — adds `users.age_verified_at TIMESTAMPTZ`. Null for grandfathered pre-age-gate users; upsert uses `COALESCE` so the original timestamp is never overwritten.

Entra portal pieces (manual, one-time — see `docs/AGE_VERIFICATION_RUNBOOK.md`):
- Custom user attribute `dateOfBirth` (string) — collected by the `SignUpSignIn` user flow as required.
- Clique Pix Enterprise App → Single sign-on → Attributes & Claims → add `dateOfBirth` claim (source: Directory schema extension from `b2c-extensions-app`).
- Clique Pix app manifest: `acceptMappedClaims: true`, `accessTokenAcceptedVersion: 2` (required for extension claims to appear in tokens).
- Function App `func-cliquepix-fresh` managed identity: `User.ReadWrite.All` application permission on Microsoft Graph, admin-consented (for the under-13 cleanup delete).

Privacy posture: Clique Pix's Postgres `users` table stores only `age_verified_at` (a timestamp), never DOB. Entra stores DOB on the user principal (same as email + displayName). Users can delete their Entra account to remove all traces. Privacy Policy §2.2 + §11 (`website/privacy.html`) describe this accurately.

Policy constant: `MIN_AGE = 13` in `backend/src/shared/utils/ageUtils.ts`. Terms §2 (`website/terms.html`) + Privacy Policy §11 declare the minimum. If policy ever changes, three files move together: `ageUtils.ts`, `privacy.html`, `terms.html`.

Telemetry: `authVerify` fires `age_gate_passed` (with coarse `ageBucket`), `age_gate_denied_under_13`, `age_gate_entra_delete_failed` — never logs raw DOB or precise age. `auth_verify_success` continues to fire for the normal login path.

History note: two prior attempts were reverted. (1) A client-side login-screen DatePicker + `auth.ts` validation, reverted because email-bound client caching leaked sign-in to unverified users in sign-out → different-new-user scenarios. (2) An Entra Custom Authentication Extension on `OnAttributeCollectionSubmit`, reverted on 2026-04-18 after multi-day debugging confirmed the approach is unsupported and inherently opaque. The current claim-based approach is the third iteration.

---

## Entra External ID — Known Bug & Required Workaround

### Optimistic authentication on cold start (user-facing contract)

Clique Pix does not block its UI on a network call at launch. Ever. `main.dart` reads the access token + cached `UserModel` from secure storage before `runApp` and seeds `AuthNotifier`'s state. Returning users with a valid cached session see Events as the first frame. First-time users see LoginScreen with a fully enabled "Get Started" button as the first frame. Background verification runs concurrently via `_verifyInBackground` (8s timeout) — on session-expired failures it emits `AuthReloginRequired`, which the router surfaces as the `WelcomeBackDialog`.

**Hard rule:** no splash screen, no "checking auth" state blocking the UI, no path through the auth code that can leave the user staring at a loading indicator for more than 15 seconds. The escape-hatch UI on LoginScreen ("Having trouble? Sign in with a different account") appears after 15 seconds of sign-in spinner and calls `AuthNotifier.resetAndSignIn()` which clears the MSAL cache and restarts interactive auth.

Timeouts across the auth stack:
- `silentSignIn` during background verification — 8s
- Post-browser `verifyAndGetUser` during interactive sign-in — 10s
- `backgroundTokenService.register()` best-effort — 5s + catchError
- `AppLifecycleService._refreshCallback` on resume — 8s
- `AuthInterceptor` 401 refresh — 8s
- Interactive browser auth (`pca.acquireToken`) — untimed (user types password)

The `pendingRefreshFlagKey` in `AppLifecycleService` is cleared **before** awaiting the refresh (not after), so a hung refresh cannot poison every future resume.

### The Problem

Entra External ID (CIAM) tenants have a **hardcoded 12-hour inactivity timeout** on refresh tokens. This is a confirmed Microsoft bug — standard Entra ID tenants get 90-day lifetimes. No portal-based configuration options exist.

Error signature: `AADSTS700082: The refresh token has expired due to inactivity... inactive for 12:00:00`

### Required: 5-Layer Token Refresh Defense (silent-push edition, 2026-04-19)

Microsoft's documented mitigation for this exact scenario (Azure Communication Services chat → "Implement registration renewal → Solution 2: Remote Notification") is **silent push + background refresh**. That is the current Layer 2. The previous notification-based AlarmManager Layer 2 was deleted because `flutter_local_notifications.zonedSchedule` only schedules a notification to display; it does not execute code, and the silent `Importance.min` notifications the user never tapped never refreshed anything.

| Layer | Mechanism | Trigger | Platforms | Purpose |
|-------|-----------|---------|-----------|---------|
| 1 | Battery-optimization exemption | First home-screen frame after login | Android | Allows OS FCM delivery + WorkManager on Samsung/Xiaomi/Huawei |
| 2 | **Server-triggered silent FCM push** | Backend timer every 15 min, users inactive 9-11h | both | Wakes the app, runs `acquireTokenSilent` in an isolate. Falls back to `pending_refresh_on_next_resume` flag if iOS isolate can't run MSAL |
| 3 | Foreground refresh on app resume | `AppLifecycleState.resumed` if token ≥ 6h stale or pending flag set | both | Primary, most-reliable defense |
| 4 | WorkManager periodic task | Every ~8h, network connected | Android | Best-effort backup |
| 5 | Graceful re-login via Welcome Back | Silent refresh fails (AADSTS700082 / AADSTS500210 / no cached account) | both | One-tap re-auth with `loginHint` pre-fill |

### Layer Details

**Layer 1 — Battery Optimization Exemption (Android)**
- `Permission.ignoreBatteryOptimizations.request()` at runtime — the manifest-only declaration is not sufficient on API 23+
- Dialog shown once on the first frame of the home screen after login; `BatteryOptimizationService.requestExemptionIfNeeded(context)` self-gates on the `battery_dialog_shown` SharedPreferences key
- Without this, Samsung/Xiaomi/Huawei kill background processes and Layer 4 becomes unreliable

**Layer 2 — Server-triggered silent FCM push**
- Backend timer `refreshTokenPushTimer` (CRON `0 7,22,37,52 * * * *`) selects users with `last_activity_at BETWEEN NOW() - INTERVAL '11 hours' AND NOW() - INTERVAL '9 hours'` AND `last_refresh_push_sent_at < NOW() - INTERVAL '6 hours'`
- `sendSilentToMultipleTokens(tokens, { type: 'token_refresh', userId })` → FCM v1 with NO `notification` block; `apns-push-type: background`, `apns-priority: 5`, `apns-topic: com.cliquepix.app`, `apns.payload.aps.content-available: 1`, `android.priority: high`
- Client `_firebaseMessagingBackgroundHandler` (main.dart) branches on `message.data['type'] == 'token_refresh'`, creates a fresh `SingleAccountPca` from `MsalConstants`, calls `acquireTokenSilent`, saves the access token
- On iOS, if `msal_auth` isn't usable in the background isolate, fall back to writing `pendingRefreshFlagKey` into SharedPreferences; Layer 3 picks up the flag on next foreground
- Authoritative doc: `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`

**Layer 3 — Foreground Refresh (both platforms, primary)**
- `AppLifecycleService` implements `WidgetsBindingObserver`; on `AppLifecycleState.resumed` it checks `TokenStorageService.isTokenStale()` (≥ 6h since `lastRefreshTime`) AND the `pendingRefreshFlagKey` fallback flag
- If either is true, calls `AuthRepository.refreshToken()` (MSAL silent acquisition)
- On success, calls optional `_onRefreshSuccess` hook
- On failure, invokes `_reloginCallback` → Layer 5
- Wired in `auth_providers.dart` — `AuthNotifier` starts the observer on `AuthAuthenticated` and stops it on sign-out / unauth

**Layer 4 — WorkManager (Android backup)**
- `Workmanager().registerPeriodicTask` every 8h (`AppConstants.workManagerIntervalHours`), `NetworkType.connected`
- `callbackDispatcher` now runs the full MSAL silent refresh in the WorkManager isolate: creates `SingleAccountPca` from `MsalConstants`, calls `acquireTokenSilent`, writes to `TokenStorageService`
- Isolate-safe because the MSAL cache (Android EncryptedSharedPreferences / iOS Keychain) is process-wide
- Telemetry is queued into a SharedPreferences ring buffer the main isolate drains on next foreground

**Layer 5 — Graceful Re-Login UX**
- `AuthState` adds `AuthReloginRequired(email?, displayName?)`
- `AuthNotifier.checkAuthStatus` detects `AADSTS700082` / `AADSTS500210` / `no account in the cache` on cold start and, if `lastKnownUser.email` is set, emits `AuthReloginRequired` instead of `AuthUnauthenticated`
- `AuthNotifier._triggerWelcomeBack` does the same on Layer-3 refresh failure during an active session
- **`AuthInterceptor` ALSO triggers Layer 5 (since 2026-05-03):** when an in-flight 401's refresh fails with a session-expired pattern (`AADSTS700082` / `AADSTS500210` / `no_account_found`), the interceptor calls `AuthNotifier.triggerWelcomeBackOnSessionExpiry(reason: errorCode)` fire-and-forget. Without this hook, the 401 propagated as AsyncError to whichever screen made the call — and `home_screen.dart` rendered the raw `DioException` toString verbatim before the parallel `_verifyInBackground` could transition state. The new path races the AsyncError to the screen and wins. Telemetry split via `welcome_back_shown { source: 'interceptor' | 'lifecycle' }` measures effectiveness. **Three sites must stay in sync** on the session-expired regex: `AuthInterceptor._isSessionExpired`, `AuthRepository._extractAadstsCode`, `AuthNotifier._handleSilentSignInFailure`. Comment on each notes the others
- `LoginScreen` listens on `authStateProvider` and calls `WelcomeBackDialog.show` with `loginHint = email`
- **Never render `error.toString()` for AsyncError on bootstrap-path screens.** Use `core/utils/api_error_messages.dart::friendlyApiErrorMessage(err, resourceLabel: ...)` which explicitly never returns raw `DioException` toString. The home screen (`home_screen.dart:289-310`) is the canonical example — narrow-scope SnackBars on local actions (delete photo, share video) are fine with `'Failed to X: $e'` messaging since users only see them after explicit interaction

### Known unknowns and honest limits

- **APNs throttles background pushes.** Silent-push deliverability will be < 100%. The `refresh_push_timer_ran.sent` vs. `silent_push_received` ratio in App Insights is the ground truth.
- **Force-killed iOS apps don't receive silent pushes.** iOS platform policy. Layer 5 is the only recourse.
- **iOS Background App Refresh disabled.** Layer 2 is dead for that user; Layer 5 still works.
- **`msal_auth` in iOS background isolate.** Plugin-channel registration may fail. The fallback-flag path (Layer 2 → Layer 3) keeps us correct even then.

### Android Permissions

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

`SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` remain declared but are no longer on the critical path (the notification-based Layer 2 that used them has been deleted).

### iOS Info.plist

`UIBackgroundModes` must contain `remote-notification` for silent pushes to wake the app. Already set.

**Do NOT declare `BGTaskSchedulerPermittedIdentifiers` in `app/ios/Runner/Info.plist`.** Layer 4 is Android-only — there is no iOS-native `BGTaskScheduler` path in this codebase. iOS 13+ requires every identifier in that array to have a corresponding `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` call in `AppDelegate.swift`'s `application(_:didFinishLaunchingWithOptions:)`. A declaration without a registered handler causes `NSInternalInconsistencyException: 'No launch handler registered for task with identifier <ID>'` and SIGABRT — typically the moment the FlutterViewController re-attaches after `SFSafariViewController` dismisses, producing the symptom "app vanishes after MSAL/Safari sign-in." A `com.cliquepix.tokenRefresh` declaration was removed 2026-05-01; the constant of that name in `app/lib/features/auth/domain/background_token_service.dart:18` is the WorkManager (Android) task identifier and unrelated to iOS BGTaskScheduler.

### Token Storage

- Auth tokens: `flutter_secure_storage` only — never `shared_preferences`
- `lastRefreshTime`: written atomically in `TokenStorageService.saveTokens`; staleness threshold is `AppConstants.tokenStaleThresholdHours` (6h)
- `lastKnownUser`: stored on `verifyAndGetUser` success, read by Layer 5
- `pendingRefreshFlagKey` (SharedPreferences, not secure): bridge between Layer 2 isolate and Layer 3 main isolate
- Clear all on logout; cancel WorkManager task

### Key Timing

- Microsoft inactivity timeout: **12h** (hardcoded)
- Silent-push window: user inactive **9-11h**
- Layer 3 stale threshold: **6h**
- Layer 4 WorkManager interval: **8h**
- Silent-push dedup: **6h** per user

### Backend — tables touched

| Column | Table | Purpose |
|--------|-------|---------|
| `last_activity_at` | users | Updated fire-and-forget by `authMiddleware`, capped 1/min/user; feeds Layer-2 timer |
| `last_refresh_push_sent_at` | users | Updated by `refreshTokenPushTimer`; enforces 6h dedup |

Both added in migration `009_user_activity_tracking.sql`. Partial index on `last_activity_at WHERE last_activity_at IS NOT NULL`.

### Telemetry + diagnostics

- Events flow through `telemetry_service.dart` (client) → `POST /api/telemetry/auth` → `trackEvent` → App Insights
- Endpoint accepts JWTs whose signature is valid even if `exp` has passed — this endpoint exists specifically to hear from clients with expiring/expired tokens. `authMiddleware.verifyJwtAllowExpired` powers it
- Events: `battery_exempt_prompted/_granted`, `silent_push_received/_refresh_success/_refresh_failed/_fallback_flag_set`, `foreground_stale_check/_refresh_success/_refresh_failed`, `wm_task_fired/_refresh_success/_refresh_failed`, `welcome_back_shown/_continue/_switch_account`, `cold_start_relogin_required`, `refresh_push_timer_ran`
- Tap the version number 7 times in the Profile screen to unlock Token Diagnostics — shows last refresh time, age, pending-flag state, battery-exempt status, and the 50-event ring buffer

### Reference

Full implementation details, architecture diagrams, and Kusto queries: `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

---

## Media Handling Pipeline

Media uploads are the most performance-critical path in Clique Pix. Photos and videos have radically different shapes — photos can be compressed cheaply client-side to 500KB–1.5MB, while videos are 50–150MB even after sensible encoding and must be transcoded server-side. Avatars are a third shape — small, square, per-user fixed paths, and the only media type where the backend runs synchronous thumbnail generation at confirm time.

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

### Avatar Pipeline (added 2026-04-24, migration 010)

User headshots that replace the initials-in-a-gradient-ring fallback everywhere a user is surfaced (Profile hero, photo/video feed cards, clique member lists, DM threads + chat headers). Single blob container (`photos`, name historical) with per-user fixed paths under the `avatars/` virtual prefix — each new upload supersedes the prior one, no accumulation, no orphan tracking.

**Blob paths (fixed per user):**
```
avatars/{userId}/original.jpg     # 512×512 JPEG q85
avatars/{userId}/thumb.jpg        # 128×128 JPEG q75 (sharp, generated at confirm time)
```

**Client pipeline (both Flutter and web):**
1. Pick source (camera or gallery / file input)
2. Square crop via native cropper (`image_cropper` TOCropViewController/uCrop on mobile; `react-easy-crop` on web)
3. Optional filter — Original / B&W / Warm / Cool. Baked via `Canvas` + `ColorFilter.matrix` (Flutter) or `getImageData` + matrix loop (web). Identical matrices across platforms
4. Compress to 512px JPEG quality 85 (`flutter_image_compress` / `browser-image-compression`)
5. `POST /api/users/me/avatar/upload-url` → 5-min User Delegation SAS (write+create) → direct PUT to blob
6. `POST /api/users/me/avatar` → backend verifies blob, size ≤ 3MB, content-type JPEG/PNG; runs `sharp` inline to produce 128px thumb; stamps `avatar_updated_at = NOW()`; returns enriched `User`

**Backend propagation rules:**
- 1-hour view SAS via `generateViewSas(path, 3600)` (longer than photos' 5-min / videos' 15-min — avatars render on every screen; shorter expiry would thrash `cached_network_image`)
- **Cache key stability:** clients must set `cacheKey: 'avatar_${userId}_v${avatar_updated_at.ms}'` on `CachedNetworkImageProvider` (Flutter) / append as `?_v=` query param (web). URL churns every hour; cache key only churns when the user actually changes their avatar
- Every response that carries user denormalization (14 handlers: auth, photos, videos, events, cliques, dm) runs `enrichUserAvatar` from `backend/src/shared/services/avatarEnricher.ts` — single source of truth for SAS signing
- `buildAuthUserResponse` in the same helper is the canonical shape emitted by `authVerify` / `getMe` / all avatar-mutation endpoints. Single shape → one Flutter `UserModel.fromJson` deserializer

**First-sign-in welcome prompt (migration 010 added the state):**
Backend computes `should_prompt_for_avatar` on every auth response as `avatar_blob_path IS NULL AND NOT avatar_prompt_dismissed AND (avatar_prompt_snoozed_until IS NULL OR avatar_prompt_snoozed_until < NOW())`. Flutter triggers `AvatarWelcomePrompt` on `HomeScreen.initState` once per session when true; web mounts `AvatarWelcomePromptGate` in `AppLayout`. Three actions:
- **Yes** — opens the same picker/editor pipeline used from Profile. Upload success implicitly clears the flag via `avatar_blob_path IS NOT NULL`
- **Maybe Later** — `POST /api/users/me/avatar-prompt {action: 'snooze'}` → sets `avatar_prompt_snoozed_until = NOW() + 7 days`
- **No Thanks** — `POST /api/users/me/avatar-prompt {action: 'dismiss'}` → sets `avatar_prompt_dismissed = TRUE`, never re-prompts
- Back-button / tap-outside behaves like "Maybe Later" (safer default than permanent dismiss from accidental fat-finger)

**Frame presets (0..4):**
- `0` = auto-gradient from `displayName.hashCode` — the historical default that still ships for users who never touch the preset picker
- `1..4` = explicit palette indices. Palette matches mobile `AvatarWidget._palette` and web `Avatar.palettes` 1:1 so the same user renders the same gradient on every platform
- Updated via `PATCH /api/users/me/avatar/frame` — takes effect on the initials-fallback ring too, not just the uploaded-photo ring

**AuthNotifier rule:** client-side `AuthNotifier.updateUserAvatar(UserModel)` is a pure in-memory state swap. It MUST NOT trigger a token refresh — spurious refresh calls would disturb the 5-layer Entra defense's counters. The backend's confirm response already returns a fresh enriched user; just drop it into `AuthAuthenticated(user)`.

**Rate limiting:** removed entirely from APIM after FIVE consecutive user-blocking 429 incidents (4 on 2026-04-27, 1 on 2026-04-29). The 2026-04-29 incident reproduced because the prior cleanup only addressed the **API**-scope policy — APIM has FOUR policy scopes (Global, Product, API, Operation) and a rate-limit at any one of them produces the same 429 body. The actual culprit on 2026-04-29 was APIM's **default `starter` Product policy** containing `<rate-limit calls="5" renewal-period="60" />` plus `<quota calls="100" renewal-period="604800" />` — auto-created when the service was first provisioned, never touched, never inspected. New users auto-subscribe to `starter` and got slammed at 5/min on first sign-in. Fix: PUT a `<base />`-only policy at the starter product scope. **When diagnosing any 429, audit ALL FOUR APIM policy scopes via the script in `docs/BETA_OPERATIONS_RUNBOOK.md` §2 — not just the API scope.** Abuse protection lives at the application layer: JWT auth, event-membership checks, User Delegation SAS expiry (5 min photo / 30 min video block), orphan cleanup timer. The Azure Monitor alert `apim-429-detected` fires within 5 min of any APIM 429. Client-side `silentRetryOn429` (`app/lib/core/utils/upload_url_silent_retry.dart`) is a defense-in-depth safety net that absorbs a single 429 per 5-min window per device — it is wired into the photo and video upload-URL calls so a future regression doesn't immediately surface to users. **Do not re-add `<rate-limit-by-key>` OR `<rate-limit>` OR `<quota>` at ANY APIM scope** until APIM is migrated off Developer tier (Standard v2 has a distributed cache and an SLA). See `apim_policy.xml` in-file comment for the full 5-incident history.

**Account deletion:** `deleteMe` in `auth.ts` deletes both avatar blobs before the cascade row delete. Idempotent (`deleteIfExists`), so missing blobs don't block the flow.

**Out of scope (for v1):** animated/video avatars, Gravatar/social imports, multiple avatars per user, per-clique avatar overrides, reactions on avatars, AI-generated avatars.

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
- On `DELETE /api/photos/{id}` and `DELETE /api/videos/{id}`: caller must be the uploader OR the event organizer (`events.created_by_user_id`). Use the shared `canDeleteMedia` helper in `backend/src/shared/utils/permissions.ts`; uploader takes precedence; record `deleterRole` ∈ `'uploader' | 'organizer'` on the `photo_deleted` / `video_deleted` telemetry event alongside `uploaderId` and `eventOrganizerId`. Both handlers JOIN `events` in the SELECT for a single round-trip.

### Blob Storage Access — RBAC + User Delegation SAS:
- **No storage account keys in application code.** All CliquePix blob/queue access uses `DefaultAzureCredential` (managed identity). No account-key-based SAS tokens anywhere.
- `allowSharedKeyAccess` is `true` on the storage account — required because the Azure Functions runtime (`AzureWebJobsStorage`) uses shared keys internally for timer triggers, leases, and deployment. Migrate to identity-based `AzureWebJobsStorage__accountName` in v1.5 to fully disable.
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
| **Event created by clique member** | `new_event` | All clique members **except creator** (foreground real-time refresh of `allEventsListProvider`) | All clique members **except creator** | `{ type: 'new_event', event_id, clique_id, event_name, creator_name, clique_name }` |
| **Weekly Friday 5 PM reminder** (client-scheduled) | `friday_reminder` (local) | — | **Self only** (local notification — no FCM, no Web PubSub) | `{ type: 'friday_reminder' }` |

**No notifications sent** for member removals, voluntary departures, or video upload initiation (the feed placeholder card is enough signal to the uploader; other members are notified when the video is ready to play, not when it starts transcoding).

**Client-scheduled local notifications via `flutter_local_notifications.zonedSchedule` are permitted ONLY for displaying static recurring reminders, never for executing code.** The Friday 5 PM reminder is the sole such notification in v1. The previous Layer-2 token-refresh `zonedSchedule` was deleted because that primitive does not run code at fire time — it only displays. For *displaying* a static nudge, it is the correct primitive. See `app/lib/services/friday_reminder_service.dart` and `docs/NOTIFICATION_SYSTEM.md` "Weekly Friday Reminder" subsection.

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
- `cliquepix_default` — HIGH importance heads-up banners. All FCM-driven pushes (photos, videos, DMs, member joins, event lifecycle) flow through this channel. Referenced in AndroidManifest.
- `cliquepix_reminders` — DEFAULT importance. Only the weekly Friday reminder uses this channel. Separated so users can mute reminders via OS Settings without muting photo/video pushes.
- Android 13+ permission requested once via `requestNotificationsPermission()` covers both channels.

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

### v1 Approach (multi-layer)

- **Stale-while-revalidate cache for events + cliques** (since 2026-05-03) — `app/lib/core/cache/list_cache_service.dart` persists the last `listAllEvents()` + `listCliques()` responses to `SharedPreferences` under versioned, user-scoped keys (`events_cache_v1_${userId}`, `cliques_cache_v1_${userId}`). `main()` reads both with a 250 ms timeout AFTER the optimistic-auth bootstrap, overrides `eventsBootstrapProvider` + `cliquesBootstrapProvider` in `ProviderScope`. The `AllEventsNotifier` / `CliquesListNotifier` `build()` methods return the cached list synchronously, then `Future.microtask(_refreshSilently)`. **Hard rule: a refresh failure must NOT overwrite cached `AsyncData` with `AsyncError`** — the silent-refresh path captures the error to `eventsRefreshErrorProvider` / `cliquesRefreshErrorProvider` (a `StateProvider<Object?>`) and `return`s without touching `state`. Cache writes are best-effort and isolated in their own try/catch so a write failure can't promote to a refresh error. `home_screen.dart` no longer renders a full-screen `CircularProgressIndicator`; it renders the cached list immediately with an inline "Refreshing…" pill (driven by `AsyncValue.isReloading`) and a "Couldn't refresh — tap to retry" pill (driven by the error provider). The 3-card shimmer (`app/lib/widgets/list_skeleton.dart`) only appears on true first-launch — no cache and no fresh data yet. Caches are cleared in `auth_repository.dart` `signOut` / `deleteAccount` / `resetSession` via `ListCacheService().clearAll()`.
- **Deferred non-critical `main()` init** (since 2026-05-03) — `Workmanager().initialize`, `flutter_local_notifications.initialize` + 2× `createNotificationChannel` + `requestNotificationsPermission`, `tz.initializeTimeZones` + `FlutterTimezone.getLocalTimezone`, and the `FirebaseMessaging.onMessage.listen` registration all moved out of `main()` and into `performDeferredInit()` (in `main.dart`), invoked from `_CliquePixState.initState` via `WidgetsBinding.instance.addPostFrameCallback`. Idempotent via `_deferredInitDone` flag. Shaves 5–10 s off cold-start first paint. **Hard rule: `Firebase.initializeApp()` and `FirebaseMessaging.onBackgroundMessage(...)` MUST stay before `runApp()`** — the background isolate handler is registered there, and `firebase_messaging` will assert if Firebase isn't initialized. Push tokens aren't registered until post-`AuthAuthenticated` (which is also post-frame), so the deferred channel-creation can't race a foreground push.
- **Always-on Web PubSub** (since 2026-04-30) — `DmRealtimeService` is connected on `AuthAuthenticated` from `AuthNotifier._startLifecycle` (not per-DM-screen as it was originally). Disconnects on `_stopLifecycle`. Reconnects on `AppLifecycleState.resumed` if dropped. Delivers DM messages, `video_ready`, and `new_event` to whichever screen the user is currently on. Sub-second latency when the connection is alive.
- **FCM push** as the always-arrives fallback for backgrounded / terminated devices and for foreground users when the WebSocket is dropped. Same payload shape as Web PubSub data envelope so both paths trigger identical client behavior.
- **Refresh on app resume** via `WidgetsBindingObserver` (`didChangeAppLifecycleState`) — invalidates the events / cliques providers so the next read fetches fresh.
- **Pull-to-refresh** via `RefreshIndicator` on all list/detail screens.
- **30-second polling** via `Timer.periodic` (lifecycle-aware via `LifecycleAwarePollerMixin`) on `event_feed_screen`, `cliques_list_screen`, `clique_detail_screen`. Defense-in-depth — the always-on Web PubSub is the primary signal, polling catches anything missed.

`HomeScreen` (the dashboard with `allEventsListProvider`) does NOT poll. It relies on the Web PubSub `new_event` real-time path + FCM fallback + app-resume refresh.

**Web PubSub event types currently dispatched** in `DmRealtimeService` `_connectInternal` (per `app/lib/features/dm/domain/dm_realtime_service.dart`):
- `dm_message_created` — emits to `onMessage` stream (consumed by `DmChatScreen`)
- `video_ready` — emits to `onVideoReady` stream (consumed by `EventFeedScreen` + the always-on `RealtimeProviderInvalidator` since 2026-04-30)
- `new_event` — emits to `onNewEvent` stream (consumed by `RealtimeProviderInvalidator`, which invalidates `allEventsListProvider`, `eventsListProvider(cliqueId)`, `notificationsListProvider`)

Add new types by extending the type switch in `_connectInternal` and adding a corresponding `Stream<...>` getter, then subscribe wherever invalidation is needed.

---

## Performance Expectations

- Photo capture to visible in feed: < 5 seconds on good connectivity
- Video upload completion to transcoding job started (queue dispatch latency): < 10 seconds (KEDA polling 5s + ~5s container scheduling)
- **Video uploader's perceived wait: zero** — local-first playback lets the uploader play from their device file the moment they tap "Upload", before any network work begins. Instant preview (SAS to original blob) is a fallback if the local file is cleaned up
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

**Container Apps Jobs cold start (~15-25s on Consumption profile)** is the biggest remaining bottleneck on the slow path. Migrating from Container Apps Jobs to a long-running Container Apps Service queue processor would eliminate it — estimated ~$52/month at `minReplicas=1` (2 vCPU / 4 GiB, idle rate 24/7) vs ~$3-11/month current Jobs cost. Full cost analysis in `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 12 appendix. Deferred to v1.5. With local-first uploader playback (Decision 13), the cold start only affects how fast *other clique members* see the processed version — the uploader plays instantly from their device.

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
| APIM | `apim-cliquepix-003` (Basic v2, since 2026-05-05 — migrated from `apim-cliquepix-002` Developer tier) |
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

No storage account keys in application code. All CliquePix SDK calls use `DefaultAzureCredential` (Function App Node.js + Container Apps Job). `allowSharedKeyAccess` remains `true` on the storage account because the Azure Functions runtime (`AzureWebJobsStorage`) requires shared keys — migrate to identity-based connection in v1.5. PostgreSQL connection string stored in Key Vault, referenced via Key Vault reference in Function App settings.

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
8. **Tap their own video card immediately and play from the local device file** — zero wait, zero network. The local pending card appears in the feed the moment the user taps "Upload", before any Azure communication begins
9. Play back a video cleanly via HLS with MP4 fallback
10. React to others' photos and videos
11. Save a photo or video to their device — individually via the detail/player screen, or in bulk via multi-select download (photos and videos together, with progress)
12. Share a photo or video externally via the OS share sheet
13. **Delete their own photo or video** via the 3-dot menu on the feed card (visible to the uploader only, on all three video states) or the PopupMenu on the photo detail / video player AppBar (works even when the video player fails to init on a broken blob). Shared `confirmDestructive` helper backs all 7 destructive-confirm dialogs in the app with identical dark-theme styling.
14. Receive push notifications when new photos are added and when videos finish processing (uploader gets the Web PubSub signal but NOT the FCM push for their own video)
15. See backend error codes mapped to friendly messages on the upload screen (`VIDEO_LIMIT_REACHED`, `DURATION_EXCEEDED`, etc. — read from `e.response.data.error.code` on a `DioException`)
16. See photos and videos automatically disappear from the cloud when the event expires
17. **Upload a profile picture** (headshot) that replaces their initials everywhere — Profile hero, their own photo/video feed cards, DM threads. Tap the gradient ring → bottom sheet → crop → filter → frame → Save. Other clique members see the uploader's headshot on their cards on the next feed poll
18. **Get a branded welcome prompt on first sign-in** asking if they want to add a photo now, with Yes / Maybe Later (7-day snooze) / No Thanks (never re-prompt) options. Choice persists server-side so it's honored across reinstall + cross-device

If all eighteen of these work cleanly on both iOS and Android, v1 is done. (Local-first uploader playback replaces the preview_url-based instant preview as the primary uploader UX — see `docs/VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md`.)

---

## Companion Documents

| Document | Purpose |
|----------|---------|
| `docs/PRD.md` | Product requirements, feature definitions, UX principles, branding |
| `docs/ARCHITECTURE.md` | Full technical architecture, data model, security, deployment strategy |
| `docs/AUTHENTICATION.md` | Single-source orientation doc for auth — providers, end-to-end flow, iOS/Android/web specifics, App Store reviewer demo account, configuration reference, migration history |
| `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Complete 5-layer token refresh implementation (code samples, debug tags, test procedures) |
| `docs/EVENT_DM_CHAT_ARCHITECTURE.md` | Event-centric 1:1 DM design: Web PubSub delivery, schema, auth rules |
| `docs/CliquePix_Video_Feature_Spec.md` | Generic video feature spec (handoff doc — requirements, acceptance criteria) |
| `docs/VIDEO_ARCHITECTURE_DECISIONS.md` | CliquePix-specific video architecture decisions (17 decisions, 0-16): transcoder host, HLS SAS delivery, schema, player, upload UX, stream-copy fast path, instant preview, HDR pipeline, KEDA tuning, image cache keys, local-first uploader playback, video save/share, iOS HLS bypass, source rotation handling |
| `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` | As-built runbook for the Azure infra (ACR, Container Apps Environment, Container Apps Job, Storage Queue, RBAC roles, KEDA scaler config). Source of truth until Bicep IaC catches up. |
| `docs/NOTIFICATION_SYSTEM.md` | Push notification architecture: all 7 notification types, FCM payloads, Web PubSub events, token lifecycle, tap routing |
| `docs/VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md` | Local-first uploader playback handoff doc — architecture and implementation status |
| `docs/BETA_TEST_PLAN.md` | Manual smoke test checklist (60+ items) for beta releases — dual-device testing |
| `docs/BETA_OPERATIONS_RUNBOOK.md` | Incident response, troubleshooting, DB backup/restore, key rotation, cost monitoring. §7 includes avatar telemetry + welcome-prompt funnel KQL queries; §2 adds avatar-specific incident playbooks |
| `docs/WEB_CLIENT_ARCHITECTURE.md` | Web client architecture, deployment, CORS/CSP config, MSAL.js setup, video upload parity, §8.5 avatar upload + welcome prompt |
