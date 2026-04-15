# DEPLOYMENT_STATUS.md — Clique Pix v1

Last updated: 2026-04-15 (Profile Contact Us + legal tile reorder)

## Video v1 Status

**Branch:** `feature/video` — ready for on-device verification, pending merge to `main`

| Phase | Status | Commit |
|---|---|---|
| 1. Database migration (007 — media_type + video columns) | ✅ Applied to production | `fe3e69f` |
| 2. Infrastructure (Log Analytics, ACR Standard, Container Apps Environment+Job, Storage Queue, RBAC, Budget) | ✅ Provisioned in `rg-cliquepix-prod` | `8e569ab`, `343d893` |
| 3. Transcoder container (Dockerfile + Node.js runner + FFmpeg) | ✅ v0.1.2 deployed to `cracliquepix.azurecr.io` | `a6a9930`, `9db5bad` |
| 4. Backend Function endpoints (10 new routes) | ✅ Deployed to `func-cliquepix-fresh` | `552cb60`, `9db5bad` |
| 5. Backend integration test (E2E with real test video) | ✅ All 3 attempts passed after 2 bugs fixed | `9db5bad` |
| 6. Flutter frontend (11 new files, 11 modified) | ✅ Compiles, debug APK builds successfully | `45f5baf` |
| 7. Polish + on-device testing + merge to main | ⏳ In progress — manual testing required before merge | — |

**See also:**
- `docs/VIDEO_ARCHITECTURE_DECISIONS.md` — 8 architecture decisions + 7 product Q&A
- `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` — Azure resources runbook (as-built)
- `docs/CliquePix_Video_Feature_Spec.md` — original generic feature spec
- `docs/VIDEO_V1_TESTING_CHECKLIST.md` — manual on-device testing checklist (Phase 7)

---

## Pre-existing v1 Status (photos, cliques, events, DMs)

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Migration (002_member_joined_notification.sql) | Done | Added `member_joined` to notifications type CHECK constraint (run 2026-03-31) |
| Migration (003_event_deleted_notification.sql) | Done | Added `event_deleted` to notifications type CHECK constraint (run 2026-04-03) |
| Migration (004_user_delete_set_null.sql) | Done | Made `created_by_user_id` / `uploaded_by_user_id` nullable with ON DELETE SET NULL (run 2026-04-03) |
| Shared models (8 files) | Done | User, Clique, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | Code reviewed + 49 issues fixed |
| Auth middleware (JWT via JWKS) | Done | Uses typed errors (UnauthorizedError, NotFoundError) |
| Error handler middleware | Done | Correlation IDs via invocationId |
| Auth functions (verify, getMe, deleteMe) | Done | `deleteMe` cleans up blobs, sole-owner cliques, user record |
| Cliques functions (8 endpoints) | Done | joinClique sends FCM push; `removeMember` endpoint for owner to remove members |
| Events functions (4 endpoints) | Done | Includes `deleteEvent` for organizer-initiated deletion |
| Photos functions (5 endpoints) | Done | Validates via blob properties, async thumbnail gen |
| Reactions functions (2 endpoints) | Done | Static imports, consistent telemetry keys |
| Notifications functions (5 endpoints) | Done | Includes `deleteNotification` and `clearNotifications` |
| Timer functions (3 timers) | Done | Deduplication on expiring notifications |
| Health endpoint | Done | Standard response envelope |
| npm dependencies installed | Done | |

### Flutter Mobile App (Dart)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (pubspec.yaml, analysis_options) | Done | Flutter 3.35.5, Dart 3.9.2 |
| Native scaffolding (Android/iOS) | Done | `flutter create` with org `com.cliquepix`; Android package `com.cliquepix.clique_pix`, iOS bundle ID `com.cliquepix.app` (changed from flutter create default `com.cliquepix.cliquePix`) |
| Design system (colors, gradients, typography, theme) | Done | Dark theme throughout, uses `withValues(alpha:)` (Flutter 3.27+) |
| Constants (endpoints, app constants, environment) | Done | Domain: `clique-pix.com` |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Event-first flow, 4 tabs (Home/Cliques/Notifications/Profile), auth guard with redirect preservation for invite deep links |
| API client (Dio + 3 interceptors) | Done | Auth interceptor uses parent Dio for retry |
| Token storage service | Done | Refresh callback mechanism wired to MSAL |
| Storage service (save to gallery + share + batch download) | Done | Single photo/video save, unified batch download (photos + videos) with progress, share via temp file |
| Deep link service | Done | Host: clique-pix.com, initialized in app.dart via ConsumerStatefulWidget |
| Push notification service | Done | FCM token registration + refresh; foreground display via `flutter_local_notifications`; background/terminated tap navigation; static callback for local notification taps |
| Shared widgets (7 widgets) | Done | Gradient-ringed avatars, dark-themed bottom nav with gradient icons |
| Data models (5 models) | Done | PhotoModel with resilient num/string parsing, EventModel with cliqueName/memberCount |
| Auth feature (MSAL integration) | Done | `msal_auth` 3.3.0, custom API scope, auto-login on startup, MSAL error recovery, dismiss button |
| 5-layer token refresh defense | Done | All layers wired; loginHint threaded through Layer 5 |
| Cliques feature (API, repository, providers, 6 screens) | Done | Dark theme, gradient-bordered cards, gradient-ringed avatars, labeled "Create Clique" FAB, pull-to-refresh + 30s polling on list and detail screens, JoinCliqueScreen with dark theme |
| Events feature (API, repository, providers, 4 screens) | Done | Event-first flow, events home screen, dark-themed event detail with hero header, labeled "Create Event" FAB, `listAllEvents` backend endpoint, event cards show photo + video counts, `Wrap`-based layout handles large system font sizes without overflow |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | `pro_image_editor` for crop/draw/stickers/filters, prominent "Upload to Event" button, step-by-step progress overlay, `uploaded_by_name` in responses, multi-select photo download with progress, debug logging throughout pipeline |
| Notifications feature (API, repository, providers, 1 screen) | Done | Dark theme, colored icon badges, unread/read styling, `member_joined` type with clique navigation |
| Profile feature (1 screen) | Done | Dark theme, gradient profile card, grouped settings with gradient icons, Privacy Policy + Terms of Service open `clique-pix.com` in-app browser via `url_launcher` |
| App entry point (main.dart) | Done | Firebase, timezone, WorkManager, local notifications plugin (top-level), `cliquepix_default` channel creation, Android 13+ permission request, FCM `onMessage` foreground listener, background message handler |
| All API providers wired to ApiClient | Done | No UnimplementedError providers |
| App launcher icon | Done | Clique Pix camera logo at all Android densities |
| Login screen | Done | Dark gradient, animated glowing logo, slide-in animations |
| App-wide dark theme | Done | `AppTheme.dark` applied globally in app.dart; all screens use consistent dark (#0E1525) background with gradient accents |
| Home screen dashboard | Done | State-aware: brand new, has cliques, active events, expired events; How It Works card, clique quick-start chips, active event cards with countdown timers |
| Android manifest | Done | Permissions, App Links, FCM, MSAL BrowserTabActivity |
| iOS Info.plist | Done | Camera/photo permissions, background modes, MSAL URL schemes |
| Firebase config (Android) | Done | `google-services.json` placed in `android/app/` |
| Firebase config (iOS) | Done | `GoogleService-Info.plist` placed in `ios/Runner/` |

### Website (clique-pix.com)

| Component | Status | Notes |
|-----------|--------|-------|
| Landing page (index.html) | Done | Brand design, feature highlights, download CTAs |
| Privacy policy (privacy.html) | Done | Photo + video + DM coverage, 14 sections, Xtend-AI LLC, NC jurisdiction, effective April 13, 2026 |
| Terms of service (terms.html) | Done | Photo + video + DM coverage, 16 sections, effective April 13, 2026 |
| Invite landing page (invite.html) | Done | Dark-themed, platform detection, intent:// for Android, app store buttons, OG meta tags |
| Static Web App config | Done | MIME types for well-known files, security headers, `/invite/*` rewrite to invite.html |
| Well-known files | Done | apple-app-site-association (Team ID: `4ML27KY869`) + assetlinks.json (debug SHA256 fingerprint) |
| Azure Static Web App | Done | `swa-cliquepix-prod`, Free tier, redeployed 2026-03-31 |
| Custom domains | Done | `clique-pix.com` (apex) + `www.clique-pix.com`, managed SSL |

### Documentation

| Component | Status | Notes |
|-----------|--------|-------|
| .gitignore | Done | Firebase admin SDK key pattern added |
| ARCHITECTURE.md | Done | Domain corrected to clique-pix.com |
| PRD.md | Done | |
| CLAUDE.md | Done | Domain corrected, PostgreSQL updated to pg-cliquepixdb |
| ENTRA_REFRESH_TOKEN_WORKAROUND.md | Done | |

---

## Azure Infrastructure Status

### All Resources (in `rg-cliquepix-prod`)

| Resource | Name | Location | Status |
|----------|------|----------|--------|
| Resource Group | `rg-cliquepix-prod` | eastus | Ready |
| Log Analytics | `log-cliquepix-prod` | eastus | Ready |
| Application Insights | `appi-cliquepix-prod` | eastus | Ready (workspace-based) |
| Function App | `func-cliquepix-fresh` | eastus | Ready — 39 functions deployed (incl. 7 DM endpoints) |
| Storage Account | `stcliquepixprod` | eastus | Ready — `photos` container, blob public access disabled |
| PostgreSQL | `pg-cliquepixdb` | eastus2 | Ready — v18, `cliquepix` DB with 10 tables (incl. `event_dm_threads`, `event_dm_messages`) |
| Key Vault | `kv-cliquepix-prod` | eastus | Ready — `pg-connection-string` + `fcm-credentials` + `web-pubsub-connection-string` stored |
| API Management | `apim-cliquepix-002` | eastus | Ready — Developer SKU, API imported, rate limiting configured |
| Front Door | `fd-cliquepix-prod` | global | Ready — Standard SKU (no WAF) |
| Static Web App | `swa-cliquepix-prod` | eastus2 | Ready — clique-pix.com + www |
| DNS Zone | `clique-pix.com` | global | Ready — api CNAME, apex ALIAS, www CNAME, TXT validation |
| Web PubSub | `wps-cliquepix-prod` | eastus | Ready — Standard S1, hub: `cliquepix` |
| Entra External ID | `cliquepix.onmicrosoft.com` | — | Ready — app registered, 3 identity providers |

### Deleted Resources

| Resource | Name | Reason |
|----------|------|--------|
| PostgreSQL | `pg-cliquepix` | Replaced by `pg-cliquepixdb` (v18) |

### RBAC Role Assignments (Function App managed identity)

| Role | Scope | Status |
|------|-------|--------|
| Storage Blob Data Contributor | `stcliquepixprod` | Assigned |
| Storage Blob Delegator | `stcliquepixprod` | Assigned |
| Key Vault Secrets User | `kv-cliquepix-prod` | Assigned |

### Traffic Path (verified working)

```
Flutter App → Front Door (fd-cliquepix-prod) → APIM (apim-cliquepix-002) → Azure Functions (func-cliquepix-fresh) → PostgreSQL / Blob Storage
```

Health endpoint confirmed at:
- `https://func-cliquepix-fresh.azurewebsites.net/api/health`
- `https://apim-cliquepix-002.azure-api.net/api/health`
- `https://cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net/api/health`
- `https://api.clique-pix.com/api/health`

### APIM Rate Limiting Policies

| Scope | Limit | Operation |
|-------|-------|-----------|
| Global (all operations) | 60 requests/min per IP | API-level policy |
| Upload URL | 10 requests/min per IP | `POST /events/{eventId}/photos/upload-url` |
| Auth verify | 5 requests/min per IP | `POST /auth/verify` |

### Function App Settings

| Setting | Value | Source |
|---------|-------|--------|
| `PG_CONNECTION_STRING` | Key Vault reference | `kv-cliquepix-prod/pg-connection-string` |
| `FCM_CREDENTIALS` | Key Vault reference | `kv-cliquepix-prod/fcm-credentials` |
| `STORAGE_ACCOUNT_NAME` | `stcliquepixprod` | Direct |
| `ENTRA_TENANT_ID` | `27748e01-d49f-4f0b-b78f-b97c16be69dc` | Direct (CIAM tenant) |
| `ENTRA_CLIENT_ID` | `7db01206-135b-4a34-a4d5-2622d1a888bf` | Direct |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | Direct |
| `NODE_ENV` | `production` | Direct |

### Entra External ID Configuration

| Component | Status | Details |
|-----------|--------|---------|
| CIAM Tenant | `cliquepix.onmicrosoft.com` | Tenant ID: `27748e01-d49f-4f0b-b78f-b97c16be69dc` |
| App Registration | `Clique Pix` | Client ID: `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Redirect URI (Android debug) | Configured | `msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D` |
| Redirect URI (iOS) | Configured | `msauth.com.cliquepix.app://auth` (auto-generated from Bundle ID `com.cliquepix.app`) |
| Application ID URI | Configured | `api://7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Exposed API Scope | Configured | `access_as_user` — required for MSAL to return app-scoped access token |
| Email OTP | Enabled | Primary sign-in method |
| Google Identity Provider | Configured | OAuth client via Google Cloud Console |
| Apple Identity Provider | Configured | Service ID: `com.cliquepix.app.service`, Key ID: `4NYXZNV9VD` |
| User Flow | `SignUpSignIn` | Email OTP + Google + Apple, Clique Pix app associated |

### Firebase Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Firebase Project | `Clique Pix` | Project ID: `clique-pix-d7fde` |
| Cloud Messaging (FCM) | Enabled | V1 API |
| Android app | Registered | Package: `com.cliquepix.clique_pix` |
| iOS app | Registered | Bundle ID: `com.cliquepix.app` |
| Service account key | Stored | Key Vault: `kv-cliquepix-prod/fcm-credentials` |
| google-services.json | Placed | `app/android/app/google-services.json` (gitignored) |
| GoogleService-Info.plist | Placed | `app/ios/Runner/GoogleService-Info.plist` (gitignored) |

### Google OAuth Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Google Cloud Project | `Clique Pix` | |
| OAuth consent screen | Configured | External, Testing mode |
| Authorized domains | Set | `ciamlogin.com`, `microsoftonline.com`, `clique-pix.com` |
| OAuth client | Web application | For Entra federation (server-to-server) |
| App domain URLs | Set | Home: `https://clique-pix.com`, Privacy: `/privacy.html`, Terms: `/terms.html` |

### Apple Sign In Configuration

| Component | Status | Details |
|-----------|--------|---------|
| App ID | `com.cliquepix.app` | Team ID: `4ML27KY869` |
| Services ID | `com.cliquepix.app.service` | Sign In with Apple configured with CIAM domains |
| Key | `CliquePix Sign In` | Key ID: `4NYXZNV9VD` |
| Client secret (.p8) | Active | **Renewal required: September 2026** |

### Configuration Notes

| Setting | Value | Notes |
|---------|-------|-------|
| `allowSharedKeyAccess` | `true` | Required by Azure Functions runtime for AzureWebJobsStorage |
| `allowBlobPublicAccess` | `false` | No anonymous blob access |
| Storage SKU | `Standard_GZRS` | Changed from RAGZRS (not supported by Consumption plan) |
| Function App plan | Consumption (Linux) | EastUSLinuxDynamicPlan |
| Deployment method | Run-from-package (blob SAS) | Windows→Linux zip requires Python zipfile for forward slashes |
| Front Door endpoint | `cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net` | |
| Custom domain (API) | `api.clique-pix.com` | CNAME → Front Door, managed certificate |
| Custom domain (website) | `clique-pix.com` + `www.clique-pix.com` | ALIAS/CNAME → Static Web App |
| Android package name | `com.cliquepix.clique_pix` | Generated by `flutter create --org com.cliquepix` |
| iOS bundle ID | `com.cliquepix.app` | |
| MSAL package | `msal_auth: ^3.3.0` | Replaced `msal_flutter` (v1 embedding incompatible with Flutter 3.35) |
| MSAL scopes | `['api://7db01206.../access_as_user']` | Custom API scope only; OIDC scopes added implicitly by MSAL |
| CIAM issuer format | `https://{tenantId}.ciamlogin.com/{tenantId}/v2.0` | Tenant ID as subdomain (NOT tenant name) |
| CIAM JWKS URI | `https://cliquepix.ciamlogin.com/{tenantId}/discovery/v2.0/keys` | Tenant name as subdomain |
| API base URL (dev + prod) | `https://api.clique-pix.com` | Front Door custom domain; `fd-cliquepix-prod.azurefd.net` is NOT a valid hostname |

---

## Code Review Summary (2026-03-25)

49 issues found and fixed across 7 commits:

| Severity | Count | Examples |
|----------|-------|---------|
| Critical | 13 | Blob path prefix, SAS permissions, TLS validation, telemetry init, auth wiring |
| High | 18 | Missing telemetry events, image compression, blob upload streaming, reaction IDs |
| Medium | 12 | Feed polling, notification dedup, error interceptor, HEIC detection |
| Low | 5 | Health envelope, deprecated withOpacity, correlation IDs, barrel exports |

---

## Authentication Fix Summary (2026-03-26)

Four bugs were found and fixed in the MSAL → Backend authentication chain:

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. No custom API scope | MSAL returned a Microsoft Graph token (wrong signing keys) when only OIDC scopes were requested | Exposed `api://clientId/access_as_user` scope in Entra; MSAL now requests only this scope |
| 2. Backend issuer mismatch | Backend validated issuer as `cliquepix.ciamlogin.com/...` but CIAM tokens use `{tenantId}.ciamlogin.com/...` | Changed issuer to `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0` |
| 3. Wrong dev API base URL | `fd-cliquepix-prod.azurefd.net` returns 404 (Azure resource name, not actual endpoint) | Changed to `api.clique-pix.com` for both dev and prod |
| 4. `offline_access` declined | CIAM tenants decline `offline_access` without admin consent | Removed from scopes; MSAL handles refresh tokens internally |

**Key learning:** For Entra External ID (CIAM), a mobile app calling a custom backend API **must** expose an API scope (`Expose an API` → `Add a scope`). Without it, `result.accessToken` is a Microsoft Graph token signed by Graph keys — not the CIAM tenant's keys — causing `invalid signature` on backend verification. OIDC scopes (`openid`, `profile`, `email`) must NOT be requested explicitly; MSAL adds them implicitly. Mixing API scopes with OIDC scopes causes `MsalDeclinedScopeException`.

---

## Photo Upload Pipeline Fix Summary (2026-03-26)

The photo upload pipeline appeared completely broken — photos never appeared after capture. Root cause: a **double-pop navigation bug** in the ProImageEditor v5.1.4 integration.

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. ProImageEditor double-pop | v5.x's `doneEditing()` calls `onImageEditingComplete` then immediately calls `onCloseEditor`. Having `Navigator.pop()` in both callbacks double-popped: removed editor + CameraCaptureScreen. User never saw the preview/Upload button. | Moved `Navigator.pop()` to `onCloseEditor` only; `onImageEditingComplete` saves bytes to closure variable without popping |
| 2. BlobUploadService Dio config | `Content-Type` set in headers map instead of `Options.contentType`; manual `Content-Length` could conflict with Dio auto-calc; no `responseType: ResponseType.bytes` for Azure XML errors | Set `contentType: 'image/jpeg'` on Options, `responseType: ResponseType.bytes`, removed manual Content-Length |

**Key learning:** ProImageEditor v5.x's `doneEditing()` (main_editor.dart:1514-1566) always calls `onCloseEditor` after `onImageEditingComplete` completes. The correct pattern is: save data in `onImageEditingComplete` (no pop), then pop in `onCloseEditor`. This matches the official Firebase/Supabase example in the ProImageEditor package.

---

## QR Invite Flow Fix + Clique Join Notifications (2026-03-31)

### Problem 1: QR Code invite returns 404

Scanning a clique invite QR code navigated to `https://clique-pix.com/invite/{code}` which returned a 404 from Azure because the Static Web App had no route or page for `/invite/*` paths.

**Root causes and fixes:**

| Issue | Fix |
|-------|-----|
| No web page for `/invite/*` paths | Created `website/invite.html` — branded dark-themed landing page with platform detection, `intent://` URI for Android, app store buttons |
| No SWA rewrite rule | Added `/invite/*` → `invite.html` rewrite in `staticwebapp.config.json` (must come before `.well-known` routes) |
| `DeepLinkService` never initialized | Converted `app.dart` to `ConsumerStatefulWidget`, call `initialize(router)` in `initState` |
| Invite route bypassed auth check | Removed `isInviteRoute` exemption from GoRouter redirect; added `?redirect=` query param to preserve invite URL through login flow |
| `.well-known` placeholders | Replaced `TEAM_ID` → `4ML27KY869` in AASA; replaced SHA256 placeholder with debug keystore fingerprint in assetlinks.json |
| `JoinCliqueScreen` light theme | Restyled with dark background, gradient heading, aqua accents, dark TextField |

**Website redeployed** to `swa-cliquepix-prod` via SWA CLI. Invite URLs now return 200 with branded page.

### Problem 2: Owner not notified when someone joins clique

| Issue | Fix |
|-------|-----|
| No `member_joined` notification type | Created migration `002_member_joined_notification.sql` — ALTERed CHECK constraint on `notifications.type` |
| Backend didn't send push on join | Added FCM push + notification record creation to `joinClique()` in `cliques.ts`; replicates exact pattern from `photos.ts` |
| `NotificationType` model missing type | Added `'member_joined'` to union type in `notification.ts` |
| Client didn't render `member_joined` | Added icon/color case (person_add + aqua/violet), title case ("New Member"), and clique navigation in `_NotificationTile.onTap` |
| No FCM token registration | Created `PushNotificationService` — requests permission, gets FCM token, sends to `POST /api/push-tokens`, listens for token refresh |
| No auto-refresh on clique screens | Added `WidgetsBindingObserver` + `RefreshIndicator` + `Timer.periodic(30s)` polling to both `CliquesListScreen` and `CliqueDetailScreen` |

**Backend redeployed** to `func-cliquepix-fresh`. Migration run against `pg-cliquepixdb`.

**Known issue:** Push notifications not yet confirmed working end-to-end on device. FCM token registration and backend push logic are implemented but need further debugging.

### Problem 3: Global light theme overriding dark screens

`app.dart` used `AppTheme.light` — a Material 3 light theme that overrode per-widget dark styling on some screens (notably `CreateCliqueScreen`).

**Fix:** Created `AppTheme.dark` in `app_theme.dart` with dark defaults matching the app's visual design (dark scaffold, dark AppBar, dark InputDecoration, aqua accents). Switched `app.dart` to `theme: AppTheme.dark`.

---

## Remaining Tasks

### Completed

| Task | Status | Notes |
|------|--------|-------|
| MSAL authentication flow | Done | End-to-end working: MSAL → custom API scope → backend JWT verification → user upsert |
| Event-first UX flow | Done | 4 tabs (Events/Cliques/Notifications/Profile), event creation with inline clique picker |
| Dark theme across all screens | Done | Cliques detail, event detail, camera capture, notifications, profile — all consistent |
| Photo editor integration | Done | `pro_image_editor` ^5.1.4 — crop, draw, stickers, emoji, filters, text |
| Auth error recovery | Done | Auto-login on startup, MSAL cache reset on failure, error dismiss button |
| New app icon/logo | Done | Generated via `flutter_launcher_icons` from 1024x1024 source |
| Backend: `listAllEvents` endpoint | Done | `GET /api/events` — returns all events across user's cliques with clique name/member count |
| Backend: `uploaded_by_name` in photos | Done | `listPhotos` JOINs users table; `PhotoWithUrls` includes uploader display name |
| PhotoModel resilient parsing | Done | Handles PostgreSQL bigint-as-string (file_size_bytes) without type cast errors |
| ProImageEditor double-pop fix | Done | v5.x calls `onCloseEditor` after `onImageEditingComplete`; moved `Navigator.pop()` to `onCloseEditor` only to prevent double-pop that skipped preview/upload screen |
| BlobUploadService Dio fix | Done | Set `contentType` on Options (not in headers), `responseType: ResponseType.bytes`, removed manual Content-Length |
| Upload pipeline debug logging | Done | `[CliquePix]` prefixed `debugPrint` at every step for `adb logcat` diagnosis |

### Recently Completed (2026-03-31)

| Task | Status | Notes |
|------|--------|-------|
| Well-known files: real values | Done | Apple Team ID `4ML27KY869` in AASA, debug SHA256 in assetlinks.json |
| Invite landing page | Done | `website/invite.html` with SWA rewrite rule, deployed to `swa-cliquepix-prod` |
| Deep link service initialization | Done | `DeepLinkService.initialize(router)` called in `app.dart` |
| Auth gate for invite routes | Done | Unauthenticated invite URLs redirect to login with `?redirect=` preservation |
| Global dark theme | Done | Created `AppTheme.dark`, switched `app.dart` from `AppTheme.light` |
| Home screen dashboard | Done | 4-state contextual dashboard, How It Works card, clique chips, active event cards |
| Back buttons on full-screen routes | Done | Event detail, camera capture, photo detail all have explicit back navigation |
| Clique join push notification (backend) | Done | `joinClique()` sends FCM to existing members, creates `member_joined` notification records |
| DB migration: member_joined type | Done | `002_member_joined_notification.sql` run against `pg-cliquepixdb` |
| FCM token registration (client) | Done | `PushNotificationService` gets token, registers with backend, listens for refresh |
| Clique screens refresh | Done | Pull-to-refresh + app-resume + 30s polling on CliquesListScreen and CliqueDetailScreen |
| JoinCliqueScreen dark theme | Done | Gradient heading, aqua accents, dark TextField |
| Dark theme consistency | Done | EventsListScreen, CreateCliqueScreen, InviteScreen all restyled |

### Recently Completed (2026-04-01)

| Task | Status | Notes |
|------|--------|-------|
| Clique member management: owner remove | Done | `DELETE /api/cliques/{cliqueId}/members/{userId}` — owner-only, validates role, prevents self-removal |
| Clique member management: leave/delete UI | Done | "Leave Clique" button (members), "Delete Clique" button (sole owner), confirmation dialogs |
| Clique member management: tappable removal | Done | Owner sees remove icon on non-owner members; tap shows confirmation dialog |
| Graceful 404 on member removal | Done | When removed user's screen refreshes, detects 404 DioException and navigates to `/cliques` with SnackBar instead of showing error |
| State invalidation: member count | Done | Uses `membersAsync.valueOrNull?.length` for live count; avoids full-screen loading flash |
| Frontend API: `removeMember` | Done | Endpoint constant, CliquesApi method, CliquesRepository method |
| Push notification: foreground display | Done | `onMessage` listener in `main.dart` shows heads-up banner via `flutter_local_notifications.show()` |
| Push notification: channel creation | Done | `cliquepix_default` channel with `Importance.high` created in `main.dart` at startup |
| Push notification: Android 13+ permission | Done | `requestNotificationsPermission()` via Android-specific plugin API |
| Push notification: background tap | Done | `onMessageOpenedApp` → navigates to clique/event via GoRouter |
| Push notification: terminated tap | Done | `getInitialMessage()` → delayed navigation after router init |
| Push notification: local tap routing | Done | Static callback bridges `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter |
| Push notification: in-app list refresh | Done | `onMessage` invalidates `notificationsListProvider` for immediate update |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 27 functions |

### Recently Completed (2026-04-04)

| Task | Status | Notes |
|------|--------|-------|
| Post-creation invite flow | Done | When creating event with NEW clique, modal bottom sheet prompts "Invite Friends" or "Skip for Now" on Event Detail screen. Uses `GoRouter.extra` to pass cliqueId/cliqueName (one-time, not restorable from URL) |
| Top-level routes for cross-shell navigation | Done | Added `/view-clique/:cliqueId` and `/invite-to-clique/:cliqueId` outside `StatefulShellRoute` — fixes back-navigation when pushing to shell-internal routes from Event Detail |
| Clique navigation from event detail | Done | AppBar group icon (always visible) + tappable clique name with chevron in hero section — both use top-level `/view-clique/` route for clean back-navigation |

### Recently Completed (2026-04-03)

| Task | Status | Notes |
|------|--------|-------|
| Event deletion: backend endpoint | Done | `DELETE /api/events/{eventId}` — creator-only auth, blob cleanup before cascade DB delete, push + in-app notification to clique members |
| Event deletion: frontend UI | Done | Delete icon in AppBar (organizer only), dark-themed confirmation dialog, post-delete navigation to events list with SnackBar |
| Event deletion: API/repository layer | Done | `deleteEvent()` method in EventsApi and EventsRepository |
| Photo card name readability fix | Done | Uploader name and timestamp text overridden to white for dark card background (#162033) — was invisible dark navy (#0F172A) |
| Multi-select media download: selection state | Done | `MediaSelectionNotifier` + `mediaSelectionProvider` (family by eventId) in photos_providers.dart — unified for photos + videos |
| Multi-select media download: card UI | Done | Circular checkbox overlay on photo and video cards (aqua when selected), tap toggles selection; processing/failed videos excluded from selection |
| Multi-select media download: feed UI | Done | Selection toolbar with Select All / Deselect All + Cancel; download action bar with dynamic label ("Download 3 Photos" / "Download 2 Videos" / "Download 5 Items") |
| Multi-select media download: batch save | Done | Photos via `savePhotoToGallery()`, videos via `saveVideoToGallery()` (MP4 fallback URL) — sequential with combined progress, continues past individual failures |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Clique screens: refresh button | Done | Refresh icon in AppBar on both CliqueDetailScreen and CliquesListScreen — calls existing `_refresh()` / `cliquesListProvider.notifier.refresh()` |
| DB migration: `event_deleted` notification type | Done | Migration `003_event_deleted_notification.sql` — added `event_deleted` to notifications CHECK constraint |
| Event creator name: backend queries | Done | `getEvent`, `listEvents`, `listAllEvents` now JOIN `users` table, return `created_by_name` |
| Event creator name: frontend model | Done | Added `createdByName` optional field to `EventModel`, parsed from `created_by_name` |
| Event creator name: UI display | Done | "Created by {name}" row with person icon in event detail hero header |
| Backend redeployed (2nd) | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Notification clear/delete: backend endpoints | Done | `DELETE /api/notifications/{id}` (single) + `DELETE /api/notifications` (clear all) with ownership verification |
| Notification clear/delete: API/repository | Done | `deleteNotification()` + `clearAll()` in notifications_api.dart and notifications_repository.dart |
| Notification clear/delete: UI | Done | Clear All icon in AppBar with confirmation dialog; swipe-to-dismiss (Dismissible) on each notification tile |
| Backend redeployed (3rd) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 31 functions |
| Copy user ID button | Done | User ID displayed on profile card with copy icon, copies to clipboard with SnackBar |
| Delete account: backend endpoint | Done | `DELETE /api/users/me` — cleans up sole-owner cliques + blobs, deletes user photos + blobs, deletes user record |
| Delete account: DB migration 004 | Done | `created_by_user_id` and `uploaded_by_user_id` made nullable with ON DELETE SET NULL on cliques, events, photos |
| Delete account: auth layer | Done | `deleteAccount()` threaded through AuthApi → AuthRepository → AuthNotifier with local cleanup |
| Delete account: profile UI | Done | Red "Delete Account" tile with confirmation dialog; GoRouter auto-redirects to login on success |
| Backend redeployed (4th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 32 functions |
| DM: Azure Web PubSub provisioned | Done | `wps-cliquepix-prod` Standard S1, connection string in Key Vault, Function App setting configured |
| DM: database migration 005 | Done | `event_dm_threads` + `event_dm_messages` tables with indexes, CHECK constraints, CASCADE from events |
| DM: Web PubSub service | Done | `webPubSubService.ts` — token negotiation, `sendToUser` for direct user-targeted delivery (switched from thread-scoped groups) |
| DM: backend endpoints (7) | Done | createOrGetThread, listThreads, getThread, listMessages, sendMessage (rate limited), markRead, negotiate |
| DM: backend models | Done | `dmThread.ts` — DmThread + DmMessage TypeScript interfaces |
| DM: timer integration | Done | DM threads marked read-only in `cleanupExpired` timer, then hard-deleted with event via CASCADE |
| DM: clique removal integration | Done | `removeMember` + `leaveClique` mark affected DM threads as read-only |
| DM: Flutter models | Done | `DmThreadModel` + `DmMessageModel` with fromJson factories |
| DM: Flutter API + repository | Done | `dm_api.dart` + `dm_repository.dart` — 7 methods matching backend |
| DM: Flutter realtime service | Done | `dm_realtime_service.dart` — WebSocket connection with auto-reconnect (exponential backoff), re-negotiates fresh URL on reconnect |
| DM: Flutter providers + routing | Done | Riverpod providers, 3 routes under `/events/:eventId/` (dm-threads, dm/new, dm/:threadId) |
| DM: thread list screen | Done | Dark-themed list with unread indicators, "New Message" FAB, empty state |
| DM: chat screen | Done | Message bubbles (gradient for sent, dark for received), composer, read-only banner |
| DM: member picker screen | Done | Lists clique members for starting new DMs |
| DM: event detail entry points | Done | Messages icon in AppBar + prominent "Messages" button below "Add Photo" |
| DM: FCM push tap routing | Done | `dm_message` type navigates to `/events/{eventId}/dm/{threadId}` |
| DM: debug logging | Done | `[CliquePix DM]` logs for eventId, API response, thread count |
| Backend redeployed (5th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 39 functions |
| Fix: Sign out not working | Done | Missing `await`, unprotected cleanup, stale PCA instance — all three fixed with defense-in-depth (try/catch + try/finally + `_pca = null`) |
| Fix: Welcome screen UI | Done | Hide redundant FAB in brand-new state, brighten helper text (0.3→0.55), "Add Your Crew"→"Add Your Clique" |
| Fix: DM real-time delivery | Done | Switched from group-based (`sendToAll`) to user-targeted (`sendToUser`) delivery; fixed WebSocket reconnection to re-negotiate fresh URL |
| Backend redeployed (6th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — DM sendToUser fix |
| Fix: Sign-out browser session | Done | Added `browser_sign_out_enabled: true` to `msal_config.json` + `Prompt.login` on `acquireToken` — clears Google session cookies on sign-out, forces re-authentication on sign-in |

### Recently Completed (2026-04-13)

| Task | Status | Notes |
|------|--------|-------|
| Fix: iOS MSAL auth loop | Done | Three root causes: (1) no iOS platform registered in Azure Entra, (2) Info.plist URL scheme `msauth.com.cliquepix.app` didn't match bundle ID, (3) missing keychain entitlements (`com.microsoft.adalcache`). Errors were silently swallowed by `auth_providers.dart` catch block. |
| iOS bundle ID reconciliation | Done | Changed Xcode bundle ID from `com.cliquepix.cliquePix` (flutter create default) to `com.cliquepix.app` to match Apple App ID, Firebase iOS, and Apple Sign In config. Updated Azure Entra iOS platform accordingly. |
| Info.plist URL scheme fix | Done | Changed from hardcoded `msauth.com.cliquepix.app` to `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` — auto-resolves at build time |
| Runner.entitlements created | Done | Keychain group `$(AppIdentifierPrefix)com.microsoft.adalcache` for MSAL token caching |
| iOS deployment target bump | Done | 13.0 → 15.0 (required by `firebase_core` v4 and `workmanager_apple`) |
| Firebase packages upgraded | Done | `firebase_core` 2.x → 4.7.0, `firebase_messaging` 14.x → 16.2.0 (old versions incompatible with Xcode 26.2), `share_plus` 9.x → 12.x (dependency conflict with new firebase_core) |
| iOS code signing configured | Done | `DEVELOPMENT_TEAM = 4ML27KY869`, `CODE_SIGN_STYLE = Automatic` on all Runner build configs |
| iOS on-device verification | Done | App builds, installs, and authenticates successfully on physical iPhone (iOS 26.3.1) |

### Recently Completed (2026-04-15)

| Task | Status | Notes |
|------|--------|-------|
| Profile: remove "View Licenses" from About dialog | Done | Replaced Flutter's built-in `showAboutDialog()` (which always injects a VIEW LICENSES button) with a custom `showDialog` + `AlertDialog` containing only a Close action. Title, version, and legalese text preserved. `profile_screen.dart:145-166` |
| Cliques list: remove "+ Create Clique" FAB | Done | Deleted the always-visible gradient FAB from `CliquesListScreen` to eliminate duplication with the empty-state card's "Create Clique" button. Reduced list bottom padding from 100 → 24 now that the FAB no longer needs clearance. Users with existing cliques still reach Create Clique via the Home tab's "+ New Clique" quick-start chip. `cliques_list_screen.dart:135` |
| Event Detail: add 4-tab bottom nav | Done | Event Detail (`/events/:eventId`) previously had no way to jump directly to Home / Cliques / Notifications / Profile — only a back arrow. Extracted the shell's nav bar into a shared `AppBottomNav` widget (`app/lib/widgets/app_bottom_nav.dart`), refactored `ShellScreen` to use it (pixel-identical), and added `bottomNavigationBar: AppBottomNav(...)` to `EventDetailScreen`'s Scaffold. Taps use `context.go('/events' \| '/cliques' \| '/notifications' \| '/profile')` — go_router's `StatefulShellRoute` activates the correct branch cleanly. `selectedIndex: 0` (Home highlighted) since events live under `/events`. Zero routing changes, zero cross-branch push concerns. Full-screen children (camera, photo detail, video capture/upload/player, DM list/chat) remain without the nav. Rejected alternative of moving `/events/:eventId` into the Home shell branch due to go_router 14 cross-branch `push` ambiguity from `events_list_screen.dart:137` and notification tap handlers. `event_detail_screen.dart:29-62`, `shell_screen.dart`, `app_bottom_nav.dart` (new) |
| Profile: reorder legal tiles, add Contact Us | Done | First settings group reordered to `About Clique Pix → Terms of Service → Privacy Policy → Contact Us`. Gradient pairs reassigned so the brand rainbow cascade still flows top-to-bottom (aqua→deep, deep→violet, violet→pink, pink→aqua). New Contact Us tile opens a dark-themed dialog (matching Sign Out / Delete Account styling) showing `support@xtend-ai.com` in a `SelectableText` with two actions: **Copy Email** (Clipboard + "Email copied!" floating snackbar, mirroring the existing user-ID copy pattern) and **Send Email** (launches `mailto:support@xtend-ai.com?subject=Clique%20Pix%20Support` via `LaunchMode.externalApplication`). File-level `_supportEmail` const prevents typo drift across the three use sites. Android manifest `<queries>` block extended with `SENDTO` + `mailto` intent — **required** for Android 11+ package visibility, else `launchUrl` silently no-ops. iOS `LSApplicationQueriesSchemes` left unchanged (non-blocking since `canLaunchUrl` is not used). `profile_screen.dart:8,141-237`, `AndroidManifest.xml:98-111`. |

### Not Started

| Task | Status | Notes |
|------|--------|-------|
| APIM: X-Azure-FDID header validation | Not done | Restrict APIM to Front Door traffic only |
| Google OAuth: add second redirect URI | Not done | May need tenant-ID-format URI |
| Release signing key | Not done | Needed for production APK and Play Store; assetlinks.json must be updated with release SHA256 |
| App Store / Play Store submission | Not done | |
| iOS Associated Domains entitlement | Not done | Requires Xcode on Mac: Signing & Capabilities → `applinks:clique-pix.com` |
| Push notification end-to-end verification | In progress | Full pipeline implemented (backend FCM send confirmed via App Insights, client foreground/background/terminated handlers, channel creation, Android 13+ permission). Needs on-device verification. |

### End-to-End Validation

| Step | Status |
|------|--------|
| 1. Sign up / sign in | Done (2026-03-26) |
| 2. Create a Clique | Done (2026-03-26) |
| 3. Generate invite link/QR | Done (2026-03-31) — QR code encodes `https://clique-pix.com/invite/{code}` |
| 4. Join Clique via invite (QR scan) | Done (2026-03-31) — invite landing page loads (no more 404), join succeeds, joiner appears in clique |
| 5. Create Event (24h/3d/7d) | Done (2026-03-26) |
| 6. Capture photo in-app | Done (2026-03-26) — photo confirmed in database |
| 7. Upload photo (compress → SAS → blob → confirm) | In progress — double-pop bug fixed (user never saw Upload button); Dio config fixed; needs retest |
| 8. See photo in feed | In progress — type cast bug fixed, needs retest after upload pipeline fix |
| 9. React to photo | Not tested |
| 10. Save photo to device | Not tested |
| 11. Share photo externally | Not tested |
| 12. Receive push notification (clique join) | In progress — backend sends FCM successfully (confirmed via App Insights telemetry), client has foreground/background/terminated handlers + notification channel + Android 13+ permission. Needs on-device verification. |
| 13. Auto-deletion after expiry | Not tested |
| 14. Graceful re-login (Layer 5) | Not tested |
| 15. Owner sees new member (auto-refresh) | Partial — pull-to-refresh works, 30s polling implemented, but auto-refresh not confirmed working on device |
| 16. Owner removes member from clique | Done (2026-04-01) — owner taps member → confirm dialog → member removed → list refreshes |
| 17. Member leaves clique | Done (2026-04-01) — member taps "Leave Clique" → confirm → navigates to cliques list |
| 18. Removed member graceful redirect | Done (2026-04-01) — 404 detection auto-navigates removed user back to cliques list with SnackBar |
| 19. Event organizer deletes event | Not tested — delete icon visible to creator, confirmation dialog, blob cleanup + cascade delete |
| 20. Non-organizer cannot delete event | Not tested — delete icon should not appear for non-creators |
| 21. Multi-select media download | Not tested — enter selection mode, select photos + videos, download with progress bar, dynamic label |
| 22. Photo card uploader name readable | Not tested — white text on dark card background |
| 23. Event creator name displayed | Not tested — "Created by {name}" visible on event detail screen |
| 24. Clear all notifications | Not tested — tap trash sweep icon in AppBar → confirm → all notifications cleared |
| 25. Swipe to dismiss notification | Not tested — swipe left on individual notification → red background → deleted |
| 26. Copy user ID from profile | Not tested — tap copy icon next to UUID → clipboard |
| 27. Delete account | Not tested — tap Delete Account → confirm → account removed → redirected to login |
