# DEPLOYMENT_STATUS.md — Clique Pix v1

Last updated: 2026-03-24

---

## Code Implementation Status

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | Compiles with zero TS errors |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Shared models (8 files) | Done | User, Circle, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | |
| Auth middleware (JWT via JWKS) | Done | |
| Error handler middleware | Done | |
| Auth functions (verify, getMe) | Done | |
| Circles functions (7 endpoints) | Done | |
| Events functions (3 endpoints) | Done | |
| Photos functions (5 endpoints) | Done | Includes sharp validation + thumbnail generation |
| Reactions functions (2 endpoints) | Done | |
| Notifications functions (3 endpoints) | Done | |
| Timer functions (3 timers) | Done | Cleanup expired, orphans, notify expiring |
| Health endpoint | Done | |
| npm dependencies installed | Done | 329 packages, 0 vulnerabilities |

### Flutter Mobile App (Dart)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (pubspec.yaml, analysis_options) | Done | Needs `flutter create` from Windows terminal |
| Design system (colors, gradients, typography, theme) | Done | |
| Constants (endpoints, app constants, environment) | Done | |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Deep link support for /invite/:code |
| API client (Dio + 3 interceptors) | Done | |
| Token storage service | Done | |
| Storage service (save to gallery) | Done | |
| Deep link service | Done | |
| Shared widgets (7 widgets) | Done | |
| Data models (5 models) | Done | |
| Auth feature (API, state, repository, providers, UI) | Done | MSAL methods are placeholders |
| 5-layer token refresh (4 services + welcome back dialog) | Done | |
| Circles feature (API, repository, providers, 5 screens) | Done | |
| Events feature (API, repository, providers, 3 screens) | Done | |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | |
| Notifications feature (API, repository, providers, 1 screen) | Done | |
| Profile feature (1 screen) | Done | |
| App entry point (main, app, shell) | Done | |
| Android manifest | Done | 5-layer permissions, App Links, FCM |
| iOS Info.plist | Done | Camera/photo permissions, background modes |

### Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| .gitignore | Done | |
| Well-known files (apple-app-site-association, assetlinks.json) | Done | assetlinks.json needs SHA256 fingerprint |
| Documentation (ARCHITECTURE.md, PRD.md, ENTRA_REFRESH_TOKEN_WORKAROUND.md) | Done | |

---

## Azure Infrastructure Status

### Existing Resources (in `rg-cliquepix-prod`)

| Resource | Name | Status |
|----------|------|--------|
| Resource Group | `rg-cliquepix-prod` | Exists |
| API Management | `apim-cliquepix-002` | Exists — needs API import and policies |
| DNS Zone | `clique-pix.com` | Exists |
| Entra External ID | `cliquepix.onmicrosoft.com` | Exists — needs app registration + email OTP config |
| Key Vault | `kv-cliquepix-prod` | Exists — needs secrets (pg-connection-string, fcm-credentials) |
| PostgreSQL | `pg-cliquepix` | Exists (East US 2) — needs schema migration |
| Storage Account | `stcliquepixprod` | Exists — needs `photos` container created |

### Resources to Create

| Resource | Name | Status | Notes |
|----------|------|--------|-------|
| Log Analytics Workspace | `log-cliquepix-prod` | Not created | Prerequisite for App Insights |
| Application Insights | `appi-cliquepix-prod` | Not created | Workspace-based, linked to Log Analytics |
| Function App | `func-cliquepix-fresh` | Not created | Flex Consumption, Node.js 20, Linux |
| Front Door | `fd-cliquepix-prod` | Not created | Standard SKU, WAF with DRS 2.1 |
| Firebase Project | (new) | Not created | FCM push transport only |

### RBAC Role Assignments (for Function App managed identity)

| Role | Scope | Status |
|------|-------|--------|
| Storage Blob Data Contributor | `stcliquepixprod` | Not assigned |
| Storage Blob Delegator | `stcliquepixprod` | Not assigned |
| Key Vault Secrets User | `kv-cliquepix-prod` | Not assigned |
| Monitoring Metrics Publisher | `appi-cliquepix-prod` | Not assigned |

### Configuration Tasks

| Task | Status | Notes |
|------|--------|-------|
| Storage: verify `allowSharedKeyAccess: false` | Not verified | |
| Storage: verify `allowBlobPublicAccess: false` | Not verified | |
| Storage: create `photos` container (private) | Not done | |
| Key Vault: add `pg-connection-string` secret | Not done | |
| Key Vault: add `fcm-credentials` secret | Not done | |
| Function App: configure app settings | Not done | PG_CONNECTION_STRING, STORAGE_ACCOUNT_NAME, ENTRA_TENANT_ID, ENTRA_CLIENT_ID, APPLICATIONINSIGHTS_CONNECTION_STRING |
| APIM: import CliquePix API v1 | Not done | Backend URL → func-cliquepix-fresh |
| APIM: rate limiting policies | Not done | Global 60/min, uploads 10/min, auth 5/min |
| APIM: X-Azure-FDID header validation | Not done | |
| Front Door: origin group → APIM | Not done | |
| Front Door: health probe /api/health | Not done | |
| Front Door: custom domain api.clique-pix.com | Not done | |
| Front Door: WAF policy (DRS 2.1, detection mode) | Not done | |
| Front Door: well-known file routing | Not done | |
| DNS: CNAME api.clique-pix.com → Front Door FQDN | Not done | |
| Entra: configure email OTP / magic link | Not done | |
| Entra: register CliquePix app | Not done | |
| Firebase: create project + enable FCM | Not done | |
| Firebase: download google-services.json | Not done | |
| Firebase: download GoogleService-Info.plist | Not done | |
| Run 001_initial_schema.sql against pg-cliquepix | Not done | |

---

## Integration Tasks

| Task | Status | Notes |
|------|--------|-------|
| Flutter: run `flutter create` from Windows terminal | Not done | Generates gradle/Xcode boilerplate |
| Flutter: wire Riverpod API providers | Not done | authApiProvider, circlesApiProvider, eventsApiProvider, photosApiProvider, notificationsApiProvider throw UnimplementedError |
| Flutter: complete MSAL integration | Not done | signIn, silentSignIn, refreshToken are placeholders |
| Backend: deploy to func-cliquepix-fresh | Not done | `func azure functionapp publish func-cliquepix-fresh` |
| End-to-end test flow (14 steps) | Not done | |

---

## Deployment Order

1. Create Log Analytics → Application Insights
2. Create Function App (Flex Consumption) with managed identity
3. Assign RBAC roles to Function App identity
4. Create Key Vault secrets
5. Configure Function App app settings (with Key Vault references)
6. Run database migration against pg-cliquepix
7. Create storage `photos` container
8. Deploy backend code to Function App
9. Configure APIM (import API, policies)
10. Create Front Door (origin → APIM, health probe, WAF)
11. Configure DNS (api.clique-pix.com → Front Door)
12. Configure Entra External ID (app registration, email OTP)
13. Create Firebase project, store FCM credentials in Key Vault
14. Flutter: run `flutter create`, wire providers, integrate MSAL
15. Add platform config files (google-services.json, GoogleService-Info.plist)
16. Build and test on devices
