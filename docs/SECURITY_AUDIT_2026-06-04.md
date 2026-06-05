# Security & Detrimental-Bug Audit — 2026-06-04

Canonical record of the pre-App-Store-submission security audit and the fixes that shipped on branch `security/audit-fixes-2026-06-04`. Read this before touching auth, the entitlement/paywall paths, media deletion, the upload-confirm flow, or the FCM token lifecycle — the "Don't regress these" section at the bottom lists invariants that were added deliberately.

**Context at audit time:** RevenueCat paywall live in production (deployed 2026-06-02), days from App Store submission and real subscribers. Baselines: backend 174/174 jest, Flutter 96/96, webapp lint+build green.

---

## Method

Six parallel adversarial audit dimensions (each prompted to *attack*, not describe), every Critical/High finding independently re-verified against source before it was trusted, then a `make_interval`-style direct read of every claim that drove a fix. Dimensions:

1. AuthN/AuthZ & IDOR
2. Payments, entitlement & trial correctness
3. Injection, input validation & media pipeline
4. Secrets, data exposure, dependencies & CI
5. Client-side gates & platform config
6. Concurrency, lifecycle & destructive-path correctness

**Headline:** no remote, unauthenticated data-breach-class hole. Fundamentals verified sound — parameterized SQL, `execFile`+array-args ffmpeg (no shell injection), blob-scoped User Delegation SAS, JWT issuer/audience/RS256/JWKS validation, constant-time webhook compare, no committed secrets in git history, no token/SAS/PII in logs, error handler never leaks stacks, MSAL broker config intact, React default-escaping with no raw-HTML sink.

---

## Findings & disposition

Severity legend: 🔴 Critical · 🟠 High · 🟡 Medium · ⚪ Low/latent.

| ID | Sev | Finding | Status |
|----|-----|---------|--------|
| C1 | 🔴 | Invite codes 32-bit + no rate limiting → brute-forceable to join private cliques | ✅ Fixed `85116d2` |
| C2 | 🔴 | Video HLS/fallback/poster blobs orphaned on all 4 delete paths (breaks auto-delete promise + GDPR + cost) | ✅ Fixed `7e2dd75` |
| H1 | 🟠 | `forceSyncFromRcApi` could permanently lock out a just-paid subscriber (RC API lag) | ✅ Fixed `b40e978` |
| H2 | 🟠 | Orphan-cleanup raced upload-confirm with no atomic claim | ✅ Fixed `b40e978` |
| H3 | 🟠 | Internal transcoder callback is a function key, not managed identity — docs claimed otherwise | ✅ Docs corrected `ae37344` (code change deferred to v1.5) |
| H4 | 🟠 | `assetlinks.json` carries the debug keystore fingerprint | ⏳ Gene to apply before Android prod |
| H5 | 🟠 | Dependency CVEs (HIGH axios + fast-xml-builder) | ✅ Fixed `85116d2` |
| H6 | 🟠 | FCM token never de-registered on sign-out / account delete | ✅ Fixed `ae37344` |
| M1 | 🟡 | `entitlement_ids` empty-array bypasses the non-plus filter (latent) | ⬜ Open (low urgency) |
| M2 | 🟡 | `entitlementRefresh` in-process throttle not multi-instance-safe | ⬜ Open |
| M3 | 🟡 | 403-vs-404 existence oracles (`getPhoto`, `deletePhoto`, `deleteVideo`, `createOrGetDmThread`) | ⬜ Open |
| L1 | ⚪ | `avatars.ts` snooze used template-literal SQL `INTERVAL` (static today) | ✅ Fixed `85116d2` |
| L2 | ⚪ | HLS manifest rewriter signs any line, no `segment_\d+\.ts` allowlist (defense-in-depth) | ⬜ Open |
| L3 | ⚪ | Transcoder doesn't re-validate queue-message UUIDs (defense-in-depth) | ⬜ Open |
| L4 | ⚪ | Open-redirect: Flutter login `redirect` param + webapp `post_login_redirect` unvalidated | ⬜ Open |
| L5 | ⚪ | `/diagnostics/tokens` not in paywall allowlist | ⬜ Open |
| L6 | ⚪ | `/invite/:code` not in paywall allowlist — bounces lapsed users to paywall | ⬜ Open (product decision) |
| L7 | ⚪ | webapp `.env.*` force-tracked (public values only); CI lacks `permissions:`; webapp has no tests | ⬜ Open |
| — | — | **Trial farming** (delete → re-signup = fresh 7-day trial) | Accepted-by-design — see below |

---

## Fixes that shipped (with code references)

### C1 — Invite-code entropy (`85116d2`)
`backend/src/functions/cliques.ts` `generateInviteCode()`: `crypto.randomBytes(4)` (32-bit, 8 hex) → `crypto.randomBytes(16)` (128-bit, 32 hex). Join resolves by exact match so existing shorter codes keep working. Brute-force enumeration of private cliques is now infeasible even with no APIM rate limiting.

### C2 — Video-blob cleanup on every delete path (`7e2dd75`)
New `deleteMediaAssets(media)` in `backend/src/shared/services/blobService.ts` branches on `media_type`: **videos prefix-delete the per-media directory** (`photos/{cliqueId}/{eventId}/{videoId}/` — original + `hls/*` + `fallback.mp4` + `poster.jpg`); photos delete original + thumbnail explicitly (byte-identical to prior behavior). The trailing slash prevents a sibling `{videoId}X/` collision. Wired into the four sites that previously deleted only `blob_path` + `thumbnail_blob_path`:
- `events.ts` `deleteEvent`
- `auth.ts` `deleteMe` — sole-owner cliques + the user's own media in other cliques
- `timers.ts` expiry safety-net before event hard-delete

4 regression tests in `backend/src/__tests__/blobMediaCleanup.test.ts` (incl. the prefix-superset sibling guard).

### H1 — Entitlement lag-lockout guard (`b40e978`)
`entitlementService.ts` `forceSyncFromRcApi`: RC's REST API is eventually-consistent and lags webhooks by seconds–minutes — exactly when the client's 30s post-purchase auto-recovery calls `POST /api/users/me/entitlement/refresh`. The old code synthesized an EXPIRATION with `event_timestamp_ms = Date.now()` that won the ordering guard, deactivated the user, **and** made the real RENEWAL webhook get rejected as stale (sticky lockout). Now: if the DB already shows `active` + a future `entitlement_expires_at`, the sync **skips deactivation** and keeps the webhook-driven state (the 6h reconciliation timer handles genuine expiry). Synthetic events are only ever `RENEWAL` now — the system never down-grades via a synthetic event. 3 regression tests in `backend/src/__tests__/forceSyncLagGuard.test.ts`.

### H2 — Atomic upload-confirm claim (`b40e978`)
The orphan-cleanup timer deleted `status='pending'` rows + blobs past the 10/30-min window with no coordination against an in-flight confirm. Both sides now use a guarded atomic claim:
- **Confirm** (`photos.ts confirmUpload`, `videos.ts commitVideoUpload`): the status UPDATE is `... WHERE id=$1 AND status='pending'`. 0 rows ⇒ the timer reaped it: clean up + tell the client to retry (telemetry `photo_commit_lost_to_orphan_cleanup` / `video_commit_lost_to_orphan_cleanup`). Never enqueue a transcode for a deleted row.
- **Timer** (`timers.ts` orphan loops): `DELETE ... WHERE id=$1 AND status='pending'`, and the blob is deleted **only after winning the row**, so a confirming upload's blob is never deleted. Either ordering is now safe.

### H3 — Callback-auth docs corrected (`ae37344`)
`/api/internal/video-processing-complete` uses an **Azure Functions function key** (`authLevel: 'function'`, `?code=<FUNCTION_CALLBACK_KEY>`; key from Key Vault, set on the Container Apps Job), **not** managed identity. CLAUDE.md + ARCHITECTURE.md claimed managed identity at three sites — all corrected, with the key flagged as a sensitive shared secret. Managed-identity JWT validation remains deferred to v1.5 (needs an Azure AD app registration for the Function's audience). Code: `backend/transcoder/src/callbackService.ts`, `backend/src/functions/videos.ts` `videoProcessingComplete`.

### H5 — Dependency CVEs (`85116d2`)
`npm audit fix` across webapp/backend/transcoder. Cleared HIGH `axios` prototype-pollution (webapp, on the authenticated API-client path) and HIGH `fast-xml-builder` (backend + transcoder, transitive via Azure SDK). Transcoder now 0 vulns. **Deliberately not forced:** webapp 2 moderate (esbuild/vite, dev-only, breaking Vite-major to fix) and backend 4 moderate (transitive `uuid` via the Google API client, breaking `uuid@14`) — left to avoid breaking-change risk in a security batch; revisit on a normal dependency-maintenance pass.

### H6 — FCM de-register on sign-out/delete (`ae37344`)
New `DELETE /api/push-tokens` (authenticated, ungated, scoped to the caller: `DELETE WHERE token=$1 AND user_id=$2`). Flutter: `NotificationsApi.deletePushToken` → repository → `PushNotificationService.deregister()` (fetches the current FCM token, deletes it, best-effort). Wired into `AuthNotifier.signOut/deleteAccount` via an injected `deregisterPush` callback that runs **before** the JWT is cleared. Callback injection (not a typed field) avoids tightening the existing import cycle — `push_notification_service.dart` already imports `auth_providers.dart`.

### L1 — Parameterized avatar SQL (`85116d2`)
`avatars.ts` snooze: `NOW() + INTERVAL '${PROMPT_SNOOZE_DAYS} days'` (the only template-literal SQL fragment in the backend; static today but a future-refactor injection trap) → `NOW() + make_interval(days => $2)`.

---

## Trial farming — accepted-by-design

`auth.ts` stamps `trial_ends_at = NOW() + INTERVAL '7 days'` at first sign-in (COALESCE-preserved on re-auth). `deleteMe` calls RC `DELETE /subscribers`. A user who deletes their account and re-signs-up (same or new email — `ON CONFLICT (external_auth_id)`, and a new Entra account = new OID) gets a fresh 7-day trial. This is **inherent to any no-card trial** and is treated as an accepted tradeoff, not a hole. If it ever needs hardening, the option is a hashed-email fingerprint table that survives `deleteMe` (carries a GDPR tension — deliberate choice). Document any change to this stance in the canonical paywall doc when it's written.

---

## Verified CLEAN (do not re-flag without new evidence)

- **Git history:** no secrets ever committed; `secrets/` correctly ignored; no token/SAS/PII in `console.*` or `debugPrint`.
- **SQL:** 100% parameterized after L1. Transcoder uses `execFile` + array args (no shell injection). Blob paths server-generated from UUIDs.
- **JWT:** issuer/audience/RS256/JWKS enforced; `verifyJwtAllowExpired` scoped to `/api/telemetry/auth` only. RevenueCat webhook constant-time bearer compare.
- **Entitlement:** webhook idempotency (`event_id`) + out-of-order guard (`entitlement_updated_at`); CANCELLATION/BILLING_ISSUE/TRANSFER/PAUSE/unknown handled correctly; `effective_active` fails closed on null trial.
- **Client gates:** `EntitlementState.fromJson` fails closed; tokens only in `flutter_secure_storage` / sessionStorage; MSAL `Broker.msAuthenticator` at all PCA sites; no `BGTaskSchedulerPermittedIdentifiers`; `tools:node="remove"` exact-alarm suppression intact; webapp `setApiMsalInstance` ordering correct; React default-escaping, no raw-HTML sink, no `eval`.
- **Concurrency:** video prefix-delete scoping safe (UUID-derived, trailing slash); `video_ready` vs delete-during-transcode guarded (`status==='deleted'` check); notification sweep correct; token-refresh session-expired regex in sync across all three sites (`AuthInterceptor._isSessionExpired`, `AuthRepository._extractAadstsCode`, `AuthNotifier._handleSilentSignInFailure`).

---

## Remaining for Gene / follow-up

| Item | Action |
|------|--------|
| **H4 assetlinks** | Before Android production: replace the debug SHA256 in `webapp/public/.well-known/assetlinks.json` (and the `infrastructure/well-known/` template) with both the release upload-key and the Play App Signing fingerprint; redeploy SWA. Else App Links break on Play-signed installs and are sideload-spoofable. |
| **M1** | `entitlementService.ts:80-83` — require `entitlement_ids.includes('plus')` unless the event type is entitlement-agnostic (TRANSFER). |
| **M2** | `auth.ts` `entitlementRefresh` — replace the in-process `Map` throttle with a DB column (`users.last_refresh_called_at`) so it holds across instances. |
| **M3** | Convert `getPhoto` / `deletePhoto` / `deleteVideo` / `createOrGetDmThread` to a single JOINed membership SELECT → `NotFoundError` when absent (the `getVideo`/`getVideoPlayback` pattern), so non-members get 404 not 403. |
| **L2/L3** | Add a `segment_\d+\.ts` allowlist in `hlsManifestRewriter.ts`; re-validate queue-message UUIDs in `transcoder/runner.ts`. |
| **L4** | Require a leading `/` on the Flutter login `redirect` param and webapp `post_login_redirect` before navigating. |
| **L5/L6** | Decide paywall-allowlist policy for `/diagnostics/tokens` and `/invite/:code` (the latter currently bounces lapsed users to the paywall instead of letting them join). |
| **L7** | Add a "no secrets" header to webapp `.env.*` (or untrack); add `permissions: contents: read` to CI workflows; add auth/entitlement-guard tests to the webapp. |

---

## Don't regress these (invariants added by this audit)

1. **Invite codes stay ≥128-bit** (`crypto.randomBytes(16)`). Never shrink — there is no APIM rate limiting to compensate.
2. **All media deletion goes through `blobService.deleteMediaAssets`.** Never delete only `blob_path` + `thumbnail_blob_path` for a row that could be a video — that orphans HLS/fallback/poster. Any new delete path must call this helper.
3. **Upload-confirm UPDATEs are atomic claims** guarded on `status='pending'`, and the orphan timer deletes the blob only after a guarded row-delete wins. Don't revert to read-then-update or unconditional `DELETE WHERE id=$1`.
4. **`forceSyncFromRcApi` never down-grades a subscriber via a synthetic event.** Synthetic events are RENEWAL-only; deactivation requires DB corroboration (`active` + future expiry → skip).
5. **Sign-out / delete-account de-register the FCM token before clearing the JWT** (`AuthNotifier` → `deregisterPush` → `PushNotificationService.deregister`).
6. **The transcoder callback is function-key auth, not managed identity.** Treat `FUNCTION_CALLBACK_KEY` as a rotatable secret; don't re-document it as managed-identity until the v1.5 change actually lands.
7. **Invite-code validation `maxLength` MUST stay ≥ the generated code length.** `joinClique` uses `INVITE_CODE_MAX_LENGTH` (64) and `generateInviteCode()` emits 32 hex chars. A smaller limit truncates via `sanitizeString().slice()` and the exact-match lookup 404s every new clique join. Guarded by `inviteCode.test.ts`.
8. **Sole-owner clique deletion deletes media blobs first.** `leaveClique` enumerates the clique's media and calls `deleteMediaAssets` (invariant #2) BEFORE `DELETE FROM cliques` — otherwise CASCADE drops the rows and the blobs are orphaned with no cleanup path.
9. **The transcoder bounds queue redelivery itself (`MAX_DEQUEUE_COUNT`).** There is no Storage Queue dead-letter queue on the bare-SDK path — never re-document one. Malformed messages are deleted on dequeue.

---

## Follow-up re-audit — 2026-06-04 (independent pass)

A second, independent audit (13 finders across backend / transcoder / Flutter / webapp / config, each finding adversarially re-verified) ran after the fixes above merged. It confirmed the fixes held — **except the C1 invite fix introduced a join-breaking regression** — and surfaced new issues the first pass missed (broader Flutter/web/transcoder coverage). Raw 89 → 69 confirmed.

### Ship-blockers — fixed on branch `fix/audit-ship-blockers-2026-06-04`

| ID | Sev | Finding | Fix |
|----|-----|---------|-----|
| INV-1 | 🔴 | **Regression from C1 (`85116d2`):** `joinClique` validated `invite_code` with `maxLength 20`, truncating the new 32-char codes → exact-match lookup 404s → every clique created since C1 is un-joinable (link/QR/SMS/web). | `cliques.ts`: `INVITE_CODE_MAX_LENGTH = 64`, join uses it; `generateInviteCode` + constant exported; `inviteCode.test.ts` round-trip regression. |
| BLOB-1 | 🔴 | **C2 gap:** sole-owner `leaveClique` CASCADE-drops media rows but never deleted blobs (`cliques.ts` didn't import `blobService`) → permanent orphan of originals + HLS/fallback/poster. | `leaveClique` enumerates clique media and calls `deleteMediaAssets` before `DELETE FROM cliques`. |
| TQ-1 | 🔴 | **No real poison handling:** code + docs assumed Storage Queue auto-DLQs after 5 dequeues (false for the bare SDK). A persistently-failing callback or malformed message redelivered forever, respawning a 2-vCPU replica each cycle; the video stuck `processing`. | `MAX_DEQUEUE_COUNT` poison guard + terminal failure callback + delete in `runner.ts` / `queueService.ts`; malformed messages deleted on dequeue; false DLQ comments + `VIDEO_ARCHITECTURE_DECISIONS.md:173` corrected. |
| AUTH-1 | 🟠→cfg | **MSAL Android redirect = DEBUG keystore cert hash** (AndroidManifest + `msal_config.json` + `msal_constants.dart`) → sign-in fails on Play-signed builds. | ✅ Wired with the real Play App Signing hash (`4FsaiJ4wJWgM09R/hUh3osYJhgg=`). `androidRedirectUri` is now `String.fromEnvironment('MSAL_ANDROID_REDIRECT_URI')` defaulting to the **release** hash (fail-safe); debug opts in via `dart_defines/debug.json`. AndroidManifest registers **both** `<data>` paths. **Remaining (Gene):** register `msauth://com.cliquepix.clique_pix/4FsaiJ4wJWgM09R%2FhUh3osYJhgg%3D` in the Entra app registration (Authentication → Android). |
| H4 | 🟠→cfg | **assetlinks.json carried only the DEBUG SHA-256** → App Links fail (+ spoofable) on Play-signed installs. | ✅ Added the release Play App Signing SHA-256 (`BD:B3:DE:EC:…:60:75:FB`) to `webapp/public/.well-known/assetlinks.json` + the `infrastructure/` template (both fingerprints now present). **Remaining (Gene):** redeploy the SWA so `clique-pix.com/.well-known/assetlinks.json` serves the new file. |

### Other confirmed findings (tracked, not yet fixed)

High/medium to schedule:
- **PAY — reviewer/beta lockout:** ✅ **FIXED** (PR #21). `forceSyncFromRcApi` treated a `plus` with `expires_date: null` (RevenueCat **promotional**/lifetime grants — the reviewer + beta-tester mechanism) as inactive → `markExpired` locked them out on a "Refresh Subscription" tap. Now: a null-expiry `plus` is active-forever, and the lag-guard protects `active && (expires_at IS NULL OR future)`. `entitlementService.ts` `forceSyncFromRcApi` + 3 regression tests in `forceSyncLagGuard.test.ts`. Adversarially verified complete (every access gate keys off the `entitlement_active` boolean, not expiry math; the reconciliation timer already skips null-expiry rows). **Residual (LOW, pre-existing, accepted):** a revoked lifetime promo whose `EXPIRATION` webhook is *also* dropped is not auto-reconcilable — but the webhook `EXPIRATION` path still deactivates unconditionally, so this only bites if the webhook is lost; manual DB cleanup is the fallback for a hand-counted promo cohort.
- **PAY:** RevenueCat webhook returns 500 (not 200) on DB error / non-UUID `app_user_id` → RC retry storm, contradicting its own invariant. `revenuecatWebhook.ts:97`.
- **PAY:** reconciliation `markExpired` TOCTOU — guarded only on `active=TRUE`, not `expires_at < NOW()` → can deactivate a just-renewed payer. `entitlementService.ts:237`.
- **NOTIF:** in-app notification rows (`member_joined` / `new_photo` / `event_deleted`) are written only inside `if (tokens.length > 0)` → web-only users get none. `cliques.ts` / `photos.ts` / `events.ts`.
- **NOTIF:** FCM transient (5xx / timeout) failures purge valid push tokens. `fcmService.ts:94`.
- **TQ-2:** event-expiry hard-delete races a transcoding video → orphaned blobs + callback-404 retry storm. `videos.ts:916`.
- **START:** `_briefError` RangeError can crash app startup (blank screen) on a cold-start storage failure. `main.dart:121`.

Plus the prior-audit open items reconfirmed (M1/M2/M3, L2–L7, H4) and a longer low/info list (DM unread self-count; `error.toString()` on ~11 bootstrap screens; optimistic-entitlement flag not reset on account switch; Flutter resource leaks — `ui.Image`/temp files; web DM ownership OID-vs-UUID; transcoder HDR poster not tone-mapped; transcoder Docker runs as root; CI workflows lack `permissions:`; …). Full machine-readable finding set: workflow run `wf_1616060a-dc4`.
