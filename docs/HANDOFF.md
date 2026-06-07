# HANDOFF.md — Clique Pix

**Last updated:** 2026-06-07
**Purpose:** Single entry-point for anyone taking over (or returning to) Clique Pix. Read this top-to-bottom; it points into the deep docs for detail. If you read only one file, read this one.

> **What's authoritative:** `.claude/CLAUDE.md` is the development guardrails (it wins on scope/architecture/patterns). This file is the *operational* handoff — how to build, deploy, where things live, current state, and the rules you must not break. Where they overlap, CLAUDE.md is the source of truth and this file links to it.

---

## 0. Where to start if you're new

1. **Read this file**, then `.claude/CLAUDE.md` (the guardrails) and `docs/PRD.md` (what the product is).
2. **Get access** to the accounts in §5 (Azure subscription, Entra, RevenueCat, Apple Developer, Google Play, GitHub repo). The `secrets/` folder is **gitignored** — get those files from Gene directly.
3. **Build the web client and run it** (§3) — it hits the production API, so you'll see real data with zero backend setup. Fastest way to get oriented.
4. **Build a debug Android APK** (§3) and sign in to see the mobile app.
5. Skim §6 (don't-regress invariants) before changing anything.

---

## 1. Project overview & current status

**Clique Pix** is a **private, event-based photo and video sharing** mobile + web app. Users create **Cliques** (persistent groups), start **Events** (temporary media sessions, 24h/3d/7d), and share photos/videos that **auto-expire from the cloud** when the event ends. It is *not* a social network, feed, or messaging app.

**The two core loops** (every line of code serves one):
- **Photo:** sign in → create Event → capture/pick photo → edit (crop/draw/stickers/filters) → compress on-device → upload to Blob via SAS → feed + push → react/save/share → auto-delete.
- **Video:** capture/pick → client validate → resumable block upload → server transcode (FFmpeg → HLS + MP4 + poster) → uploader plays instantly from the local file while it transcodes → others play via HLS/MP4 → auto-delete.

**What's built (v1):** Entra CIAM auth (email+password, Google, Apple) with a 5-layer refresh-token defense; 13+ age gate; Cliques + invite (link/QR/SMS, deep-linked); Events; in-app camera + gallery for photo & video; client photo compression; video transcoding pipeline; event feed + reactions + save/share + uploader-or-organizer delete; event-scoped 1:1 DMs; avatars; **subscription paywall + 7-day free trial** (RevenueCat); FCM push; auto-expiry + orphan cleanup; **React web client** at clique-pix.com.

**Hard "do not build":** group chat, followers, public feeds/discovery, custom photo-editor (use `pro_image_editor`), video editing, 4K/HDR-preserved video, live streaming, AI features, Firebase backend (FCM transport only), Redis/SignalR/Service Bus.

**Architecture in one line:** `Flutter (iOS/Android) + React web → Azure Front Door → APIM → Azure Functions (TypeScript) → PostgreSQL + Blob Storage`, with the FFmpeg transcoder on **Container Apps Jobs**, **Entra External ID (CIAM)** for auth, and **Azure Web PubSub** for DM + `video_ready` real-time.

**Current launch status (2026-06-07):**
- **iOS:** TestFlight-only (`https://testflight.apple.com/join/hWznNvJ6`) pending App Store review; Apple ID `6766294274`.
- **Android:** sideloaded release APK + Play (internal testing). Play subscription setup in progress (tax verified; identity verification to confirm).
- **Paywall:** live — single tier `plus`, **$3.99/mo or $39.99/yr**, 7-day no-card trial granted at first sign-in.
- **Web:** live at clique-pix.com.

Deep docs: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `.claude/CLAUDE.md`.

---

## 2. Architecture map

| Surface | Stack | Lives in | Deep doc |
|---|---|---|---|
| **Mobile** | Flutter (Dart), Riverpod, Dio, `pro_image_editor`, `msal_auth`, `video_player`+`chewie`, `purchases_flutter` | `app/` | CLAUDE.md "Project Structure"; `docs/AUTHENTICATION.md` |
| **Web** | React 18 + Vite 5 + TS, Tailwind, Radix, React Query, `@azure/msal-browser`, `hls.js` | `webapp/` | `docs/WEB_CLIENT_ARCHITECTURE.md` |
| **Backend API** | Azure Functions (TypeScript, Node 20) | `backend/` | `docs/ARCHITECTURE.md` |
| **Transcoder** | FFmpeg in a SHA-pinned `jrottenberg/ffmpeg:6-alpine` container, on Container Apps Jobs | `backend/transcoder/` | `docs/VIDEO_ARCHITECTURE_DECISIONS.md`, `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` |

**Request path (control plane, no exceptions):** client → **Front Door** (`fd-cliquepix-prod`) → **APIM** (`apim-cliquepix-003`, Basic v2) → **Functions** (`func-cliquepix-fresh`) → **PostgreSQL** (`pg-cliquepixdb`) / **Blob** (`stcliquepixprod`). No direct Function URLs are published to clients.

**Async video path:** confirm endpoint enqueues on Storage Queue `video-transcode-queue` → **Container Apps Job** (`caj-cliquepix-transcoder`) pulls, transcodes, calls back to an internal Function endpoint (function-key auth) → Function updates DB + pushes `video_ready` via Web PubSub (`wps-cliquepix-prod`) + FCM.

**Data:** one Postgres DB; the `photos` table hosts **both** photos and videos (`media_type` column — historical name). One Blob container `photos` holds all media under `photos/{cliqueId}/{eventId}/{mediaId}/…`. Schema detail: `docs/ARCHITECTURE.md` §Data Architecture.

**Auth:** Entra External ID **CIAM** tenant `cliquepix.ciamlogin.com`, client `7db01206-135b-4a34-a4d5-2622d1a888bf`, custom API scope `access_as_user`. The CIAM 12-hour refresh-token bug drives the **5-layer defense** (`docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`).

---

## 3. Build, run & test

**Toolchains:** Flutter **3.35.5** (pinned in CI), Node **20+** (local 22 is fine), Docker, Android SDK + a JDK (`keytool`/`apksigner` live in the SDK/JDK), Azure CLI (`az`) + Azure Functions Core Tools (`func`) for deploys.

### Mobile (Flutter) — `app/`

> **Project rule (non-negotiable):** ALWAYS `flutter clean` before an APK build, even for one-file changes — stale artifacts must not interfere.

```bash
cd app
flutter clean && flutter pub get

# Release APK (direct install / sideload):
flutter build apk --release --dart-define-from-file=dart_defines/release.json
#   → app/build/app/outputs/flutter-apk/app-release.apk

# Release AAB (for Play upload):
flutter build appbundle --release

# Local debug run (debug keystore):
flutter run --dart-define-from-file=dart_defines/debug.json

# Tests / static analysis (what CI runs):
flutter analyze --no-fatal-infos
flutter test
```

**Signing & the MSAL redirect-URI nuance (important):**
- The MSAL Android redirect URI is chosen **at build time** by `MsalConstants.androidRedirectUri = String.fromEnvironment('MSAL_ANDROID_REDIRECT_URI', defaultValue: <release hash>)`. `dart_defines/release.json` = the **Play App Signing** hash (also the default); `dart_defines/debug.json` = the **debug keystore** hash. See `app/dart_defines/README.md`.
- Local release builds are signed with the **upload key** (`app/android/key.properties`). **Google re-signs with the Play App Signing key only when you distribute via Play.** So a locally-built release APK's cert (hash `YtL16/JyfHiAzjIBnw2zbiY9QzY=`) is *not* the Play hash — but that doesn't matter for sign-in (next bullet).
- **Sideloaded release APKs DO sign in** (verified 2026-06-06). Clique Pix uses the CIAM **system-browser/Custom-Tabs** redirect flow (not the Authenticator broker), which does **not** validate the redirect-URI hash against the running app's signing cert. Only two things matter: the redirect hash is registered in Entra **and** declared as a `<data>` path in `AndroidManifest.xml` — both true for `4Fsai…`. Don't assume a cert mismatch blocks testing.
- The Android manifest registers **both** the release (`4Fsai…`) and debug (`W28+…`) redirect paths. Both hashes are also registered in the Entra app registration. If you regenerate a keystore, update: the matching `dart_defines/*.json`, the manifest `<data>` path, and the Entra redirect URI (see `app/dart_defines/README.md` + `docs/AUTHENTICATION.md` AUTH-1).

### Web — `webapp/`

```bash
cd webapp
npm ci
npm run build         # tsc + vite → dist/  (this is the deploy gate)
npm run dev           # Vite on http://localhost:5173 — hits the PRODUCTION API, no local backend needed
npm run lint
```

### Backend — `backend/`

```bash
cd backend
npm ci
npm run lint && npx tsc --noEmit && npm test   # exactly what Backend CI runs (221 tests)
npm run build                                  # tsc → dist/src/functions/*.js
func azure functionapp publish func-cliquepix-fresh   # deploy (manual)
# health: GET https://func-cliquepix-fresh.azurewebsites.net/api/health → 200
```

### Transcoder — `backend/transcoder/`

```bash
cd backend/transcoder
npm ci
npx tsc --noEmit && npx tsc
docker build -t cliquepix-transcoder:test .
```
Deploy is a retag + job update (see §4) — the running job is pinned to a semver tag, not `:latest`.

### CI (GitHub Actions, `.github/workflows/`)

| Workflow | Runs | ⚠️ |
|---|---|---|
| **Backend CI** | `npm ci` → lint → `tsc --noEmit` → test | on `backend/**` |
| **Flutter CI** | `flutter pub get` → analyze → test | **never builds an APK** — see §6 |
| **Transcoder Build** | `npm ci` → tsc → `docker build` (+ ACR push on main) | on `backend/transcoder/**` |
| **Deploy Web App** | SWA action build + deploy | on `webapp/**` |
| **Clean up SWA PR environment** (`swa-cleanup.yml`) | deletes the PR preview env on PR close | every PR close |

All actions are pinned to `@v6` (Node 24). **Path-filter gotcha:** Backend/Flutter/Transcoder CI only run on a PR when their *source dirs* change — editing only their YAML doesn't trigger them on the PR (first validated on the post-merge `main` push).

---

## 4. Deploy channels & current live state

**Deploy is NOT uniform across surfaces — know which is which:**

| Surface | How it deploys | Live when |
|---|---|---|
| **Web / SWA** | **Auto** — GitHub Actions on merge to `main` touching `webapp/**` | minutes after merge |
| **Backend** | **Manual** — `func azure functionapp publish func-cliquepix-fresh` | when you run it |
| **Transcoder** | CI builds + pushes to ACR, **but the Container Apps Job is pinned to a SEMVER tag** (currently **`v0.1.8`**). `:latest` is NOT live until you `az acr import` retag → `az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --image cracliquepix.azurecr.io/cliquepix-transcoder:vX.Y.Z` | after retag + job update |
| **Mobile** | **A new app build** (Play / TestFlight). Nothing auto-deploys. | when you ship a build |

**SWA staging-env auto-cleanup:** the SWA Free tier caps staging (preview) envs at **3 concurrent**; every PR creates one. Cleanup is handled by `.github/workflows/swa-cleanup.yml` (`pull_request: types: [closed]`, **no paths filter**). It's a *separate* workflow on purpose — `webapp-deploy.yml`'s trigger omits `types:` so it never receives `closed` (the old in-workflow close job ran 0 times across ~30 PRs and orphaned envs until the cap blocked deploys). Break-glass if it ever fails: `az staticwebapp environment delete --name swa-cliquepix-prod --resource-group rg-cliquepix-prod --environment-name <PR#> --yes`.

**Current live state (2026-06-07):**
- ✅ **Backend** `#22/#23` hardening **deployed + verified** (RevenueCat webhook returns 200 on a valid signature, 401 on a bad one; `/api/health` 200).
- ✅ **Transcoder** running `v0.1.8` (TQ-1 poison-message guard).
- ✅ **Web** live with all recent fixes (DM ownership, EntitlementGuard error state, Lightbox MP4 download, web DM mark-read, **photo 3024/q88**, **avatar quality**).
- ⏳ **Mobile photo-quality bump (3024 px / q88) + avatar q90 are LIVE on web but PENDING the next mobile build** — the Dart code is on `main`; it ships to users only in a new Play/TestFlight build.
- ✅ All 4 CI workflows green on `main`; **0 open PRs**.

Deploy history + per-item status: `docs/DEPLOYMENT_STATUS.md`.

---

## 5. Accounts, keys, domains & secrets index

> **No secret VALUES are in this repo or this doc — only locations/identifiers.** The `secrets/` folder (`.p8` keys, service-account JSON) is gitignored. Passwords live in Key Vault or with Gene. **A new owner must obtain from Gene directly:** the `secrets/` files, the Android keystore + `key.properties` passwords, the App Store reviewer account password, and any account logins.

### Domains & emails
| Item | Value |
|---|---|
| Web app | `clique-pix.com` · API `api.clique-pix.com` (the only owned domain; **no email mailboxes** on it) |
| ⚠️ `cliquepix.com` (no hyphen) | **NOT owned** — never reference it |
| Public contact (footer, legal, "Contact Us") | `support@xtend-ai.com` (company: **Xtend-AI, LLC**) |
| App Store reviewer login | `vwhitley1967@gmail.com` — **email+password** (NOT Google/Apple SSO); password held by Gene, **not** in Key Vault. `users.id 325e4455-b1b8-461e-a844-6f158cffaf84` |
| App Store Connect contact / account owner | `genewhitley2017@gmail.com` |
| APIM publisher / Azure admin notifications | `gwhitley@xtend-ai.com` |
| Ops / Azure budget-alert recipient | `bluebuildapps@gmail.com` (old "BlueBuildApps" brand) |

### Azure — subscription "Clique Pix" (`25410e67-b3c8-49a2-8cf0-ab9f77ce613f`), RG `rg-cliquepix-prod`
| Resource | Name |
|---|---|
| Function App | `func-cliquepix-fresh` |
| Storage (blob + queue) | `stcliquepixprod` |
| PostgreSQL Flexible Server | `pg-cliquepixdb` |
| Key Vault | `kv-cliquepix-prod` |
| APIM | `apim-cliquepix-003` (Basic v2) |
| Front Door | `fd-cliquepix-prod` |
| Web PubSub | `wps-cliquepix-prod` |
| Container Registry | `cracliquepix` |
| Container Apps Env / Job | `cae-cliquepix-prod` / `caj-cliquepix-transcoder` |
| Storage Queue | `video-transcode-queue` |
| Static Web App | `swa-cliquepix-prod` |
| App Insights | `appi-cliquepix-prod` |

**Key Vault contents (names only):** PostgreSQL connection string · FCM credentials · `revenuecat-webhook-secret` · `revenuecat-secret-api-key`. Function App reads them via Key Vault references (its managed identity has `Key Vault Secrets User`). Storage/Queue access is RBAC + managed identity (no account keys in code).

### Entra External ID (CIAM)
Tenant `cliquepix.ciamlogin.com` · app client `7db01206-135b-4a34-a4d5-2622d1a888bf` · custom API scope `access_as_user` · age gate via the `dateOfBirth` claim. **Android redirect hashes** registered (Entra + manifest): release/Play `4FsaiJ4wJWgM09R/hUh3osYJhgg=`, debug `W28+gAaZ9fNu1yL/GMRe94rK0dY=`. Web SPA redirects: `https://clique-pix.com/auth/callback`, `http://localhost:5173/auth/callback`. Full setup: `docs/AUTHENTICATION.md`, `docs/AGE_VERIFICATION_RUNBOOK.md`.

### RevenueCat (paywall)
Project `04f5314d` · entitlement `plus` · offering `default` (Monthly `$3.99` + Annual `$39.99`, 7-day trial) · webhook `whintgr721b9e5264` → `POST /api/internal/revenuecat-webhook` (Bearer secret in Key Vault) · iOS public SDK key `appl_OvhNypnojnQSEebpQtBikJYTHBa` (in `app/lib/core/constants/revenuecat_constants.dart`); **Android `goog_` key still pending Play setup.** Reviewer + beta access = RevenueCat **Promotional** grants (see §6). Punch list: `docs/GENE.md`.

### Apple / Google
Apple App ID `6766294274` · bundle `com.cliquepix.app` · Team `4ML27KY869` · Sign-in-with-Apple Services ID `com.cliquepix.app.service`, Key `4NYXZNV9VD`. ASC API key `AuthKey_TP9C6PA769.p8` + IAP key `SubscriptionKey_7K28U2Z2B2.p8` in `secrets/`. Android package `com.cliquepix.clique_pix`; Play service-account JSON (when set up) in `secrets/`.

### Android signing
`app/android/key.properties` → the **upload key** (cert hash → `YtL16/JyfHiAzjIBnw2zbiY9QzY=`). Play App Signing re-signs to `4Fsai…`. The debug keystore (`~/.android/debug.keystore`) on Gene's machine matches the registered debug hash `W28+…`.

---

## 6. Known issues, gotchas & DON'T-REGRESS invariants

These are load-bearing rules — each was added after an incident, an audit finding, or a confirmed upstream bug. Treat every one as a guardrail. Detail lives in `.claude/CLAUDE.md` ("Hard rule" callouts), `docs/SECURITY_AUDIT_2026-06-04.md` (the don't-regress list), and `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

### Auth — Entra CIAM 12h refresh-token bug + 5-layer defense
- **The 12h inactivity refresh-token expiry (`AADSTS700082`) is a real, portal-unfixable CIAM bug.** The whole 5-layer defense exists to keep users signed in past it — don't simplify it away.
- **The session-expired regex must stay synced across exactly 3 sites** (`AuthInterceptor._isSessionExpired`, `AuthRepository._extractAadstsCode`, `AuthNotifier._handleSilentSignInFailure`; codes `AADSTS700082`/`AADSTS500210`/`no_account_found`). One disagreement strands the user instead of routing to Welcome-Back re-login.
- **`pendingRefreshFlagKey` is cleared BEFORE awaiting the refresh** — else a hung refresh poisons every future resume.
- **Do NOT add `BGTaskSchedulerPermittedIdentifiers` to iOS `Info.plist`** — Layer 4 is Android-only; a declaration with no handler crashes with SIGABRT ("app vanishes after sign-in").
- **iOS MSAL broker MUST be `Broker.msAuthenticator`, not `Broker.safariBrowser`**, at all 3 PCA sites — `safariBrowser`'s persistent cookie jar traps account-switchers on "Continue as <previous user>".

### APIM — rate limiting REMOVED at all 4 scopes; never re-add
- **No `<rate-limit>` / `<rate-limit-by-key>` / `<quota>` at ANY scope** (Global/Product/API/Operation) until APIM leaves Developer/Basic tier — five 429 incidents. Abuse protection is application-layer (JWT, membership checks, SAS expiry, orphan cleanup) + client `silentRetryOn429`. When diagnosing a 429, audit **all four scopes AND `bicep/apim/main.bicep`**.

### Media deletion — always via `deleteMediaAssets`
- **All media deletes go through `deleteMediaAssets(media)`** (`backend/src/shared/services/blobService.ts`), which prefix-deletes a video's whole dir (HLS/fallback/poster) vs a photo's original+thumb. Deleting only `blob_path`+`thumbnail_blob_path` orphans video blobs forever (hit `deleteEvent`/`deleteMe`/expiry/`leaveClique` before the fix). Sole-owner `leaveClique` deletes blobs **before** `DELETE FROM cliques` (CASCADE removes the rows otherwise).

### Invite codes — 128-bit entropy is the only brute-force defense
- **`generateInviteCode` stays `crypto.randomBytes(16)` (128-bit); the join validator `INVITE_CODE_MAX_LENGTH` (64) stays ≥ the code length.** Join resolves a clique by `invite_code` alone with no rate limiting; a too-small cap silently truncated codes and made every new clique un-joinable (the INV-1 regression).

### Uploads — atomic claim between confirm and orphan-cleanup
- **Upload-confirm UPDATEs are guarded on `status='pending'`; the orphan timer deletes the blob only after its guarded row-delete wins.** Never revert to read-then-update / unconditional delete — they race and the timer can delete an in-flight confirm's blob.

### Paywall — a v1 requirement, not optional
- **Do NOT regress to a free tier / remove the paywall** without product approval. Backend authoritative: `requireActiveEntitlement` 402s `SUBSCRIPTION_REQUIRED`; effective access = `entitlement_active OR trial_ends_at > NOW()`.
- **Reviewer + beta access = RevenueCat Promotional grants, never a DB override.**
- **`forceSyncFromRcApi` must keep null-expiry lifetime/promo grants active and never down-grade via a synthetic event** (synthetic = RENEWAL-only). A null-`expires_date` `plus` IS the reviewer/beta mechanism; treating it as inactive hard-paywalled reviewers on "Refresh Subscription" (the PAY fix).

### FCM — de-register on sign-out + permanent-vs-transient purge
- **Sign-out/delete de-register the FCM token before clearing the JWT** (`DELETE /api/push-tokens`).
- **Only permanent FCM errors (404 `UNREGISTERED` / 400 `INVALID_ARGUMENT`) purge a token** (`isPermanentTokenError`) — a transient blip must not purge valid tokens (it was disabling the Layer-2 silent-push defense fleet-wide).

### Photo quality — editor cap must stay ≥ the compression cap
- **In `camera_capture_screen.dart`, `pro_image_editor`'s `imageGenerationConfigs.maxOutputSize` (`Size(4032,4032)`) must stay ≥ `AppConstants.maxImageDimension` (3024).** The editor's default is `Size(2000,2000)`, which silently re-caps every photo below 3024 before the authoritative compress step — degrading quality with no error. Photos are **3024 px / JPEG q88** (mobile + web in lockstep), avatars **q90** (mobile).

### Build / CI — two recurring footguns
- **Never put a literal `--` inside an XML comment (`<!-- … -->`)** — XML forbids it, and the parser rejects the whole file. **This has bitten twice:** `apim_policy.xml` (a `--protocols` comment broke the APIM Basic v2 deploy, 2026-05-05) and **`AndroidManifest.xml`** (`--dart-define-from-file` in a comment broke **all** release APK/AAB builds, fixed PR #41, 2026-06-06). Watch any hand-edited XML.
- **Flutter CI does NOT build an APK** — it runs `analyze` + `test` only, so manifest/XML/R8 breakage that only fails at `flutter build apk` is invisible to CI (that's exactly how the manifest bug shipped). **Recommended follow-up:** add a `flutter build apk --debug` step to `flutter-ci.yml`. And `flutter clean` before every release build (project rule).

---

## 7. Recent work log (2026-06-04 → 2026-06-07 session)

This session opened by pulling the security-audit branch from a Mac workstation (PR #17) and ran a full pre-submission hardening + cleanup pass. PRs **#17–#41**, all merged to `main`.

**Security audit + backend hardening**
- **#17** security & detrimental-bug audit (128-bit invite codes, canonical `deleteMediaAssets`, atomic upload-confirm claim, FCM de-register, CVE patches).
- **#18** added the Play App Signing SHA-256 to `assetlinks.json` (Android App Links auto-verify on Play-signed builds).
- **#19** ship-blockers: **INV-1** (invite-join regression — codes truncated, every clique un-joinable), **BLOB-1** (sole-owner clique-delete blob orphan), **TQ-1** (transcoder poison-message guard `MAX_DEQUEUE_COUNT=5`), **AUTH-1** (MSAL Android release redirect hash).
- **#21** reviewer-lockout: keep null-expiry promotional/lifetime grants active in `forceSyncFromRcApi`.
- **#22** PAY hardening: RevenueCat webhook always-200-on-non-auth (retry-storm guard) + non-UUID guard + `markExpired` TOCTOU.
- **#23** **NOTIF-1** (web-only members get in-app notification rows), **NOTIF-2** (permanent-vs-transient FCM token purge), **TQ-2** (event-expiry vs in-flight-transcode race).
- **Backend #22/#23 were deployed via `func publish` and verified** (webhook 200 on valid signature, 401 on invalid; `/api/health` 200).

**Flutter & web fixes**
- **#24** Flutter polish — `briefError` launch-crash, friendly bootstrap errors, gallery-save temp-file leaks.
- **#25** 5-layer auth state-machine hardening — session-resurrection epoch guard, 401 retry-loop guard, single-flight refresh mutex, optimistic-entitlement reset on identity change.
- **#26** webapp — DM sender-identity (UUID vs Entra OID), recoverable EntitlementGuard error state, Lightbox MP4 download.
- **#27** webapp — web DM mark-read sends `last_read_message_id` (was 400ing).

**CI & ops**
- **#28** bumped `actions/checkout` + `setup-node` to `@v6` (Node 24) across all 4 workflows.
- **#29** **SWA staging-env auto-cleanup** — new `swa-cleanup.yml` (root cause of the orphan-env failures: `webapp-deploy.yml`'s `pull_request` trigger omitted `types:`, so `closed` was never delivered). Proven working.
- **#41** fixed a malformed `AndroidManifest.xml` (illegal `--` in a comment, latent since #19) that **blocked all release APK/AAB builds**.

**Docs sync** — **#20/#30/#31/#32/#33** brought all ~20 `/docs` files current vs PR #17–28 (each gap grounded against the actual code), recorded deploys, and updated `GENE.md`.

**Email/domain cleanup** — **#34/#35/#36/#37** removed the never-existed `appreview@cliquepix.com` (reviewer is `vwhitley1967@gmail.com`) and `hello@clique-pix.com` (footer now `support@xtend-ai.com`), scrubbed the dead `cliquepix.app` domain, and corrected the reviewer-credentials block + legacy URLs.

**Photo / avatar quality** — **#38** raised photos from 2048 px/q80 to **3024 px/q88** (~3 MP → ~6.9 MP for a 12 MP phone) across mobile + web, including the `pro_image_editor` `maxOutputSize` lockstep; **#40** raised mobile avatars to **q90**; **#39** fixed the stale cross-references.

**Verification** — a clean release APK was built and **sideloaded successfully** on a Samsung Galaxy Flip 6 (confirming sideloaded release APKs sign in fine, despite the upload-key cert).

**What's pending**
- **Ship a new mobile build** (Play/TestFlight) to deliver the 3024/q88 photo + q90 avatar quality to mobile users (it's live on web).
- **Optional:** add a `flutter build apk --debug` step to Flutter CI (would have caught the #41 manifest bug).
- Finish the Play subscription setup (RevenueCat Android `goog_` SDK key + RTDN) and the App Store / Play review submissions.

---

## 8. Companion docs index

| Doc | What it covers |
|---|---|
| `.claude/CLAUDE.md` | **Authoritative** development guardrails — scope, architecture, patterns, all hard rules |
| `docs/PRD.md` | Product requirements, features, branding |
| `docs/ARCHITECTURE.md` | Full technical architecture, data model, security, deployment |
| `docs/AUTHENTICATION.md` | Auth orientation — providers, flows, iOS/Android/web specifics, reviewer demo account |
| `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` | The 5-layer token-refresh defense, in full |
| `docs/AGE_VERIFICATION_RUNBOOK.md` | 13+ age gate (claim-based, Entra config) |
| `docs/EVENT_DM_CHAT_ARCHITECTURE.md` | Event-scoped 1:1 DMs (Web PubSub) |
| `docs/VIDEO_ARCHITECTURE_DECISIONS.md` | 17 video decisions (transcoder, HLS SAS, player, rotation, etc.) |
| `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` | As-built Azure video infra (ACR, Container Apps, queue, RBAC, image version history) |
| `docs/VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md` | Local-first uploader playback |
| `docs/NOTIFICATION_SYSTEM.md` | Push architecture (FCM + Web PubSub), all notification types |
| `docs/WEB_CLIENT_ARCHITECTURE.md` | Web client architecture, deploy, CORS/CSP, MSAL.js, entitlement gating |
| `docs/INVITE_INSTALL_REFERRER.md` | Install-aware QR invites + deferred deep linking |
| `docs/DEPLOYMENT_STATUS.md` | Deploy tracking — what's live vs pending, per item |
| `docs/BETA_OPERATIONS_RUNBOOK.md` | Incident response, troubleshooting, backups, key rotation, cost |
| `docs/BETA_TEST_PLAN.md` | Manual smoke-test checklist (dual-device) |
| `docs/VIDEO_V1_TESTING_CHECKLIST.md` | Video-specific manual tests |
| `docs/SECURITY_AUDIT_2026-06-04.md` | Pre-submission security audit — findings, fixes, don't-regress invariants |
| `docs/GENE.md` | Personal paywall-rollout punch list + secrets index (Gene's working notes) |
| `docs/PLAN.md` | Paywall implementation plan + status snapshot |
