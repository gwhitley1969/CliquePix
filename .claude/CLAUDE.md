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

**Subscription Paywall + Free Trial (v1, RevenueCat — migration 012/013)**
- Single tier, entitlement `plus`. **Monthly $3.99 / Annual $39.99** ("2 months free"). Annual carries a 7-day store intro offer for new subscribers.
- **7-day no-card free trial of the full app**, granted at first sign-in (`users.trial_ends_at = NOW() + 7 days`, COALESCE-preserved). After it lapses unsubscribed, a hard paywall drops. Effective access = `entitlement_active OR (trial_ends_at > NOW())`, computed live (no reconciliation timer for trial).
- Backend is authoritative: `requireActiveEntitlement` 402s `SUBSCRIPTION_REQUIRED` unless subscribed OR in trial; `buildAuthUserResponse` emits `entitlement { active, in_trial, trial_ends_at, effective_active, ... }`. RevenueCat webhook at `POST /api/internal/revenuecat-webhook`; 6h `entitlementReconciliationTimer` for subscription (not trial) expiry.
- Mobile: `purchases_flutter` + `purchases_ui_flutter` (Paywalls v2). Router gates on `effective_active`; only `/paywall` + `/profile` reachable without access. Web: gated routes show "subscribe in the mobile app" (no Stripe in v1).
- Reviewer + beta testers: RevenueCat **Promotional** entitlement grants (no DB override).
- **Guardrail: do NOT regress to a free tier or remove the paywall without explicit product approval.** Monetization is now a v1 product requirement, not a future consideration.
- **Store review prompts:** native `in_app_review` `requestReview()` fires after the user's 3rd successful media upload (cross-session), frequency-capped at 120 days, availability-gated, never on an error or paywall path. Manual "Rate Clique Pix" tile in Profile uses `openStoreListing(appStoreId: 6766294274)`.

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

POST   /api/internal/video-processing-complete     # Container Apps Job callback (Azure Functions function-key auth via ?code=; managed-identity JWT deferred to v1.5)

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
DELETE /api/push-tokens                            # de-register this device's FCM token on sign-out / account delete (body: { token })

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
12. Container Apps Job calls `POST /api/internal/video-processing-complete` with results. **Auth is the Azure Functions function key** (`authLevel: 'function'`), passed as `?code=<FUNCTION_CALLBACK_KEY>` (key sourced from Key Vault, set as the Job's env var) — NOT a managed-identity JWT. The managed-identity-token approach was attempted and deferred to v1.5 (needs an Azure AD app registration for the Function's audience). Treat the function key as a sensitive shared secret: a leak (via the Job env, Key Vault, or storage) lets a caller flip `processing` videos to `active`. See `backend/transcoder/src/callbackService.ts` + `backend/src/functions/videos.ts:videoProcessingComplete`.
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
- **Canonical media-delete helper (added 2026-06-04, security audit C2):** ALL media deletion goes through `deleteMediaAssets(media)` in `backend/src/shared/services/blobService.ts` — it branches on `media_type` (video → prefix-delete the per-media dir; photo → original + thumbnail). Any new delete path MUST call it. Deleting only `blob_path` + `thumbnail_blob_path` for a row that could be a video orphans the HLS/fallback/poster blobs forever (the bug that hit `deleteEvent`, `deleteMe`, and the expiry safety-net before the fix). See `docs/SECURITY_AUDIT_2026-06-04.md`.

---

## Age Gate (13+) — Claim-based backend enforcement

13+ minimum enforced by a **claim-based backend check** — NOT a Custom Authentication Extension (Microsoft docs state age gating isn't supported in External ID; the CAE-on-`OnAttributeCollectionSubmit` approach was tried and reverted 2026-04-18 as unsupported/opaque). DOB is collected once by the Entra-hosted signup form, stored on the user principal, emitted as a `dateOfBirth` claim. `authVerify` (`backend/src/functions/auth.ts`) reads it on first login, computes age server-side: ≥13 upserts `age_verified_at = NOW()`; <13 returns HTTP 403 `AGE_VERIFICATION_FAILED` and best-effort deletes the Entra account via Graph. Returning users fast-path (claim + `age_verified_at` already set; never re-prompted).

**Hard rules:**
- `MIN_AGE = 13` lives in `backend/src/shared/utils/ageUtils.ts`. If policy changes, **three files move together**: `ageUtils.ts`, `website/privacy.html` (§11), `website/terms.html` (§2).
- **No login-screen DOB picker in the client** — the login screen is just the "Get Started" MSAL button. On a 403, `AuthNotifier.signIn` reads `error.message`, calls `resetSession()` to clear the MSAL cache (so the invalid token isn't reused), and emits `AuthError(serverMessage)` rendered as a red banner.
- Postgres `users` stores only `age_verified_at` (a timestamp), **never DOB** (Entra holds DOB). Upsert uses `COALESCE` so a grandfathered user's original timestamp is never overwritten.
- Telemetry never logs raw DOB or precise age — only coarse `ageBucket` (`age_gate_passed` / `age_gate_denied_under_13` / `age_gate_entra_delete_failed`).

Key code: `decideAgeGate` / `extractDobFromClaims` (GUID-prefixed `extension_<b2cAppId>_dateOfBirth`) / `parseAnyDob` in `auth.ts`; `deleteEntraUserByOid` in `entraGraphClient.ts`; migration `008_user_age_verification.sql`. Entra portal setup (custom attribute, claim mapping, manifest `acceptMappedClaims` + `accessTokenAcceptedVersion: 2`, Graph `User.ReadWrite.All` consent), full flow, CAE failure modes, and reverted-attempt history: **`docs/AGE_VERIFICATION_RUNBOOK.md`**.

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

### Critical invariants (full per-layer mechanics in the doc)

The rules that bite if violated — step-by-step layer implementation lives in `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`:
- **Layer 1** battery-optimization exemption (`Permission.ignoreBatteryOptimizations`, gated on `battery_dialog_shown`) is required on API 23+ or Samsung/Xiaomi/Huawei kill Layer 4.
- **Layer 2 silent push** (`refreshTokenPushTimer`, CRON `0 7,22,37,52 * * * *`, users inactive 9–11h, 6h dedup) sends FCM with **NO `notification` block** (`apns-push-type: background`, `content-available: 1`, `android.priority: high`). iOS fallback when the isolate can't run MSAL: write `pendingRefreshFlagKey`; Layer 3 consumes it.
- **Layer 3 (primary)**: on `AppLifecycleState.resumed`, refresh if token ≥6h stale OR pending flag set. `pendingRefreshFlagKey` is cleared **before** awaiting the refresh, so a hung refresh can't poison every future resume.
- **Layer 4 (Android only)**: WorkManager (~8h) runs full MSAL silent refresh in-isolate — safe because the MSAL cache is process-wide.
- **Layer 5**: cold-start + active-session + interceptor all route session-expired to `WelcomeBackDialog` with `loginHint`. **Three sites must stay in sync** on the session-expired regex (`AADSTS700082` / `AADSTS500210` / `no_account_found`): `AuthInterceptor._isSessionExpired`, `AuthRepository._extractAadstsCode`, `AuthNotifier._handleSilentSignInFailure`.
- **Never render `error.toString()` for AsyncError on bootstrap-path screens** — use `core/utils/api_error_messages.dart::friendlyApiErrorMessage(...)` (`home_screen.dart` is canonical). Narrow-scope SnackBars on explicit local actions may use `'Failed to X: $e'`.
- **Honest limits:** APNs throttles background pushes (<100% delivery); force-killed iOS apps and disabled Background App Refresh get no silent push — Layer 5 is the only recourse there.

### Android Permissions

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

**`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` are NOT declared.** Google Play restricts `USE_EXACT_ALARM` to alarm-clock/calendar apps and rejects builds that include it, so we suppress `flutter_local_notifications`' transitive contribution via `<uses-permission ... tools:node="remove" />`. The Friday reminder uses `AndroidScheduleMode.inexactAllowWhileIdle` (needs neither).

### iOS Info.plist

`UIBackgroundModes` must contain `remote-notification` (already set) for silent pushes to wake the app.

**Do NOT declare `BGTaskSchedulerPermittedIdentifiers`.** Layer 4 is Android-only — there is no iOS `BGTaskScheduler.shared.register(...)` handler. A declaration without a matching registered handler throws `NSInternalInconsistencyException` + SIGABRT (symptom: "app vanishes after MSAL/Safari sign-in"). The `com.cliquepix.tokenRefresh` constant in `background_token_service.dart:18` is the WorkManager (Android) task id — unrelated to iOS BGTaskScheduler.

### Token Storage & Key Timing

- Auth/refresh tokens in `flutter_secure_storage` **only** — never `shared_preferences`. `pendingRefreshFlagKey` (SharedPreferences) bridges Layer 2 → Layer 3. `lastRefreshTime` written atomically in `TokenStorageService.saveTokens`. Clear all on logout; cancel WorkManager.
- Timings: Microsoft inactivity **12h** (hardcoded) · silent-push window inactive **9–11h** · Layer 3 stale **6h** · Layer 4 interval **8h** · silent-push dedup **6h**/user.
- Backend (migration `009_user_activity_tracking.sql`, partial index on non-null): `users.last_activity_at` (updated fire-and-forget by `authMiddleware`, capped 1/min, feeds Layer-2 timer) + `users.last_refresh_push_sent_at` (enforces 6h dedup).
- Diagnostics: tap the Profile version number 7× to unlock Token Diagnostics (refresh age, pending-flag, battery-exempt, 50-event ring buffer). Telemetry posts to `/api/telemetry/auth` (accepts expired-but-valid JWTs via `verifyJwtAllowExpired`).

**Full implementation, telemetry event list, architecture diagrams, and Kusto queries: `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`.**

---

## Media Handling Pipeline

Photos compress cheaply client-side (500KB–1.5MB); videos (50–150MB) transcode server-side; avatars are small square per-user fixed paths with synchronous thumb gen. Step-by-step upload flows are under **API Design** above; full FFmpeg invocations + parameter rationale live in **`docs/VIDEO_ARCHITECTURE_DECISIONS.md`** (Decision 3, Decisions 8–12).

### Photo Pipeline — locked numbers

Client (`flutter_image_compress`): strip EXIF → resize longest edge ≤2048px → JPEG q80 → HEIC→JPEG → reject >10MB. Server at confirm (Function never touches bytes mid-upload): verify blob, validate content-type **JPEG/PNG only** + size (reject >15MB), then fire-and-forget `sharp` thumbnail (400px longest edge, JPEG q70, ~30–80KB → `thumbnail_blob_path`; feed falls back to original on failure). See `backend/src/functions/photos.ts`.

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max dimension | 2048px | Covers all phone screens; group-photo app, not stock photography. |
| JPEG quality | 80 | "Visually indistinguishable." 90+ wastes bytes; 70 shows artifacts on gradients/skin. |
| Max file size | 10MB | Post-compression safety net (typical 500KB–1.5MB). |
| Format | JPEG | Universal; HEIC converted client-side. |

### Video Pipeline — locked numbers

Client does **validation only** (no meaningful client compression): extension MP4/MOV, duration ≤5min, file-size estimate, show upload-time estimate. Server: ffprobe authoritative validation → `canStreamCopy(probeResult)` picks **fast path** (`-c copy` tee remux, ~2–5s) vs **slow path** (libx264 re-encode + HDR→SDR `zscale`/`tonemap=hable`). Both emit HLS + MP4 from a **single tee-muxer invocation**; poster extracted separately; original master set to Cool tier. KEDA polling 5s, min-executions=1.

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max duration | 5 minutes | Spec; balances meaningful moments vs transcoding/storage cost. |
| Accepted containers | MP4, MOV | iPhone MOV, Android MP4. |
| Accepted source codecs | H.264, HEVC | Others (VP9, AV1) rejected server-side. |
| Max output resolution | 1080p | No 4K in v1; downscale only, never upscale. |
| Output codec | H.264 | Best `video_player`/HLS compatibility. |
| HDR policy | Normalize to SDR | Consistent playback; HDR preservation is post-v1. |

**Locked FFmpeg parameters (do not change without measuring):** preset `veryfast` (slow path only — fast path is `-c copy`) · CRF 23 · AAC 128k · HLS segments 4s · **`-pix_fmt yuv420p` REQUIRED on slow path** (or HDR yields undecodable 10-bit High10 H.264) · profile/level high/4.0 · color metadata bt709. Rotation is **autorotate-baked** — do NOT add `-noautorotate` without an explicit `transpose` (see Decision 16). Callback reports `processing_mode: 'transcode' | 'stream_copy'` + `fast_path_failure_reason` for telemetry.

### Avatar Pipeline (migration 010)

Headshots replace the initials-gradient-ring fallback everywhere a user is surfaced. Per-user fixed paths `avatars/{userId}/original.jpg` (512×512 q85) + `thumb.jpg` (128×128 q75, `sharp` at confirm). Client: pick → square crop (native) → optional filter (Original/B&W/Warm/Cool, **identical matrices Flutter+web**) → 512px q85 → upload-url SAS (write+create) → confirm (≤3MB, JPEG/PNG, stamps `avatar_updated_at`, returns enriched `User`).

**Hard rules:**
- **1-hour view SAS** (`generateViewSas(path, 3600)`) — longer than photo (5min) / video (15min) because avatars render on every screen.
- **Cache key stability:** `cacheKey: 'avatar_${userId}_v${avatar_updated_at.ms}'` (Flutter) / `?_v=` param (web). URL churns hourly; cache key only churns on actual change — without this `cached_network_image` thrashes.
- All 14 user-denormalizing handlers run `enrichUserAvatar` (`avatarEnricher.ts`, single SAS-signing source); `buildAuthUserResponse` is the one canonical auth-user shape → one `UserModel.fromJson`.
- `AuthNotifier.updateUserAvatar` is a **pure in-memory swap — MUST NOT trigger token refresh** (would disturb the 5-layer Entra counters).
- Frame presets `0..4`: `0` = auto-gradient from `displayName.hashCode`; `1..4` explicit palette matching mobile `AvatarWidget._palette` / web `Avatar.palettes` 1:1. `PATCH /api/users/me/avatar/frame` (affects the initials ring too).
- First-sign-in prompt: `should_prompt_for_avatar = avatar_blob_path IS NULL AND NOT avatar_prompt_dismissed AND (snoozed_until IS NULL OR < NOW())`. Yes / Maybe Later (`snooze` → +7d) / No Thanks (`dismiss` → never). Back/tap-outside = snooze.
- Account deletion (`deleteMe`) deletes both blobs first, idempotent (`deleteIfExists`).

Full pipeline + schema: `docs/VIDEO_ARCHITECTURE_DECISIONS.md`, `docs/WEB_CLIENT_ARCHITECTURE.md §8.5`, `docs/ARCHITECTURE.md §7`.

### ⚠️ APIM rate-limiting — DO NOT re-add

Rate limiting was **removed entirely from APIM** after FIVE user-blocking 429 incidents (4 on 2026-04-27, 1 on 2026-04-29). APIM has **FOUR policy scopes** (Global, Product, API, Operation) and a limit at any one produces the same 429 body; the 2026-04-29 culprit was the auto-provisioned default `starter` **Product** policy (`<rate-limit calls="5"/>` + `<quota calls="100"/>`), which the prior API-scope-only cleanup missed. **Do not re-add `<rate-limit-by-key>` / `<rate-limit>` / `<quota>` at ANY scope** until APIM moves off Developer tier. When diagnosing any 429, audit **all four scopes** (`docs/BETA_OPERATIONS_RUNBOOK.md §2`). Abuse protection is application-layer (JWT, membership checks, SAS expiry, orphan cleanup); client `silentRetryOn429` absorbs one 429/5-min/device. Full 5-incident history: `apim_policy.xml`.

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

1. **App installed:** App Link / Universal Link routes directly into the app, lands on invite acceptance screen, calls `POST /api/cliques/_/join` with the invite code in the body.
2. **App not installed (Android):** Chrome opens `clique-pix.com/invite/{code}` → `InstallBanner` renders with a "Get on Google Play" badge whose URL carries `?referrer=invite_code%3D{code}` → user installs from Play → on first launch the Flutter app reads the Play Install Referrer via `play_install_referrer` (in `app/lib/services/install_referrer_service.dart`), persists the code to SharedPreferences key `install_referrer_pending_invite_code`, and `_CliquePixState._consumePendingInstallReferrerInvite` (in `app/lib/app/app.dart`) routes to `/invite/{code}` after the first `AuthAuthenticated` transition. JoinCliqueScreen completes the join. See `docs/INVITE_INSTALL_REFERRER.md`.
3. **App not installed (iOS):** Safari opens `clique-pix.com/invite/{code}` → in-page install banner renders with a TestFlight badge pointing at `https://testflight.apple.com/join/hWznNvJ6` (Clique Pix is TestFlight-only until App Store review approves the public listing; Apple ID `6766294274`, bundle `com.cliquepix.app`) → user installs via TestFlight → on first launch, no invite code is preserved (iOS has no Play Install Referrer equivalent), so the in-banner caption directs the user to re-tap the original invite link from Messages / wherever it was shared. Universal Link then routes into the freshly-installed app. When the public App Store listing goes live, activate Phase C-final per `docs/INVITE_INSTALL_REFERRER.md` (Smart App Banner meta tag in `webapp/index.html` + `app-argument` rewrite) so the invite code rides into the app via `NSUserActivity.webpageURL` on the post-install "OPEN" tap.
4. **Web-only path:** anyone can join entirely on the web by signing in via the existing "Sign in to accept" CTA — no install ever required.

---

## Security Rules

### API Authorization — Every Endpoint Must Enforce:
- User is authenticated (valid Entra token verified by the Function)
- User belongs to the clique/event they are accessing (membership check)
- On `DELETE /api/photos/{id}` and `DELETE /api/videos/{id}`: caller must be the uploader OR the event organizer (`events.created_by_user_id`). Use the shared `canDeleteMedia` helper in `backend/src/shared/utils/permissions.ts`; uploader takes precedence; record `deleterRole` ∈ `'uploader' | 'organizer'` on the `photo_deleted` / `video_deleted` telemetry event alongside `uploaderId` and `eventOrganizerId`. Both handlers JOIN `events` in the SELECT for a single round-trip.

**Invite-code entropy (hard rule, security audit C1, 2026-06-04):** `generateInviteCode` in `backend/src/functions/cliques.ts` uses `crypto.randomBytes(16).toString('hex')` (128-bit). NEVER shrink it. `POST /api/cliques/_/join` resolves a clique by `invite_code` alone and there is NO APIM rate limiting (deliberately removed) — anything weaker is brute-forceable to join private cliques.

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

**Atomic-claim invariant (added 2026-06-04, security audit H2):** the orphan-cleanup DELETE and the upload-confirm UPDATE race. Both sides MUST use a guarded atomic claim — do NOT revert to read-then-update or unconditional `DELETE WHERE id=$1`:
- **Confirm** (`confirmUpload`, `commitVideoUpload`): the status UPDATE is `... WHERE id=$1 AND status='pending'`. 0 rows ⇒ the timer reaped the upload mid-confirm — clean up and tell the client to retry (telemetry `photo_commit_lost_to_orphan_cleanup` / `video_commit_lost_to_orphan_cleanup`); never enqueue a transcode for a deleted row.
- **Orphan timer**: `DELETE ... WHERE id=$1 AND status='pending'`, and delete the blob ONLY after that guarded delete wins, so a confirming upload's blob is never deleted.

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

### Flows & wiring (full detail: `docs/NOTIFICATION_SYSTEM.md`)

- **Backend:** query members' push tokens → FCM HTTP v1 `sendToMultipleTokens()` (`notification` + `data`) → write `notifications` rows for the in-app list → failed sends purge stale tokens (`DELETE FROM push_tokens WHERE token = ANY($1)`).
- **Client display:** Foreground → `main.dart` `FirebaseMessaging.onMessage` → `flutter_local_notifications.show()` heads-up. Background/Terminated → OS auto-displays from the `notification` payload; tap → `onMessageOpenedApp` / `getInitialMessage()`. The `onMessage` listener is wired in `main.dart` **right after plugin init** so `show()` is always ready.
- **Channels** (created in `main.dart`): `cliquepix_default` (HIGH — all pushes) + `cliquepix_reminders` (DEFAULT — Friday reminder only, separately mutable). Android 13+ permission requested once.
- **Tokens:** `PushNotificationService` registers the FCM token post-auth via `POST /api/push-tokens`, re-registers on `onTokenRefresh`. **De-registers on sign-out / account delete** via `PushNotificationService.deregister()` → `DELETE /api/push-tokens` (body `{ token }`, scoped to the caller), wired into `AuthNotifier.signOut/deleteAccount` and run BEFORE the JWT is cleared — else the device keeps receiving pushes for the signed-out user (security audit H6, 2026-06-04). Backend upserts register on conflict.
- **Tap nav (GoRouter via `data`):** `event_id` → `/events/$id` · `clique_id` → `/cliques/$id` · `video_id`+`event_id` (from `video_ready`) → `/events/$eventId?mediaId=$videoId`. Foreground taps: `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap`.

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
- `install_referrer_read` (with `had_invite_code=true|false` in `errorCode` slot) — Android Play Install Referrer drain via pending-isolate queue
- `install_referrer_auto_join_attempted` — fires when the auth-state listener consumes a pending invite code and routes to `/invite/{code}`
- `web_invite_install_banner_shown` (with `platform`) — webapp `InstallBanner`
- `web_invite_install_badge_clicked` (with `platform`) — webapp `InstallBanner` Play badge click
- `web_invite_web_signin_clicked` — webapp `InviteAcceptScreen` "Sign in to accept" CTA

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
| *(Callback auth to Function)* | — | **Azure Functions function key** (`authLevel: 'function'`) passed as `?code=<FUNCTION_CALLBACK_KEY>` on `/api/internal/video-processing-complete`. Managed-identity JWT validation was attempted and deferred to v1.5. Rotate the key as a sensitive shared secret. |

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

The full 18-point acceptance checklist lives in **`docs/PRD.md`**. In short, v1 is done when, cleanly on both iOS and Android, a user can: sign in → create a Clique + invite (link/SMS/QR, deep-linked) → start an Event (24h/3d/7d) → capture or pick a **photo or video** → see photos in seconds and videos upload reliably with a processing placeholder, while **playing their own video instantly from the local device file** → play others' videos via HLS+MP4 fallback → react, save (single + bulk multi-select), share, and **delete their own media** → receive the right push notifications (uploader gets the Web PubSub `video_ready` but not the FCM push for their own video) → see media auto-expire from the cloud → **upload a profile picture** that replaces initials everywhere → and get the first-sign-in **avatar welcome prompt** (Yes / Maybe Later / No Thanks, persisted server-side).

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
| `docs/INVITE_INSTALL_REFERRER.md` | Install-aware QR invites + deferred deep linking: Phase A (web install banner), Phase B (Android Play Install Referrer), Phase C (iOS Smart App Banner — deferred until App Store listing live), telemetry, verification with `adb shell am broadcast` |
| `docs/SECURITY_AUDIT_2026-06-04.md` | Pre-submission security & detrimental-bug audit: methodology, all findings (Critical→Low) + disposition, fixes shipped (commit SHAs + file:line), verified-clean list, remaining items, and the **don't-regress invariants** (invite-code entropy, `deleteMediaAssets`, upload-confirm atomic claim, `forceSync` lag guard, FCM de-register, callback function-key auth) |
