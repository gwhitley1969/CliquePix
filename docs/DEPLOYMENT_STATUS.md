# DEPLOYMENT_STATUS.md — Clique Pix v1

Last updated: 2026-04-01

---

## Code Implementation Status

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Migration (002_member_joined_notification.sql) | Done | Added `member_joined` to notifications type CHECK constraint (run 2026-03-31) |
| Shared models (8 files) | Done | User, Circle, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | Code reviewed + 49 issues fixed |
| Auth middleware (JWT via JWKS) | Done | Uses typed errors (UnauthorizedError, NotFoundError) |
| Error handler middleware | Done | Correlation IDs via invocationId |
| Auth functions (verify, getMe) | Done | |
| Circles functions (8 endpoints) | Done | joinCircle sends FCM push; `removeMember` endpoint for owner to remove members |
| Events functions (3 endpoints) | Done | |
| Photos functions (5 endpoints) | Done | Validates via blob properties, async thumbnail gen |
| Reactions functions (2 endpoints) | Done | Static imports, consistent telemetry keys |
| Notifications functions (3 endpoints) | Done | |
| Timer functions (3 timers) | Done | Deduplication on expiring notifications |
| Health endpoint | Done | Standard response envelope |
| npm dependencies installed | Done | |

### Flutter Mobile App (Dart)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (pubspec.yaml, analysis_options) | Done | Flutter 3.35.5, Dart 3.9.2 |
| Native scaffolding (Android/iOS) | Done | `flutter create` with org `com.cliquepix`, package `com.cliquepix.clique_pix` |
| Design system (colors, gradients, typography, theme) | Done | Dark theme throughout, uses `withValues(alpha:)` (Flutter 3.27+) |
| Constants (endpoints, app constants, environment) | Done | Domain: `clique-pix.com` |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Event-first flow, 4 tabs (Home/Circles/Notifications/Profile), auth guard with redirect preservation for invite deep links |
| API client (Dio + 3 interceptors) | Done | Auth interceptor uses parent Dio for retry |
| Token storage service | Done | Refresh callback mechanism wired to MSAL |
| Storage service (save to gallery + share download) | Done | Downloads to temp file before sharing |
| Deep link service | Done | Host: clique-pix.com, initialized in app.dart via ConsumerStatefulWidget |
| Push notification service | Done | FCM token registration + refresh; foreground display via `flutter_local_notifications`; background/terminated tap navigation; static callback for local notification taps |
| Shared widgets (7 widgets) | Done | Gradient-ringed avatars, dark-themed bottom nav with gradient icons |
| Data models (5 models) | Done | PhotoModel with resilient num/string parsing, EventModel with circleName/memberCount |
| Auth feature (MSAL integration) | Done | `msal_auth` 3.3.0, custom API scope, auto-login on startup, MSAL error recovery, dismiss button |
| 5-layer token refresh defense | Done | All layers wired; loginHint threaded through Layer 5 |
| Circles feature (API, repository, providers, 6 screens) | Done | Dark theme, gradient-bordered cards, gradient-ringed avatars, labeled "Create Circle" FAB, pull-to-refresh + 30s polling on list and detail screens, JoinCircleScreen with dark theme |
| Events feature (API, repository, providers, 4 screens) | Done | Event-first flow, events home screen, dark-themed event detail with hero header, labeled "Create Event" FAB, `listAllEvents` backend endpoint |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | `pro_image_editor` for crop/draw/stickers/filters, prominent "Upload to Event" button, step-by-step progress overlay, `uploaded_by_name` in responses, debug logging throughout pipeline |
| Notifications feature (API, repository, providers, 1 screen) | Done | Dark theme, colored icon badges, unread/read styling, `member_joined` type with circle navigation |
| Profile feature (1 screen) | Done | Dark theme, gradient profile card, grouped settings with gradient icons |
| App entry point (main.dart) | Done | Firebase, timezone, WorkManager, local notifications plugin (top-level), `cliquepix_default` channel creation, Android 13+ permission request, FCM `onMessage` foreground listener, background message handler |
| All API providers wired to ApiClient | Done | No UnimplementedError providers |
| App launcher icon | Done | Clique Pix camera logo at all Android densities |
| Login screen | Done | Dark gradient, animated glowing logo, slide-in animations |
| App-wide dark theme | Done | `AppTheme.dark` applied globally in app.dart; all screens use consistent dark (#0E1525) background with gradient accents |
| Home screen dashboard | Done | State-aware: brand new, has circles, active events, expired events; How It Works card, circle quick-start chips, active event cards with countdown timers |
| Android manifest | Done | Permissions, App Links, FCM, MSAL BrowserTabActivity |
| iOS Info.plist | Done | Camera/photo permissions, background modes, MSAL URL schemes |
| Firebase config (Android) | Done | `google-services.json` placed in `android/app/` |
| Firebase config (iOS) | Done | `GoogleService-Info.plist` placed in `ios/Runner/` |

### Website (clique-pix.com)

| Component | Status | Notes |
|-----------|--------|-------|
| Landing page (index.html) | Done | Brand design, feature highlights, download CTAs |
| Privacy policy (privacy.html) | Done | Photo sharing-specific, Xtend-AI LLC, NC jurisdiction |
| Terms of service (terms.html) | Done | 16 sections, effective March 25, 2026 |
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
| Function App | `func-cliquepix-fresh` | eastus | Ready — 27 functions deployed (incl. `removeMember`) |
| Storage Account | `stcliquepixprod` | eastus | Ready — `photos` container, blob public access disabled |
| PostgreSQL | `pg-cliquepixdb` | eastus2 | Ready — v18, `cliquepix` DB with 8 tables |
| Key Vault | `kv-cliquepix-prod` | eastus | Ready — `pg-connection-string` + `fcm-credentials` stored |
| API Management | `apim-cliquepix-002` | eastus | Ready — Developer SKU, API imported, rate limiting configured |
| Front Door | `fd-cliquepix-prod` | global | Ready — Standard SKU (no WAF) |
| Static Web App | `swa-cliquepix-prod` | eastus2 | Ready — clique-pix.com + www |
| DNS Zone | `clique-pix.com` | global | Ready — api CNAME, apex ALIAS, www CNAME, TXT validation |
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

## QR Invite Flow Fix + Circle Join Notifications (2026-03-31)

### Problem 1: QR Code invite returns 404

Scanning a circle invite QR code navigated to `https://clique-pix.com/invite/{code}` which returned a 404 from Azure because the Static Web App had no route or page for `/invite/*` paths.

**Root causes and fixes:**

| Issue | Fix |
|-------|-----|
| No web page for `/invite/*` paths | Created `website/invite.html` — branded dark-themed landing page with platform detection, `intent://` URI for Android, app store buttons |
| No SWA rewrite rule | Added `/invite/*` → `invite.html` rewrite in `staticwebapp.config.json` (must come before `.well-known` routes) |
| `DeepLinkService` never initialized | Converted `app.dart` to `ConsumerStatefulWidget`, call `initialize(router)` in `initState` |
| Invite route bypassed auth check | Removed `isInviteRoute` exemption from GoRouter redirect; added `?redirect=` query param to preserve invite URL through login flow |
| `.well-known` placeholders | Replaced `TEAM_ID` → `4ML27KY869` in AASA; replaced SHA256 placeholder with debug keystore fingerprint in assetlinks.json |
| `JoinCircleScreen` light theme | Restyled with dark background, gradient heading, aqua accents, dark TextField |

**Website redeployed** to `swa-cliquepix-prod` via SWA CLI. Invite URLs now return 200 with branded page.

### Problem 2: Owner not notified when someone joins circle

| Issue | Fix |
|-------|-----|
| No `member_joined` notification type | Created migration `002_member_joined_notification.sql` — ALTERed CHECK constraint on `notifications.type` |
| Backend didn't send push on join | Added FCM push + notification record creation to `joinCircle()` in `circles.ts`; replicates exact pattern from `photos.ts` |
| `NotificationType` model missing type | Added `'member_joined'` to union type in `notification.ts` |
| Client didn't render `member_joined` | Added icon/color case (person_add + aqua/violet), title case ("New Member"), and circle navigation in `_NotificationTile.onTap` |
| No FCM token registration | Created `PushNotificationService` — requests permission, gets FCM token, sends to `POST /api/push-tokens`, listens for token refresh |
| No auto-refresh on circle screens | Added `WidgetsBindingObserver` + `RefreshIndicator` + `Timer.periodic(30s)` polling to both `CirclesListScreen` and `CircleDetailScreen` |

**Backend redeployed** to `func-cliquepix-fresh`. Migration run against `pg-cliquepixdb`.

**Known issue:** Push notifications not yet confirmed working end-to-end on device. FCM token registration and backend push logic are implemented but need further debugging.

### Problem 3: Global light theme overriding dark screens

`app.dart` used `AppTheme.light` — a Material 3 light theme that overrode per-widget dark styling on some screens (notably `CreateCircleScreen`).

**Fix:** Created `AppTheme.dark` in `app_theme.dart` with dark defaults matching the app's visual design (dark scaffold, dark AppBar, dark InputDecoration, aqua accents). Switched `app.dart` to `theme: AppTheme.dark`.

---

## Remaining Tasks

### Completed

| Task | Status | Notes |
|------|--------|-------|
| MSAL authentication flow | Done | End-to-end working: MSAL → custom API scope → backend JWT verification → user upsert |
| Event-first UX flow | Done | 4 tabs (Events/Circles/Notifications/Profile), event creation with inline circle picker |
| Dark theme across all screens | Done | Circles detail, event detail, camera capture, notifications, profile — all consistent |
| Photo editor integration | Done | `pro_image_editor` ^5.1.4 — crop, draw, stickers, emoji, filters, text |
| Auth error recovery | Done | Auto-login on startup, MSAL cache reset on failure, error dismiss button |
| New app icon/logo | Done | Generated via `flutter_launcher_icons` from 1024x1024 source |
| Backend: `listAllEvents` endpoint | Done | `GET /api/events` — returns all events across user's circles with circle name/member count |
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
| Home screen dashboard | Done | 4-state contextual dashboard, How It Works card, circle chips, active event cards |
| Back buttons on full-screen routes | Done | Event detail, camera capture, photo detail all have explicit back navigation |
| Circle join push notification (backend) | Done | `joinCircle()` sends FCM to existing members, creates `member_joined` notification records |
| DB migration: member_joined type | Done | `002_member_joined_notification.sql` run against `pg-cliquepixdb` |
| FCM token registration (client) | Done | `PushNotificationService` gets token, registers with backend, listens for refresh |
| Circle screens refresh | Done | Pull-to-refresh + app-resume + 30s polling on CirclesListScreen and CircleDetailScreen |
| JoinCircleScreen dark theme | Done | Gradient heading, aqua accents, dark TextField |
| Dark theme consistency | Done | EventsListScreen, CreateCircleScreen, InviteScreen all restyled |

### Recently Completed (2026-04-01)

| Task | Status | Notes |
|------|--------|-------|
| Circle member management: owner remove | Done | `DELETE /api/circles/{circleId}/members/{userId}` — owner-only, validates role, prevents self-removal |
| Circle member management: leave/delete UI | Done | "Leave Circle" button (members), "Delete Circle" button (sole owner), confirmation dialogs |
| Circle member management: tappable removal | Done | Owner sees remove icon on non-owner members; tap shows confirmation dialog |
| Graceful 404 on member removal | Done | When removed user's screen refreshes, detects 404 DioException and navigates to `/circles` with SnackBar instead of showing error |
| State invalidation: member count | Done | Uses `membersAsync.valueOrNull?.length` for live count; avoids full-screen loading flash |
| Frontend API: `removeMember` | Done | Endpoint constant, CirclesApi method, CirclesRepository method |
| Push notification: foreground display | Done | `onMessage` listener in `main.dart` shows heads-up banner via `flutter_local_notifications.show()` |
| Push notification: channel creation | Done | `cliquepix_default` channel with `Importance.high` created in `main.dart` at startup |
| Push notification: Android 13+ permission | Done | `requestNotificationsPermission()` via Android-specific plugin API |
| Push notification: background tap | Done | `onMessageOpenedApp` → navigates to circle/event via GoRouter |
| Push notification: terminated tap | Done | `getInitialMessage()` → delayed navigation after router init |
| Push notification: local tap routing | Done | Static callback bridges `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter |
| Push notification: in-app list refresh | Done | `onMessage` invalidates `notificationsListProvider` for immediate update |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 27 functions |

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
| 2. Create a Circle | Done (2026-03-26) |
| 3. Generate invite link/QR | Done (2026-03-31) — QR code encodes `https://clique-pix.com/invite/{code}` |
| 4. Join Circle via invite (QR scan) | Done (2026-03-31) — invite landing page loads (no more 404), join succeeds, joiner appears in circle |
| 5. Create Event (24h/3d/7d) | Done (2026-03-26) |
| 6. Capture photo in-app | Done (2026-03-26) — photo confirmed in database |
| 7. Upload photo (compress → SAS → blob → confirm) | In progress — double-pop bug fixed (user never saw Upload button); Dio config fixed; needs retest |
| 8. See photo in feed | In progress — type cast bug fixed, needs retest after upload pipeline fix |
| 9. React to photo | Not tested |
| 10. Save photo to device | Not tested |
| 11. Share photo externally | Not tested |
| 12. Receive push notification (circle join) | In progress — backend sends FCM successfully (confirmed via App Insights telemetry), client has foreground/background/terminated handlers + notification channel + Android 13+ permission. Needs on-device verification. |
| 13. Auto-deletion after expiry | Not tested |
| 14. Graceful re-login (Layer 5) | Not tested |
| 15. Owner sees new member (auto-refresh) | Partial — pull-to-refresh works, 30s polling implemented, but auto-refresh not confirmed working on device |
| 16. Owner removes member from circle | Done (2026-04-01) — owner taps member → confirm dialog → member removed → list refreshes |
| 17. Member leaves circle | Done (2026-04-01) — member taps "Leave Circle" → confirm → navigates to circles list |
| 18. Removed member graceful redirect | Done (2026-04-01) — 404 detection auto-navigates removed user back to circles list with SnackBar |
