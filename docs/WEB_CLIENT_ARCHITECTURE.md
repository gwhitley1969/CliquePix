# Clique Pix Web Client — Architecture

This document is the source of truth for the web client's technical architecture. When code and this document disagree, fix whichever is wrong but do not let the gap persist.

## 1. At a glance

- **Framework**: React 18 + Vite 5 + TypeScript 5
- **Styling**: Tailwind CSS with CSS variables mapped to the Clique Pix design tokens
- **Primitives**: Radix UI (Dialog, Dropdown, Toast, Tabs)
- **Routing**: React Router v6 (`createBrowserRouter`)
- **State**: TanStack Query for server state, Zustand for UI state, MSAL.js for auth state
- **Auth**: `@azure/msal-browser` + `@azure/msal-react` (Entra External ID, SPA redirect flow, PKCE)
- **Real-time**: `@azure/web-pubsub-client`
- **Media**: `browser-image-compression` + `heic2any` for photo uploads, `hls.js` for HLS playback, `@azure/storage-blob` for video block uploads (both code-split)
- **QR**: `qrcode.react`
- **Icons**: `lucide-react`
- **Telemetry**: `@microsoft/applicationinsights-web`
- **Hosting**: Azure Static Web Apps at `clique-pix.com` root; static docs at `/docs/*`; deep-link files at `/.well-known/*`; Flutter deep-link compatibility preserved byte-for-byte
- **Domain separation**: web client at `clique-pix.com`; API at `api.clique-pix.com` (different origin — CORS is mandatory and configured at APIM)

## 2. Directory layout

```
/webapp/
  package.json
  vite.config.ts
  tsconfig.json, tsconfig.node.json
  tailwind.config.ts, postcss.config.js
  eslint.config.js, .prettierrc
  index.html
  .env.example, .env.development, .env.production
  /public/
    staticwebapp.config.json
    /docs/privacy.html, /docs/terms.html
    /.well-known/apple-app-site-association, assetlinks.json
    /assets/icon.png, logo_120x120.png
  /src/
    main.tsx                     # entry: MSAL + QueryClient + Router + Toaster
    /app/
      router.tsx                 # route tree
      AppLayout.tsx              # top bar + sidebar + bottom tabs
      NotFoundScreen.tsx
    /auth/
      msalConfig.ts              # MSAL Configuration + loginRequest
      AuthGuard.tsx              # redirects to signIn() if unauthenticated
      useAccessToken.ts
    /api/
      client.ts                  # axios + request/response interceptors
      endpoints/auth.ts, cliques.ts, events.ts, photos.ts, videos.ts, messages.ts, notifications.ts
    /features/
      auth/           LoginScreen.tsx, AuthCallback.tsx, useAuthVerify.ts
      cliques/        CliquesListScreen, CliqueDetailScreen, InviteDialog, InvitePrintScreen, InviteAcceptScreen
      events/         EventsListScreen, EventDetailScreen, CreateEventModal
      photos/         MediaFeed, MediaUploader, Lightbox
      videos/         (see §7)
      messages/       MessagesScreen, ThreadScreen
      notifications/  NotificationsScreen, useUnreadNotificationCount
      profile/        ProfileScreen
      realtime/       realtimeClient.ts (Web PubSub singleton)
    /components/      Button, Modal, ConfirmDestructive, EmptyState, LoadingSpinner
    /lib/             ai.ts (App Insights), compressPhoto.ts, downloadBlob.ts, formatDate.ts
    /models/          index.ts (shared domain types)
    /styles/          tokens.css, globals.css
    vite-env.d.ts
```

## 3. Environment variables

All vars are `VITE_*`-prefixed and baked into the bundle at build time. Every value is a public OAuth/MSAL/API identifier (no secrets).

| Var | Purpose |
|---|---|
| `VITE_API_BASE_URL` | `https://api.clique-pix.com` — axios baseURL |
| `VITE_MSAL_CLIENT_ID` | `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| `VITE_MSAL_AUTHORITY` | `https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/` |
| `VITE_MSAL_KNOWN_AUTHORITY` | `cliquepix.ciamlogin.com` |
| `VITE_MSAL_SCOPE` | `api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user` |
| `VITE_APPLICATION_INSIGHTS_CONNECTION_STRING` | Optional RUM connection string (empty → RUM disabled) |

`.env.example` is the committed template. `.env.development` and `.env.production` hold the actual values (since they are public).

## 4. Auth

Mirrors the Flutter MSAL flow. Because MSAL.js uses hidden iframes for silent renewal, the **12-hour CIAM refresh-token inactivity bug does NOT apply** — the web client does not need the 5-layer defense the mobile app uses. Silent renewal Just Works.

- **Cache**: `sessionStorage` — per-tab; survives reload, clears on tab close. Safer than `localStorage` against XSS. (If users complain about signing in on every new tab, switch to `localStorage` — see the mobile Optimistic Auth doc for the tradeoffs.)
- **Sign-in**: `loginRedirect(loginRequest)`. Entra hosted form handles DOB collection, identical to mobile.
- **Post-sign-in**: `useAuthVerify` hook calls `POST /api/auth/verify` once per session. The backend upserts the user, enforces the 13+ claim-based age gate, and returns the `User` object.
- **Age gate**: 403 `AGE_VERIFICATION_FAILED` → axios interceptor surfaces the server's message via toast and triggers `pca.logoutRedirect`. Same user experience as mobile.
- **Token attachment**: axios request interceptor calls `acquireTokenSilent` before each request, sets `Authorization: Bearer <token>`. On 401, triggers `acquireTokenRedirect`.
- **Strict Mode**: handled via `@azure/msal-react` hooks — we do **not** call `handleRedirectPromise` manually in a `useEffect`. `main.tsx` awaits `handleRedirectPromise()` once before mounting the React tree.

## 5. SWA routing and CSP

`webapp/public/staticwebapp.config.json` enforces:

- **SPA fallback**: unknown paths rewrite to `/index.html` (React Router handles), with explicit excludes for `/docs/*`, `/assets/*`, `/.well-known/*`, and file extensions
- **Legacy redirects** (301): `/privacy.html` → `/docs/privacy`, `/terms.html` → `/docs/terms`, plus `/privacy` and `/terms` canonicals
- **Deep link MIME**: `.well-known/apple-app-site-association` and `assetlinks.json` served as `application/json` with 24h cache. Mobile Universal Links and App Links still work byte-for-byte.
- **CSP**: strict `default-src 'self'`. Key relaxations:
  - `frame-src https://cliquepix.ciamlogin.com` — MSAL.js silent-renewal iframe
  - `connect-src` — API at `api.clique-pix.com`, Blob Storage SAS URLs, Web PubSub WSS, MSAL authority, App Insights ingest
  - `media-src blob: https://*.blob.core.windows.net` — local video preview via `URL.createObjectURL` plus HLS segments/MP4 fallback
  - `form-action` — Entra hosted form submit
  - `style-src 'self' 'unsafe-inline'` — Tailwind inlines dynamic styles; `'unsafe-inline'` is the pragmatic SPA default

CSP is iterative during local dev. Expect to add directives when new features trigger browser console blocks.

## 6. API endpoints used by feature

All endpoints live behind `api.clique-pix.com` and are reused from mobile — no backend code changes.

| Feature | Endpoints |
|---|---|
| Auth | `POST /api/auth/verify`, `GET /api/users/me`, `DELETE /api/users/me` |
| Cliques | `GET/POST /api/cliques`, `GET /api/cliques/:id`, `POST /api/cliques/:id/invite`, `POST /api/cliques/join`, `GET /api/cliques/:id/members`, `DELETE /api/cliques/:id/members/me`, `DELETE /api/cliques/:id/members/:userId` |
| Events | `GET /api/events`, `GET /api/cliques/:id/events`, `POST /api/cliques/:id/events`, `GET /api/events/:id`, `DELETE /api/events/:id` |
| Photos | `GET /api/events/:eventId/photos`, `POST /api/events/:eventId/photos/upload-url`, `POST /api/events/:eventId/photos`, `GET /api/photos/:id`, `DELETE /api/photos/:id`, `POST /api/photos/:id/reactions`, `DELETE /api/photos/:id/reactions/:rid` |
| Videos | `GET /api/events/:eventId/videos`, `POST /api/events/:eventId/videos/upload-url`, `POST /api/events/:eventId/videos`, `GET /api/videos/:id`, `GET /api/videos/:id/playback`, `DELETE /api/videos/:id`, reactions mirror photos |
| Messages | `POST /api/events/:id/dm-threads`, `GET /api/events/:id/dm-threads`, `GET /api/dm-threads/:id`, `GET /api/dm-threads/:id/messages`, `POST /api/dm-threads/:id/messages`, `PATCH /api/dm-threads/:id/read`, `POST /api/realtime/dm/negotiate` |
| Notifications | `GET /api/notifications`, `PATCH /api/notifications/:id/read`, `DELETE /api/notifications/:id`, `DELETE /api/notifications` |

## 7. Video upload and playback — implementation status

**Scaffold committed; full parity pending.** The web client currently surfaces a "video upload coming soon" toast in `MediaUploader`. Videos uploaded from mobile are visible in the web feed via `listEventVideos` and the `videos.ts` endpoint module, but the browser-side upload pipeline and HLS player component are to-be-implemented.

What's in place:
- `/api/endpoints/videos.ts` — full endpoint coverage (upload-url, commit, playback, delete, reactions)
- `MediaFeed` renders video posters with a play overlay
- `Lightbox` has a placeholder for video playback

What's remaining for full parity:
- `features/videos/VideoUploader.tsx` — block-based upload via `@azure/storage-blob` browser bundle; client validation (extension, duration, size); resumable via `sessionStorage` block-complete state; `URL.createObjectURL` for instant local preview with SAS fallback
- `features/videos/VideoPlayer.tsx` — `hls.js` with Safari native-HLS fallback; SAS-expiry recovery pattern mirroring mobile
- Wire both into `EventDetailScreen` and `Lightbox`

Both additions are drop-in against the existing endpoint modules and should not require changes to the rest of the app.

## 8. Real-time

`features/realtime/realtimeClient.ts` manages a singleton `WebPubSubClient`:

- `initRealtime()` called once in `AppLayout` mount effect
- `negotiateRealtime()` returns a short-lived WebSocket URL + client token
- Client auto-reconnects with exponential backoff (SDK default)
- Incoming events invalidate React Query caches:
  - `dm_message_created` → `['thread', threadId, 'messages']`
  - `video_ready` → `['event', eventId, 'videos']`
  - `notification_created` → `['notifications']`

## 9. App Insights (RUM)

`lib/ai.ts` initializes `ApplicationInsights` when `VITE_APPLICATION_INSIGHTS_CONNECTION_STRING` is set. Auto page-view tracking is enabled. Custom events fired today:

- `web_login_success`
- `web_photo_upload_completed`
- `web_qr_printed`
- `web_dm_realtime_connected`

Additional events (`web_video_upload_committed`, `web_playback_sas_recovered`) will be added when video parity ships.

Kusto query for health monitoring:

```kql
customEvents
| where timestamp > ago(24h)
| where name startswith "web_"
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

## 10. Azure config checklist (one-time manual steps)

Before a new environment can work end-to-end:

1. **Entra app registration** (`7db01206-135b-4a34-a4d5-2622d1a888bf`) — add SPA platform redirect URIs for both production (`https://clique-pix.com/auth/callback`) and dev (`http://localhost:5173/auth/callback`); front-channel logout URL `https://clique-pix.com/`. Implicit grant stays unchecked.
2. **APIM CORS** — `apim_policy.xml` in this repo has the `<cors>` block; deploy the policy via Azure Portal (APIM → APIs → All APIs → Policies) or `az apim api policy create`.
3. **Azure Blob Storage CORS** — `stcliquepixprod` → Resource sharing (CORS) → Blob service: origins `https://clique-pix.com` and `http://localhost:5173`, methods `GET PUT HEAD OPTIONS`, headers `*`, exposed headers `*`, max-age `3600`. CLI: `az storage cors add --services b --methods GET PUT HEAD OPTIONS --origins "https://clique-pix.com" "http://localhost:5173" --allowed-headers "*" --exposed-headers "*" --max-age 3600 --account-name stcliquepixprod`.
4. **Front Door** — no changes; CORS passes through.

## 11. Deployment

GitHub Actions workflow `.github/workflows/webapp-deploy.yml` triggers on push/PR to `main` with paths in `webapp/**`. Uses `Azure/static-web-apps-deploy@v1` with `app_location: webapp`, `output_location: dist`, `app_build_command: npm ci && npm run build`. The `AZURE_STATIC_WEB_APPS_API_TOKEN` secret is reused from the previous website-only workflow — the SWA resource is the same.

**PR previews**: each PR gets a unique `<hash>.<region>.azurestaticapps.net` URL. Auth-dependent tests don't work on previews unless the URL is manually added to the Entra SPA redirect list (Microsoft does not support path wildcards). Treat previews as non-auth smoke-test only.

## 12. Local development

```
cd webapp
npm install
npm run dev
```

Vite runs on `http://localhost:5173` with HMR. The dev server hits the **production** API at `https://api.clique-pix.com` — no local backend is required, but CORS on APIM must include `http://localhost:5173` (configured).

## 13. Known limits

1. **Video full parity pending** — see §7.
2. **Signing out on tab close** — `sessionStorage` MSAL cache is per-tab; users must sign in again after closing and reopening. Switch to `localStorage` if beta feedback says this is painful (accepts the XSS risk tradeoff).
3. **No Web Push in v1** — users do not get background notifications in browsers. Real-time updates via Web PubSub only while the tab is open. Bell-badge polls every 60s as a safety net.
4. **PR previews cannot test auth-dependent flows** — see §11.
5. **HEIC on Chrome/Firefox** requires `heic2any` WASM — large files (>30 MB) take seconds to convert in-browser.
6. **Thumbnail cache-busting**: SAS URL signatures change on each refresh, so the browser HTTP cache misses on every load. Acceptable for v1 (thumbnails are ~50 KB).
7. **Safari cross-origin blob download** — handled via `fetch() + URL.createObjectURL`, not naive `<a download>`.
8. **Legacy App Store / Play Store listings** still point at `/privacy.html` and `/terms.html` — the 301 redirects cover this; listings should be updated to `/docs/*` directly as post-launch cleanup.
