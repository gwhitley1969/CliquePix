# DEPLOYMENT_STATUS.md — Clique Pix v1

Last updated: 2026-03-25

---

## Code Implementation Status

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Shared models (8 files) | Done | User, Circle, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | Code reviewed + fixed |
| Auth middleware (JWT via JWKS) | Done | Uses typed errors (UnauthorizedError, NotFoundError) |
| Error handler middleware | Done | Correlation IDs via invocationId |
| Auth functions (verify, getMe) | Done | |
| Circles functions (7 endpoints) | Done | |
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
| Project scaffold (pubspec.yaml, analysis_options) | Done | Needs `flutter create` from Windows terminal |
| Design system (colors, gradients, typography, theme) | Done | Uses `withValues(alpha:)` (Flutter 3.27+) |
| Constants (endpoints, app constants, environment) | Done | Domain: `clique-pix.com` |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Auth guard + deep link /invite/:code |
| API client (Dio + 3 interceptors) | Done | Auth interceptor uses parent Dio for retry |
| Token storage service | Done | Refresh callback mechanism |
| Storage service (save to gallery + share download) | Done | |
| Deep link service | Done | Host: clique-pix.com |
| Shared widgets (7 widgets) | Done | CachedNetworkImageProvider for avatars |
| Data models (5 models) | Done | PhotoModel includes status field |
| Auth feature (API, state, repository, providers, UI) | Done | MSAL methods are placeholders; signOut cancels background jobs |
| 5-layer token refresh (4 services + welcome back dialog) | Done | loginHint threaded through |
| Circles feature (API, repository, providers, 5 screens) | Done | joinByInviteCode dedicated API method |
| Events feature (API, repository, providers, 3 screens) | Done | |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | Compression constrains max dim without upscaling; feed polls every 30s |
| Notifications feature (API, repository, providers, 1 screen) | Done | |
| Profile feature (1 screen) | Done | |
| App entry point (main, app, shell) | Done | |
| All API providers wired to ApiClient | Done | No more UnimplementedError |
| Android manifest | Done | 5-layer permissions, App Links, FCM |
| iOS Info.plist | Done | Camera/photo permissions, background modes |

### Infrastructure as Code

| Component | Status | Notes |
|-----------|--------|-------|
| .gitignore | Done | |
| Well-known files (apple-app-site-association, assetlinks.json) | Done | assetlinks.json needs SHA256 fingerprint |
| Documentation (ARCHITECTURE.md, PRD.md, ENTRA_REFRESH_TOKEN_WORKAROUND.md) | Done | Domain corrected to clique-pix.com |

---

## Azure Infrastructure Status

### All Resources (in `rg-cliquepix-prod`)

| Resource | Name | Status |
|----------|------|--------|
| Resource Group | `rg-cliquepix-prod` | Ready (eastus) |
| Log Analytics | `log-cliquepix-prod` | Ready (eastus) |
| Application Insights | `appi-cliquepix-prod` | Ready (eastus, workspace-based) |
| Function App | `func-cliquepix-fresh` | Ready — 26 functions deployed, health responding |
| Storage Account | `stcliquepixprod` | Ready — `photos` container created, blob public access disabled |
| PostgreSQL | `pg-cliquepixdb` | Ready (eastus2, v18) — `cliquepix` DB with 8 tables |
| Key Vault | `kv-cliquepix-prod` | Ready — `pg-connection-string` stored |
| API Management | `apim-cliquepix-002` | Ready — CliquePix API v1 imported, 5 catch-all operations |
| Front Door | `fd-cliquepix-prod` | Ready — Standard SKU (no WAF), routing to APIM |
| DNS Zone | `clique-pix.com` | Ready — `api` CNAME → Front Door |
| Entra External ID | `cliquepix.onmicrosoft.com` | Exists — needs app registration + email OTP config |

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
- `https://api.clique-pix.com/api/health` (pending managed certificate propagation)

### Configuration Notes

| Setting | Value | Notes |
|---------|-------|-------|
| `allowSharedKeyAccess` | `true` | Required by Azure Functions runtime for AzureWebJobsStorage |
| `allowBlobPublicAccess` | `false` | No anonymous blob access |
| Storage SKU | `Standard_GZRS` | Changed from RAGZRS (not supported by Consumption plan) |
| Function App plan | Consumption (Linux) | EastUSLinuxDynamicPlan |
| Deployment method | Run-from-package (blob SAS) | Windows→Linux zip requires Python zipfile for forward slashes |
| Front Door endpoint | `cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net` | |
| Custom domain | `api.clique-pix.com` | CNAME + managed certificate |

---

## Remaining Tasks

### Azure Configuration (Portal / Manual)

| Task | Status | Notes |
|------|--------|-------|
| Entra: register CliquePix app | Not done | Get tenant ID + client ID |
| Entra: configure email OTP / magic link | Not done | |
| Update Function App `ENTRA_CLIENT_ID` setting | Not done | Currently set to placeholder |
| Firebase: create project + enable FCM | Not done | |
| Firebase: download google-services.json | Not done | For Android |
| Firebase: download GoogleService-Info.plist | Not done | For iOS |
| Key Vault: add `fcm-credentials` secret | Not done | After Firebase project created |
| APIM: rate limiting policies | Not done | Global 60/min, uploads 10/min, auth 5/min |
| APIM: X-Azure-FDID header validation | Not done | Restrict APIM to Front Door traffic only |

### Flutter Integration

| Task | Status | Notes |
|------|--------|-------|
| Run `flutter create` from Windows terminal | Not done | Generates gradle/Xcode project files |
| Complete MSAL integration | Not done | signIn, silentSignIn, refreshToken are placeholders |
| Add google-services.json (Android) | Not done | After Firebase project |
| Add GoogleService-Info.plist (iOS) | Not done | After Firebase project |
| Build and test on real devices | Not done | |

### End-to-End Validation

| Step | Status |
|------|--------|
| 1. Sign up / sign in | Not done |
| 2. Create a Circle | Not done |
| 3. Generate invite link/QR | Not done |
| 4. Join Circle via invite | Not done |
| 5. Create Event (24h/3d/7d) | Not done |
| 6. Capture photo in-app | Not done |
| 7. Upload photo (compress → SAS → blob → confirm) | Not done |
| 8. See photo in feed | Not done |
| 9. React to photo | Not done |
| 10. Save photo to device | Not done |
| 11. Share photo externally | Not done |
| 12. Receive push notification | Not done |
| 13. Auto-deletion after expiry | Not done |
| 14. Graceful re-login (Layer 5) | Not done |
