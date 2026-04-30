# Clique Pix Web Client — Architecture

Source of truth for the web client's technical architecture. When code and this doc disagree, fix whichever is wrong — don't let the gap persist.

## 1. At a glance

- **Framework**: React 18 + Vite 5 + TypeScript 5
- **Styling**: Tailwind CSS mapped to the Clique Pix design tokens in `styles/tokens.css`
- **Primitives**: Radix UI (Dialog, Dropdown, Toast, Tabs)
- **Routing**: React Router v6 (`createBrowserRouter`)
- **State**: TanStack Query for server state, Zustand for UI state, MSAL.js for auth state
- **Auth**: `@azure/msal-browser` + `@azure/msal-react` (Entra External ID, SPA redirect, PKCE)
- **Real-time**: `@azure/web-pubsub-client` — same hub as mobile
- **Media**: `browser-image-compression` + `heic2any` for photos; `hls.js` for video playback (dynamic import, code-split); `@azure/storage-blob` imported conditionally for video block uploads
- **QR**: `qrcode.react`
- **Icons**: `lucide-react` (matches mobile's stated icon set)
- **Telemetry**: `@microsoft/applicationinsights-web` — same App Insights resource as mobile
- **Hosting**: Azure Static Web Apps at `clique-pix.com`. Landing page at `/`, authenticated app shell at `/events`, `/cliques`, etc. Static docs at `/docs/*`. Deep-link files at `/.well-known/*` preserved byte-for-byte so mobile Universal Links + App Links still work.
- **Domain separation**: web at `clique-pix.com`, API at `api.clique-pix.com` — **different origins, so CORS is mandatory** (configured at APIM in `apim_policy.xml`).

## 2. Directory layout

```
/webapp/
  package.json, vite.config.ts, tsconfig.json, tsconfig.node.json
  tailwind.config.ts, postcss.config.js, eslint.config.js, .prettierrc
  index.html
  .env.example, .env.development, .env.production
  /public/
    staticwebapp.config.json
    /docs/privacy.html, /docs/terms.html
    /.well-known/apple-app-site-association, assetlinks.json
    /assets/icon.png, logo_120x120.png
  /src/
    main.tsx                      # MSAL + QueryClient + Router + Toaster; wires setApiMsalInstance before render
    /app/
      router.tsx                  # / public (landing), authed shell under pathless-parent AuthGuard
      AppLayout.tsx               # top bar + sidebar + bottom tabs for authed routes
      NotFoundScreen.tsx
    /auth/
      msalConfig.ts               # Configuration + loginRequest
      AuthGuard.tsx
      useAccessToken.ts
    /api/
      client.ts                   # axios + request/response interceptors + camelize
      camelize.ts                 # recursive snake_case -> camelCase on responses
      endpoints/
        auth.ts, cliques.ts, events.ts, photos.ts, videos.ts, messages.ts, notifications.ts
    /features/
      landing/                    # public marketing page
        LandingPage.tsx
        /sections/                # Hero, HowItWorks, Features, UseCases, BuiltDifferently, Download, Footer, LandingNav
        /components/              # PhoneMockup, DemoMediaCard, AppStoreBadge, PlayStoreBadge, BetaChip
        /hooks/                   # useRevealOnScroll.ts (IntersectionObserver)
      auth/                       # LoginScreen, AuthCallback, useAuthVerify
      cliques/                    # CliquesListScreen, CliqueDetailScreen, InviteDialog, InvitePrintScreen, InviteAcceptScreen
      events/                     # EventsListScreen, EventDetailScreen, CreateEventModal
      photos/                     # MediaFeed, MediaCard, MediaUploader, Lightbox, ReactionBar
      videos/                     # VideoPlayer (hls.js + native HLS + MP4 fallback), videoUpload, videoValidation
      messages/                   # MessagesScreen, ThreadScreen
      notifications/              # NotificationsScreen, useUnreadNotificationCount
      profile/                    # ProfileScreen
      realtime/                   # realtimeClient.ts (Web PubSub singleton)
    /components/                  # Avatar, Button, Modal, ConfirmDestructive, EmptyState, ErrorState, LoadingSpinner
    /lib/                         # ai.ts (App Insights), compressPhoto.ts, downloadBlob.ts, formatDate.ts
    /models/                      # index.ts — shared domain types (User, Clique, CliqueEvent, Media, Photo, Video, ReactionRecord, AppNotification, DmThread, DmMessage)
    /styles/                      # tokens.css, globals.css (print rules + @keyframes for landing gradient drift)
    vite-env.d.ts
```

## 3. Environment variables

All `VITE_*`-prefixed, baked into the bundle at build. Every value is a public OAuth/MSAL/API identifier — nothing secret.

| Var | Purpose |
|---|---|
| `VITE_API_BASE_URL` | `https://api.clique-pix.com` — axios baseURL |
| `VITE_MSAL_CLIENT_ID` | `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| `VITE_MSAL_AUTHORITY` | `https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/` |
| `VITE_MSAL_KNOWN_AUTHORITY` | `cliquepix.ciamlogin.com` |
| `VITE_MSAL_SCOPE` | `api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user` |
| `VITE_APPLICATION_INSIGHTS_CONNECTION_STRING` | Optional RUM connection string (empty → RUM disabled) |

`.env.example` is the committed template. `.env.development` and `.env.production` hold the actual values.

## 4. Auth

Mirrors the Flutter MSAL flow. MSAL.js uses hidden iframes for silent renewal, so the **12-hour CIAM refresh-token inactivity bug does NOT apply** to web — no 5-layer defense needed.

- **Cache**: `sessionStorage` — per-tab, survives reload, clears on tab close. Safer than `localStorage` against XSS.
- **Sign-in**: `loginRedirect(loginRequest)`. The Entra hosted form handles DOB collection, identical to mobile.
- **Post-sign-in**: `useAuthVerify` hook calls `POST /api/auth/verify` exactly once per session. The backend upserts the user (keyed on the JWT `sub` claim, fallback `oid`) and enforces the 13+ age gate. Returns the `User` object. **On HTTP 401, the hook force-calls `pca.logoutRedirect` for a clean re-sign-in** — a broken session is never allowed to persist as a rendered-but-broken app.
- **Age gate**: HTTP 403 `AGE_VERIFICATION_FAILED` → axios interceptor surfaces the server's message via toast and triggers `logoutRedirect`. Same behavior as mobile.

### 4.1 MSAL singleton wiring (load-bearing, do not regress)

`main.tsx` must call `setApiMsalInstance(msalInstance)` **after** `await msalInstance.initialize()` and **before** `ReactDOM.createRoot(...).render(...)`. This is what makes the axios interceptor in `api/client.ts` use the exact same initialized PCA that `<MsalProvider>` uses.

If the wiring is skipped, `getPca()` throws a loud developer error. This is deliberate. A previous regression (shipped to prod during the initial web-client rollout) built a fallback PCA on the fly via `new PublicClientApplication(...)`, never initialized it, caused `acquireTokenSilent` to throw `BrowserAuthError: uninitialized_public_client_application` on every request, silently dropped the `Authorization` header, and presented empty-state UI as if the user had no data. Fix landed in `fix(webapp): wire MSAL singleton so API requests actually authenticate` (PR #4).

### 4.2 Strict Mode

`<React.StrictMode>` double-invokes effects in dev. `handleRedirectPromise` is awaited once in `main.tsx` BEFORE React mounts, so it can't fire twice. Use `@azure/msal-react` hooks (`useMsal`, `useIsAuthenticated`) instead of calling `handleRedirectPromise` from `useEffect`.

## 5. SWA routing + CSP

`webapp/public/staticwebapp.config.json`:

- **SPA fallback**: unknown paths rewrite to `/index.html` with explicit excludes for `/docs/*`, `/assets/*`, `/.well-known/*`, and file extensions
- **Legacy redirects** (301): `/privacy.html` → `/docs/privacy`, `/terms.html` → `/docs/terms`, and bare `/privacy` and `/terms` canonicals
- **Deep link MIME**: `.well-known/apple-app-site-association` and `assetlinks.json` served as `application/json` with 24h cache. Mobile Universal Links + App Links continue to work byte-for-byte
- **CSP** (strict `default-src 'self'`), with these relaxations:
  - `frame-src https://cliquepix.ciamlogin.com` — MSAL silent-renewal iframe
  - `connect-src` — API at `api.clique-pix.com`, Blob Storage SAS URLs, Web PubSub WSS, MSAL authority, App Insights ingest
  - `media-src blob: https://*.blob.core.windows.net` — HLS Blob URLs, MP4 fallback, local video preview via `URL.createObjectURL`
  - `form-action https://cliquepix.ciamlogin.com` — Entra hosted form submit
  - `style-src 'self' 'unsafe-inline'` — Tailwind inlines some dynamic styles; pragmatic SPA default

Treat CSP as iterative during development — new features occasionally surface a new directive requirement.

### 5.1 Router structure

```ts
[
  { path: '/', element: <LandingPage /> },             // public marketing
  { path: '/login', element: <LoginScreen /> },
  { path: '/auth/callback', element: <AuthCallback /> },
  { path: '/invite/:code', element: <InviteAcceptScreen /> },
  { path: '/cliques/:id/invite/print', element: <AuthGuard><InvitePrintScreen /></AuthGuard> },
  {
    element: <AuthGuard><AppLayout /></AuthGuard>,     // pathless parent; authed shell
    children: [
      { path: '/events', ... }, { path: '/events/:id', ... },
      { path: '/events/:id/messages', ... }, { path: '/events/:id/messages/:threadId', ... },
      { path: '/cliques', ... }, { path: '/cliques/:id', ... },
      { path: '/notifications', ... }, { path: '/profile', ... },
    ],
  },
  { path: '*', element: <NotFoundScreen /> },
]
```

The landing page does **not** auto-redirect authenticated visitors. It swaps the top-right CTA between "Sign in" and "My Events →" based on `useIsAuthenticated()`. Authed users typing `clique-pix.com` still see the marketing page; the shortcut back to the app is always one click away.

## 6. Response-shape conventions

The backend uses PostgreSQL column names in JSON responses (`snake_case`). The web client's TypeScript models use idiomatic `camelCase`. To avoid every endpoint module doing manual conversion, `api/client.ts` mounts a global axios response interceptor that runs `camelize()` on every JSON body before it reaches React Query.

```ts
api.interceptors.response.use((response) => {
  if (response.data && typeof response.data === 'object') {
    response.data = camelize(response.data);
  }
  return response;
});
```

**Rules:**

- Response types in `api/endpoints/*` are written in the **post-transform** `camelCase` shape. The interface reflects what the caller sees, not what the wire carries.
- Request bodies (POST / PUT) stay in `snake_case` because that's what the backend validates on. Endpoint modules shape request bodies explicitly (e.g., `{ reaction_type: reactionType, invite_code: code }`).
- A few list endpoints wrap payloads in envelopes — **always unwrap in the endpoint module, don't make callers know**:
  - `GET /api/notifications` → `{ notifications: [...], next_cursor }` — unwrap via `res.data.data.notifications`
  - `GET /api/events/:id/photos` → `{ photos: [...], next_cursor }`
  - `GET /api/events/:id/videos` → `{ videos: [...] }`
  - `GET /api/dm-threads/:id/messages` → `{ messages: [...], next_cursor }`

Regression history: an early web-client version crashed on sign-in with `TypeError: t?.filter is not a function` because `listNotifications` returned the envelope object and `useUnreadNotificationCount` called `.filter()` on it. Fix landed in `fix(webapp): unwrap list envelopes + convert snake_case to camelCase` (PR #5).

## 7. API endpoints

All endpoints live at `api.clique-pix.com`. Backend is shared with mobile — no server-side changes exist for web.

| Feature | Endpoints |
|---|---|
| Auth | `POST /api/auth/verify`, `GET /api/users/me`, `DELETE /api/users/me` |
| Cliques | `GET/POST /api/cliques`, `GET /api/cliques/:id`, `POST /api/cliques/:id/invite`, `POST /api/cliques/_/join` (see note), `GET /api/cliques/:id/members`, `DELETE /api/cliques/:id/members/me`, `DELETE /api/cliques/:id/members/:userId` |
| Events | `GET /api/events`, `GET /api/cliques/:id/events`, `POST /api/cliques/:id/events`, `GET /api/events/:id`, `DELETE /api/events/:id` |
| Photos | list/upload-url/commit/get/delete + `POST /api/photos/:id/reactions`, `DELETE /api/photos/:id/reactions/:rid` |
| Videos | list/upload-url/commit/get/playback/delete + reactions |
| Messages | thread CRUD + `GET /api/dm-threads/:id/messages`, `POST .../messages`, `PATCH .../read`, `POST /api/realtime/dm/negotiate` |
| Notifications | list, read, delete, clear all |

**Join-by-code oddity**: the backend route pattern is `cliques/{cliqueId}/join` but the handler ignores the path param and resolves the clique by `invite_code` in the body. Mobile Flutter passes `_` as a placeholder; the web client does the same — `POST /api/cliques/_/join` with `{ invite_code }`. Don't try `POST /api/cliques/join` — it returns 404 because the route segment is required.

## 8. Video upload + playback

**Shipped in PR #9** (`feat(webapp): browser video upload + HLS playback (full mobile parity)`). No longer pending.

### 8.1 Upload pipeline (`features/videos/videoUpload.ts`)

Mirrors `app/lib/features/videos/data/video_block_upload_service.dart`:

1. `validateVideoFile(file)` — extension (mp4/mov), size ≤ 500 MB, duration ≤ 5 min (probed via a hidden `<video>` `loadedmetadata` event)
2. `POST /api/events/:id/videos/upload-url` → `{ videoId, blobPath, blockSizeBytes: 4 MB, blockCount, blockUploadUrls: [{ blockId, url }], commitUrl }`. Block URLs are complete — each pre-signed with `?comp=block&blockid=...` already appended
3. For each block in order: `PUT <url>` with the 4 MB chunk as body. **Sequential** (matches mobile), 5-retry exponential backoff (500 ms → 8 s), 4xx non-retryable, 5xx/network retryable
4. Per-block completion persisted in `sessionStorage` under `video_upload_progress_<videoId>` — mid-upload retry resumes from the next incomplete block. Page reload loses the `File` reference; the backend's 30-minute orphan cleanup catches that case
5. `POST /api/events/:id/videos` with `{ video_id, block_ids }` commits via Put Block List. Returns `{ videoId, status: 'processing', previewUrl, message }` (HTTP 202)
6. Feed refetch renders a processing card; the Web PubSub `video_ready` event flips it to active when transcoding finishes

### 8.2 Playback (`features/videos/VideoPlayer.tsx`)

1. `GET /api/videos/:id/playback` → `{ videoId, hlsManifest (raw M3U8 text), mp4FallbackUrl, posterUrl, durationSeconds, width, height }`. Manifest is raw text, not a URL — the client wraps it in a Blob URL before handing it to the player
2. Safari (`video.canPlayType('application/vnd.apple.mpegurl')`) uses native HLS — no JS overhead
3. Other browsers `import('hls.js')` dynamically — `hls.js` is code-split into its own ~162 KB gzip chunk that only loads when a user actually plays a video
4. On fatal HLS error, fall back to `mp4FallbackUrl` (H.264 progressive MP4)
5. **SAS-expiry recovery**: segment SAS tokens are 15 min. On mid-playback error, save `currentTime`, re-fetch `/playback`, reinitialize at saved position. Fires `web_playback_sas_recovered` telemetry.

### 8.3 Wiring

- `features/photos/MediaUploader.tsx` routes video files through `uploadVideo()` with a progress bar (filename + percent + MB counter)
- `features/photos/Lightbox.tsx` mounts `<VideoPlayer videoId=... />` when the item is an `active` video, shows a "transcoding" message for `processing`, and avoids hitting `/playback` on non-active videos (it returns 404 on those)

## 8.5 Avatar upload + welcome prompt (shipped 2026-04-24)

Matches mobile 1:1 in user flow and final image output. Code under `features/profile/`:

- `useAvatarUpload.ts` — hook orchestrating the pipeline: filter bake (canvas + color matrix) → `browser-image-compression` to 512 px JPEG q85 → `getAvatarUploadUrl()` → direct `PUT` with `x-ms-blob-type: BlockBlob` → `confirmAvatar()` → `queryClient.setQueryData(['users', 'me'], user)`. Also exposes `remove`, `setFrame`, `setPrompt` mutations
- `AvatarEditor.tsx` — Radix Dialog with `react-easy-crop` (1:1 aspect, round crop shape, pan + zoom slider). Filter row (Original / B&W / Warm / Cool) + frame preset row (5 gradient swatches). Save calls the hook
- `AvatarWelcomePromptModal.tsx` — branded first-sign-in modal. Non-dismissible via overlay click (`onPointerDownOutside={e => e.preventDefault()}`). Three buttons: Add a Photo / Maybe Later / No Thanks. Escape or dismiss resolves to `later` (safer default than permanent dismiss)
- `AvatarWelcomePromptGate.tsx` — invisible component mounted in `AppLayout`. Self-gates on the backend-computed `shouldPromptForAvatar` flag plus a session-local "already shown" React state. Wires the `yes` path through to a hidden `<input type="file">` + `AvatarEditor`
- `ProfileScreen.tsx` — tappable avatar (hover shows a camera overlay), inline file picker, confetti via `canvas-confetti` on first-ever upload (gated on `localStorage['first_avatar_celebrated']`), Change/Remove text buttons

**Filter matrices** in `useAvatarUpload.ts` are byte-identical to the mobile matrices in `app/lib/features/profile/data/avatar_repository.dart:_matrixFor` — the same user's Warm filter produces visually identical output on iOS, Android, and web.

**`Avatar.tsx`** (in `components/`) now accepts `imageUrl`, `thumbUrl`, `framePreset`, `cacheBuster`. Prefers `thumbUrl` at `size < 64`, full `imageUrl` at 64+. Cache key is appended as `?_v=<cacheBuster>` so the 1-hour SAS rotation doesn't invalidate the HTTP cache (the key only changes when `avatar_updated_at` changes server-side).

**New dependencies** (in `package.json`):
- `react-easy-crop` — browser square-crop widget (parity with mobile `image_cropper`)
- `canvas-confetti` + `@types/canvas-confetti` — first-upload celebration

**CORS prerequisite** (verified 2026-04-24): Azure Blob Storage CORS on `stcliquepixprod` allows `GET` + `PUT` + `HEAD` + `OPTIONS` from `https://clique-pix.com` + `http://localhost:5173`, 3600 s preflight cache. Applies to all `blob` service operations, so avatar reads (`<img src>`) AND direct-PUT uploads (`PUT` with SAS) both work without additional configuration.

**Not deployed yet**: the code shipped in the avatar branch, but web auto-deploys via the SWA GH Actions workflow on merge to `main`. Once merged, zero additional config needed — CORS is pre-set, backend endpoints are live, the component `Avatar.tsx` has defaults that keep the initials-fallback working while users haven't uploaded yet.

## 9. Landing page (public marketing surface at `/`)

Lives under `features/landing/`. Public — no auth required. Composed of section components in `features/landing/sections/` plus shared primitives in `features/landing/components/`.

**Sections** (top-to-bottom):

1. `LandingNav` — sticky top bar, gradient logo + wordmark + "Now in beta" chip. Right CTA swaps between "Sign in" (unauthed) and "My Events →" (authed) via `useIsAuthenticated()`
2. `Hero` — animated radial-gradient spotlights drift behind the content (`@keyframes landing-drift-a/b/c` in `globals.css`, disabled under `prefers-reduced-motion`). Headline "Your moments. Your people. No strangers." Right column is a CSS `PhoneMockup` containing a `DemoMediaCard` — a visual replica of `MediaCard` with hardcoded data and client-side tappable reactions that increment counters without any API calls
3. `HowItWorks` — three-step flow: Start an Event → Create or invite your Clique → Share, react, save what matters. Decomposition splits Clique into its own step for marketing clarity even though the real app keeps Clique creation inline during event creation
4. `Features` — 6-tile grid (camera+editor, video, reactions+DMs, QR invites, auto-delete, cross-platform)
5. `UseCases` — 4 themed cards: weddings, trips, parties, family
6. `BuiltDifferently` — strengths (private by default / temporary by design / small groups, not audiences / your memories on your device). **No competitor comparison section** — we explain our strengths on their own merits
7. `Download` — `AppStoreBadge` + `PlayStoreBadge` (styled with our own CSS + lucide Apple icon + inline Google Play SVG; placeholder `href="#"` until listings exist) + live `qrcode.react` QR of `https://clique-pix.com` for a laptop-to-phone jump
8. `Footer` — logo, tagline, Privacy / Terms / Contact

**Animation discipline**: `useRevealOnScroll` is an IntersectionObserver hook that fades each section in once on enter. Under `prefers-reduced-motion` it resolves `revealed=true` on mount so nothing ever stays hidden.

**Creative touches that are load-bearing for the pitch**:
- Real `<DemoMediaCard>` instead of a static screenshot — the preview doesn't rot when we change the real MediaCard's design
- Tappable reactions in the hero give visitors a moment of product-feel without signing up
- Live QR code in Download section lets laptop visitors pick up their phone and go

## 10. Real-time

`features/realtime/realtimeClient.ts` is a singleton `WebPubSubClient`:

- `initRealtime()` called once in `AppLayout` mount effect (authed shell only — the landing page never connects)
- `negotiateRealtime()` returns a short-lived WebSocket URL + client token
- Client auto-reconnects with exponential backoff (SDK default)
- Incoming events invalidate React Query caches:
  - `dm_message_created` → `['thread', threadId, 'messages']`
  - `video_ready` → `['event', eventId, 'videos']` — visible on the uploader's own session, per Decision 10
  - `notification_created` → `['notifications']`
  - **`new_event` — not yet handled (tracked follow-up)**: mobile shipped real-time `new_event` fan-out on 2026-04-30 (see `docs/NOTIFICATION_SYSTEM.md` "New Event Real-Time Fan-Out"). Backend already publishes `new_event` to every clique member's Web PubSub user channel. Web parity needs: (1) a dispatch branch in `realtimeClient.ts` that invalidates `['events', 'all']` and `['events', cliqueId]` and `['notifications']`, (2) any in-app notifications-list rendering for `new_event` rows. Estimated < 30 lines of code; deferred so the mobile fix could ship first against the user-reported bug.

## 11. App Insights (RUM)

`lib/ai.ts` initializes `ApplicationInsights` when `VITE_APPLICATION_INSIGHTS_CONNECTION_STRING` is set. Auto page-view tracking is enabled. Events fired today (`web_*` prefix so they co-mingle cleanly with mobile's unprefixed events):

- `web_login_success` — first authenticated render of `AppLayout`
- `web_photo_upload_completed` — per successful photo commit
- `web_video_upload_started`, `web_video_upload_committed` — video upload lifecycle
- `web_video_played` — successful playback init
- `web_playback_sas_recovered` — mid-playback SAS-expiry recovery fired
- `web_qr_printed` — user reached the Invite Print screen
- `web_dm_realtime_connected` — Web PubSub connect established
- `web_api_401` — response interceptor saw a 401 (expected during SAS expiry recovery, unexpected otherwise)

Kusto:

```kql
customEvents
| where timestamp > ago(24h)
| where name startswith "web_"
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

Exceptions query:

```kql
exceptions
| where timestamp > ago(24h)
| where customDimensions.stage in~ ("acquireTokenSilent", "video_playback_init", "video_block_upload")
| summarize count() by tostring(customDimensions.stage), outerMessage
```

## 12. Azure config checklist (one-time manual)

1. **Entra app registration** (`7db01206-135b-4a34-a4d5-2622d1a888bf`) — add SPA platform redirect URIs for `https://clique-pix.com/auth/callback` and `http://localhost:5173/auth/callback`; front-channel logout URL `https://clique-pix.com/`. Implicit grant stays **unchecked**.
2. **APIM CORS** — `apim_policy.xml` in this repo is the **CliquePix API v1 → All operations** policy (per-API scope, NOT global). Contains `<base />` + `<cors>` only. Deploy via `az rest PUT` against the management API policy URL with `format: rawxml` body, or via Azure Portal (APIM → APIs → CliquePix API v1 → Design → All operations → `</>`). **`<rate-limit-by-key>` was removed on 2026-04-27** after four consecutive user-blocking 429 incidents traced to APIM Developer-tier in-memory counter staleness — see `apim_policy.xml` in-file comment for the full incident history. Do not re-add `rate-limit-by-key` until APIM is migrated off Developer tier (Standard v2 has a distributed cache + SLA). Abuse protection now lives at the application layer: JWT auth, event-membership checks, User Delegation SAS expiry, orphan cleanup timer.
3. **Blob Storage CORS** on `stcliquepixprod` → Blob service: origins `https://clique-pix.com` + `http://localhost:5173`, methods `GET PUT HEAD OPTIONS`, headers `*`, exposed headers `*`, max-age `3600`. Required because the browser PUTs 4 MB blocks directly to Blob Storage — each block triggers a CORS preflight that max-age=3600 caches for an hour.
4. **Front Door** — no changes; Standard tier passes CORS through.

## 13. Deployment

GitHub Actions: `.github/workflows/webapp-deploy.yml` triggers on push/PR to `main` with paths under `webapp/**`. Uses `Azure/static-web-apps-deploy@v1` with `app_location: webapp`, `output_location: dist`, `app_build_command: npm ci && npm run build`. The `AZURE_STATIC_WEB_APPS_API_TOKEN` secret is reused across deploys — same SWA resource.

### 13.1 Staging-environment quota ritual (temporary, until automated)

The SWA Free tier caps staging environments at 3 concurrent previews. Every PR creates one. Once the cap is hit, subsequent deploys fail with:

```
The content server has rejected the request with: BadRequest
Reason: This Static Web App already has the maximum number of staging environments. Please remove one and try again.
```

The fix until the cleanup is automated in the workflow:

```bash
az rest --method GET \
  --uri "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Web/staticSites/swa-cliquepix-prod/builds?api-version=2023-12-01" \
  | grep -oE '"name":\s*"[^"]+"'

# Delete the staging env named `<N>` (PR number)
az rest --method DELETE \
  --uri "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Web/staticSites/swa-cliquepix-prod/builds/<N>?api-version=2023-12-01"
```

Follow-up (tracked): add a "cleanup closed-PR staging envs" step to `webapp-deploy.yml` so this stops being manual.

### 13.2 PR previews + auth

Microsoft does not support path wildcards in SPA redirect URIs, so PR preview URLs (`<hash>.<region>.azurestaticapps.net`) can't complete Entra sign-in without being added to the app registration manually. Treat previews as non-auth smoke tests. Auth-dependent verification happens in local dev and production.

## 14. Local development

```
cd webapp
npm install
npm run dev
```

Vite runs on `http://localhost:5173` with HMR. The dev server hits the **production** API at `https://api.clique-pix.com` — no local backend required. APIM CORS and Blob Storage CORS must include `http://localhost:5173` (already configured).

## 15. Known limits

1. **Signing out on tab close** — `sessionStorage` MSAL cache is per-tab. Switch to `localStorage` if beta feedback says this is painful (accepts the XSS risk tradeoff).
2. **No Web Push in v1** — users don't get background notifications in browsers. Real-time only while the tab is open. Bell-badge polls every 60 s as a safety net.
3. **Reaction ID persistence** — the enriched list endpoint returns `user_reactions: ['heart']` (types only, no IDs). Unreacting a pre-existing reaction updates the UI but skips the server DELETE until the next feed refresh. Matches mobile behavior (`app/lib/features/photos/presentation/reaction_bar_widget.dart`). Fix would need a backend change to return `{id, type}` pairs.
4. **PR previews cannot test auth-dependent flows** — see §13.2.
5. **HEIC on Chrome/Firefox** requires `heic2any` (WASM). Large files (>30 MB) take seconds to convert in-browser. iOS Safari reads HEIC natively.
6. **Thumbnail SAS cache-busting** — SAS URL query strings change on each refresh, so the browser HTTP cache misses on every load. Acceptable for v1 (thumbnails are ~50 KB).
7. **Safari cross-origin blob download** — handled via `fetch() + URL.createObjectURL`, not naive `<a download>`.
8. **App Store + Google Play badges** are placeholder `href="#"` with our own CSS + lucide/inline SVG glyphs. Swap in official SVGs + real URLs once the listings are authorized.
9. **Staging-environment quota cleanup is manual** — see §13.1.
10. **Legacy App Store / Play Store listings** may still point at `/privacy.html` and `/terms.html` — the 301 redirects cover the transition; update listings to `/docs/*` directly as post-launch cleanup.

## 16. Change log

| PR | Summary |
|---|---|
| #3 | Initial web client at clique-pix.com — auth, cliques, events, photos, DMs, notifications, profile |
| #4 | Fix MSAL singleton wiring — root cause of the initial "empty Events/Cliques" crash |
| #5 | Unwrap list envelopes + global camelize interceptor — fix for `TypeError: t?.filter is not a function` and blank cards |
| #6 | Mobile-parity media cards — uploader header, reaction bar, download icon, owner 3-dot menu |
| #7 | Fix invite flow — QR render, `/api/cliques/_/join` endpoint, auto-open Invite dialog after create |
| #8 | Branded QR print card — gradient bands, logo, wordmark (wedding-ready) |
| #9 | Browser video upload + HLS playback — full mobile parity |
| #10 | Public landing page at `/` — vibrant marketing surface |
| #11 | HowItWorks: split Clique into its own step 2 |
| (pending merge) | Avatar upload + first-sign-in welcome prompt — tappable Profile avatar, `react-easy-crop` square crop, filter presets (Original / B&W / Warm / Cool), frame presets (5 gradients), `canvas-confetti` on first upload, `AvatarWelcomePromptGate` mounted in AppLayout |
| (pending merge, 2026-04-28) | Organizer media moderation — `MediaCard` accepts `eventCreatedByUserId`; `canDelete = isUploader \|\| isOrganizerDeletingOthers`. The 3-dot menu is now visible on the event organizer's view of OTHER members' uploads (label reads "Remove" instead of "Delete"); `<ConfirmDestructive>` title and body branch on `isOrganizerDeletingOthers`; success toast says "Photo removed" / "Video removed" for the moderation path. Backed by the deployed `canDeleteMedia` API which accepts uploader OR `events.created_by_user_id`. `MediaFeed` + `EventDetailScreen` thread `event.createdByUserId` down. `Lightbox.tsx` was audited and is unchanged (read-only — no delete control). Pre-existing uploader self-delete copy is unchanged (uploader takes precedence over organizer). |
