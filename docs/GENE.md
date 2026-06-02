# GENE.md — Paywall Rollout Punch List

Personal tracking file for Gene. Pick up here when resuming the Clique Pix Plus paywall implementation.

Full plan lives at `C:\Users\genew\.claude\plans\okay-this-is-what-inherited-deer.md`.

Last updated **2026-06-02** — backend deployed live + most RevenueCat/Azure config done this session (via MCP). See session summary below.

---

## ✅ Session 2026-06-02 — what the assistant completed

- **Backend DEPLOYED live:** migrations 012+013 applied to `pg-cliquepixdb` (14 users backfilled, `trial_null=0`), `func publish` succeeded, `/api/health` 200, webhook verified 200. The paywall gate is **live** now → existing users ride a 7-day trial; **Phase 6 promo grants must land within 7 days.**
- **RevenueCat:** offering packages wired (`plus_monthly` → `$rc_monthly`, `plus_annual` → `$rc_annual`); webhook `whintgr721b9e5264` created + verified; iOS SDK key `appl_OvhNypnojnQSEebpQtBikJYTHBa` captured; `plus_annual` set to **$39.99 + 7-day intro offer** (live ASC had actually still been $29.99 with no intro offer until now); paywall AI **draft** `pw9ac01d9e31184633` created.
- **Azure:** KV secrets + Function App settings (`REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`) wired as Key Vault references and verified.

## Where we are RIGHT NOW — next clicks for Gene (all dashboard/store, no code)

1. **Publish + attach the paywall draft** `pw9ac01d9e31184633` to the `default` offering (open the editor → Publish). RC has no API for this.
   - Editor: https://app.revenuecat.com/projects/04f5314d/paywalls/pw9ac01d9e31184633/builder
2. **Verify Transfer Behavior = "Keep with previous App User ID"** (Project Settings → General). The API can't read it.
3. **Fix test-store prices**: `monthly` $9.99 → $3.99, `yearly` $79.99 → $39.99 (Products → Test Store). Real-device prices already come from the App Store products and are correct.
4. **Submit** both IAPs (still `READY_TO_SUBMIT`) on the app version page.
5. **Phase 6 promo grants** (reviewer + 4 testers) — urgent, 7-day clock.
6. **Deploy legal pages** (Phase 5 — `webapp/public/docs/*` edited + committed; GH Actions deploy pending).
7. **Android** (Phase 1b) — still blocked on the W-9/IRS item.

---

## Phase 1a — App Store Connect ✅ DONE

- ✅ Paid Apps Agreement Active
- ✅ Subscription Group: `Clique Pix Plus`
- ✅ `plus_monthly` Ready to Submit ($3.99 / mo, Family Sharing OFF, 5 English-speaking countries)
- ✅ `plus_annual` Ready to Submit ($39.99 / yr, 7-day free trial intro offer, Family Sharing OFF)
- ✅ App Store Connect API key (`AuthKey_TP9C6PA769.p8` in `secrets/`)
- ✅ In-App Purchase Subscription Key (`SubscriptionKey_7K28U2Z2B2.p8` in `secrets/`)
- ✅ App Privacy updated: Purchases / Purchase History declared
- ✅ Vendor number captured by RC: 93920852

### Reference values (non-secret)

- Apple App ID: `6766294274`
- Bundle ID: `com.cliquepix.app`
- Team ID: `4ML27KY869`
- Apple Issuer ID: stored in your secrets notes
- Subscription Key ID: `7K28U2Z2B2`
- API Key ID: `TP9C6PA769`

### Apple paste-back still owed (after RC webhook URL is generated)

- [ ] App Store Connect → My Apps → Clique Pix → App Information → **App Store Server Notifications V2**
  - Production Server URL: paste RC's URL
  - Sandbox Server URL: paste the SAME RC URL
  - Version: V2 (not V1 / legacy)

---

## Phase 1b — Google Play Console ⏸️ PAUSED

Blocked on Payments profile verification. Two issues stacked:

- ⚠️ **Tax info declined** — IRS still has "BlueBuildApps, LLC" registered to the EIN; Google's TIN matching rejects "Xtend-AI LLC" submissions
- ⏳ **Identity verification submitted, Google reviewing** (1-2 business days)

### Real fix — call the IRS

- [ ] **Call IRS Business Specialty Line: `800-829-4933`** (Mon-Fri 7am-7pm local)
  - Ask them to update the legal name on the EIN due to LLC name change (BlueBuildApps → Xtend-AI)
  - Have ready: EIN, old name, new name, NC Secretary of State filing date
  - Request a **Form 147c letter** (current name confirmation, arrives by mail 1-2 weeks)
- [ ] Once IRS database updated (often same day), retry W-9 on Google as `Xtend-AI LLC`

### Workaround if you need Google unblocked sooner

- [ ] Submit W-9 as `BlueBuildApps, LLC` (matches IRS records right now)
- Caveat: Year-end 1099-K issues under BlueBuildApps; talk to your accountant first

### Once Payments is Active

- [ ] Create subscription `plus_monthly` (Base plan: monthly, $3.99, auto-renewing, 5 English-speaking countries)
- [ ] Create subscription `plus_annual` (Base plan: annual, $39.99, auto-renewing, 5 countries)
  - [ ] Add offer: `free-trial`, 7-day free trial, eligibility "Developer determined" → new subscribers only
- [ ] Activate base plans (toggle — easy to miss!)
- [ ] App content → Data Safety → declare `Financial info → Purchase history`, list RevenueCat as partner
- [ ] Settings → License testing → add your email + beta tester Google accounts
- [ ] Google Cloud Console → IAM → create service account `revenuecat-play` (Pub/Sub Admin role)
  - [ ] Download JSON key, save to `secrets/`
  - [ ] Invite the service account email into Play Console with: View app info / View financial data / Manage orders / Manage subscriptions
- [ ] Paste-back RTDN topic name from RC (after Phase 1c Android app added in RC)

### Reference values (non-secret)

- Package name: `com.cliquepix.clique_pix`
- AAB sitting in Open Testing: versionCode=4 (this won't be the paywall build; that'll be versionCode=5)

---

## Phase 1c — RevenueCat dashboard 🟡 IN PROGRESS

### Done

- ✅ RevenueCat account + project `Clique Pix` (project ID `04f5314d`)
- ✅ Entitlement `plus` created (verified)
- ✅ Offering `default` created (Monthly + Yearly packages; Lifetime removed)
- ✅ iOS app `Clique Pix (App Store)` connected
  - Subscription Key uploaded (Key ID `7K28U2Z2B2`)
  - App Store Connect API Key uploaded (Key ID `TP9C6PA769`)
  - Issuer ID populated
  - Vendor number 93920852 auto-pulled (proves the API call works)
  - Small Business Program flag: enrolled (start date 2026-01-28)
- ✅ Apple products imported: `plus_monthly` + `plus_annual` (both Ready to Submit)
- ✅ Both Apple products attached to `plus` entitlement
- ✅ Apple Server Notification URL generated (paste back into Apple)

### iOS side — status (updated 2026-06-02)

- [x] **Attach `plus_monthly` → Monthly package** + **`plus_annual` → Annual (Yearly) package** in the `default` offering. *(done via MCP — App Store products attached alongside the test-store ones)*
- [ ] **Verify Transfer Behavior = "Keep with previous App User ID"** (Project Settings → General). **← STILL TODO; the API can't read this, so Gene must check the dashboard.**
- [x] **Webhook configured** → `https://api.clique-pix.com/api/internal/revenuecat-webhook`, `Bearer <secret>` (secret in Key Vault). Verified **200**. *(`whintgr721b9e5264`)*
- [x] **Secret API Key** generated → Key Vault `revenuecat-secret-api-key`.
- [x] **iOS public SDK key** captured → `appl_OvhNypnojnQSEebpQtBikJYTHBa`. *(still must land in `app/lib/core/constants/revenuecat_constants.dart`, Phase 3)*
- [~] **Paywalls v2 paywall** — AI **draft `pw9ac01d9e31184633`** created (dark `#0E1525`, gradient header/CTA, annual "Best Value — 7-Day Free Trial" badge, benefits list, auto-renew disclaimer, Restore). **← STILL TODO: review + Publish + attach to the `default` offering in the dashboard (no publish API).**

### Android side (do after Google Play Payments is Active and service account ready)

- [ ] Add Google Play app in Apps & providers (package `com.cliquepix.clique_pix`, upload service-account JSON)
- [ ] Import `plus_monthly` + `plus_annual` from Play, attach `plus` entitlement
- [ ] Attach to the same offering packages
- [ ] Capture Android public SDK key (`goog_...`)
- [ ] Configure RTDN — copy the Pub/Sub topic RC generates and paste into Play Console

---

## Phase 1d — Azure Key Vault + Function App settings ✅ DONE 2026-06-02

- [x] Key Vault `kv-cliquepix-prod`: `revenuecat-webhook-secret` + `revenuecat-secret-api-key` present.
- [x] Function App `func-cliquepix-fresh` settings as Key Vault references: `REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`. MI confirmed `Key Vault Secrets User` on the vault → references resolve.
- [x] Restarted (the app-setting change triggers a restart).
- [x] Smoke verified via self-sent curl (`--ssl-no-revoke`): webhook **200** on correct Bearer, **401** on bad/missing. *(Optional: also click RC "Send test event" to confirm RC-side delivery.)*

---

## Phase 2 — Backend code ✅ MOSTLY DONE

### Done

- ✅ Migration `012_revenuecat_entitlements.sql` (9 columns + partial index)
- ✅ `backend/src/shared/services/entitlementService.ts`
- ✅ `backend/src/shared/services/revenuecatRestClient.ts`
- ✅ `backend/src/shared/middleware/revenuecatAuthMiddleware.ts`
- ✅ `backend/src/functions/revenuecatWebhook.ts`
- ✅ `authMiddleware.ts` extended SELECT
- ✅ `avatarEnricher.ts` `buildAuthUserResponse` emits `entitlement`
- ✅ `requireActiveEntitlement` applied to 39 gated endpoints
- ✅ `entitlementReconciliationTimer` (6-hourly)
- ✅ `deleteMe` calls RC `DELETE /subscribers/{id}` (GDPR)
- ✅ `POST /api/users/me/entitlement/refresh` endpoint
- ✅ 164/164 existing tests still green, tsc clean

### Deploy — DONE 2026-06-02

- [x] **Deploy backend**: `func azure functionapp publish func-cliquepix-fresh` — app **Running**.
- [x] **Apply migration 012 (+ 013)** to `pg-cliquepixdb` — 14 users backfilled, `trial_null=0`.
- [x] `npm run build && npm test` — **174/174** green, tsc clean.
- [x] Webhook route confirmed live through `api.clique-pix.com` (200 on correct Bearer).

### Still TODO (non-blocking)

- [ ] Extra jest tests for webhook event types + idempotency dedup + out-of-order + auth-fail (`revenuecatWebhook.test.ts`).
- [ ] Add 2 operation declarations to `bicep/apim/main.bicep` (`/internal/revenuecat-webhook`, `/users/me/entitlement/refresh`) for IaC parity — **NO** rate-limit (6-incident history). APIM already routes them.

**Deploy order rule (satisfied): backend deployed BEFORE the Plan 2 mobile build hits TestFlight**, so the `entitlement` field exists and mobile won't null-crash.

---

## Phase 3 — Flutter mobile ✅ DONE 2026-06-02 (Plan 2)

Implemented + committed (6 commits): SDK v10, `EntitlementState` on `UserModel`, `RevenueCatService`, hosted paywall at `/paywall`, router gate on `effective_active`, nav hidden off-access, RC logIn/logOut in the auth lifecycle, `refreshEntitlement` + optimistic-flag/30s reconcile, Profile Manage/Restore + diagnostics, `version: 1.0.0+5`. **analyze 54 baseline · 96/96 tests · release APK green.**
- ✅ iOS public SDK key wired into `app/lib/core/constants/revenuecat_constants.dart` (`appl_OvhNypnojnQSEebpQtBikJYTHBa`).
- [ ] **Android `goog_` SDK key** — still a placeholder in `revenuecat_constants.dart` (Play blocked). iOS-first until then.
- [ ] **On-device smoke** + `flutter build ipa --release` — needs a device + the published paywall + an Apple sandbox tester.

Original checklist (all implemented unless noted above):

- [ ] `flutter pub add purchases_flutter purchases_ui_flutter` (in `app/`)
- [ ] Bump `version: 1.0.0+5` in `pubspec.yaml`
- [ ] Create `app/lib/core/constants/revenuecat_constants.dart` (platform-specific keys)
- [ ] Create `app/lib/services/revenuecat_service.dart`
- [ ] Create `app/lib/features/paywall/**` (domain + presentation)
- [ ] Modify `user_model.dart` (add `entitlement` field)
- [ ] Modify `auth_providers.dart` (wire `Purchases.logIn` / `logOut` in lifecycle)
- [ ] Modify `auth_repository.dart` (`resetSession` also calls `Purchases.logOut()`)
- [ ] Modify `app_router.dart` (paywall redirect)
- [ ] Modify `shell_screen.dart` (hide bottom nav when no entitlement)
- [ ] Modify `profile_screen.dart` (Manage Subscription / Restore / Refresh tiles)
- [ ] Modify `token_diagnostics_screen.dart` (entitlement section in debug view)
- [ ] Modify `main.dart` (`Purchases.configure` in `performDeferredInit`)
- [ ] Race-window handling (optimistic entitlement on purchase success → 30s auto-recovery via `/entitlement/refresh`)
- [ ] `flutter analyze` — preserve 54-issue baseline
- [ ] `flutter test` — preserve 87/87 baseline + add paywall tests
- [ ] Build `flutter build apk --release` and `flutter build ipa --release`

---

## Phase 4 — Web client (minimal, mobile-first) ✅ DONE 2026-06-02 (Plan 4)

- [x] `webapp/src/models/index.ts` — added `Entitlement` + `entitlement?` (camelCase).
- [x] `webapp/src/auth/EntitlementGuard.tsx` + `webapp/src/features/paywall/SubscribeInAppScreen.tsx` created.
- [x] Web router gates the app shell on `effective_active`; `/profile` + `/subscribe` exempt; allowlist `/subscribe`,`/profile`,`/login`,`/docs/*`,`/`.
- [x] `ProfileScreen.tsx` — "Manage Subscription" link.
- lint clean, build green. **Deploys with the web client (Task 7 SWA deploy).**

---

## Phase 5 — Privacy + Terms ✅ EDITED + COMMITTED 2026-06-02 (deploy pending)

Required by Apple Guideline 3.1.2 + Google Play Subscriptions policy. Must ship to `clique-pix.com` BEFORE App Store / Play Store review. **Files are `webapp/public/docs/*` (not `website/docs/*`).**

- [x] `webapp/public/docs/privacy.html`: subscription/billing data section + RevenueCat subprocessor link (commit `432e4f5`).
- [x] `webapp/public/docs/terms.html`: subscription terms — Clique Pix Plus, $3.99/$39.99, 7-day trial, auto-renew/charge/cancel disclosures (commit `83aaafd`). Effective dates bumped to 2026-06-02.
- [ ] **Deploy webapp via GH Actions** (= PLAN.md Task 7) — **← STILL TODO; must be live on `clique-pix.com/docs/*` BEFORE App Store submission (Apple checks the URLs).**

---

## Phase 6 — Beta tester + reviewer migration

**HARD SEQUENCING RULE (CORRECTED 2026-06-02):** A promo grant requires the RevenueCat customer to ALREADY EXIST — created only when the account runs the SDK build and signs in (`Purchases.logIn(users.id)`). You **cannot** grant before the gated build ships (a grant to a never-seen App User ID returns 404). **Correct order: ship the gated build → reviewer + testers sign in once (the backfilled 7-day trial covers them, zero lockout) → grant the promos within that 7-day window.**

> **Reviewer account is now `vwhitley1967@gmail.com`** (supersedes the old `appreview@cliquepix.com` in older notes) → `users.id 325e4455-b1b8-461e-a844-6f158cffaf84`, grant lifetime (~2100). Of the 11 tester emails, only 3 currently have `users` rows by email (`chasebatchelor`, `rfcarpen1`, + the reviewer); the rest signed in via Google/Apple federation where `email_or_phone` differs — reconcile via the full user list once each has signed in on the gated build.

- [ ] Compile beta tester user IDs from Postgres:
  ```sql
  SELECT id, email_or_phone, created_at FROM users WHERE created_at < '<cutoff>';
  ```
- [ ] In RC dashboard → Customers → each ID → Grant Promotional Entitlement `plus`:
  - `appreview@cliquepix.com` → **lifetime**
  - Each of the 4 current beta testers → **1 year**
- [ ] Update App Store Connect review notes with the reviewer + sandbox tester instructions
- [ ] Document grants in `docs/BETA_OPERATIONS_RUNBOOK.md` under new "Subscription comp grants" section

---

## Phase 7 — Docs to write/update

- [ ] New: `docs/PAYWALL_ARCHITECTURE.md` (canonical reference)
- [ ] New: `docs/REVENUECAT_RUNBOOK.md` (ops: promo grants, debugging, key rotation)
- [ ] Update `.claude/CLAUDE.md` (paywall is v1 now, no-free-tier guardrail)
- [ ] Update `docs/PRD.md` §6 Non-Goals + add §5.15 Subscription Paywall
- [ ] Update `docs/ARCHITECTURE.md` (entitlement columns + webhook architecture)
- [ ] Update `docs/BETA_TEST_PLAN.md` (new §13 — 22 paywall test rows)
- [ ] Update `docs/BETA_OPERATIONS_RUNBOOK.md` (subscription incidents)
- [ ] Update `docs/DEPLOYMENT_STATUS.md` (top entry tracking this rollout)

---

## Phase 8 — Submit and ship

Once everything above is green:

- [ ] Submit new iOS build (versionCode=5) to TestFlight with `plus_monthly` + `plus_annual` attached on the version page
- [ ] Submit new Android AAB to Play Internal Test track
- [ ] Beta verification: 22-row BETA_TEST_PLAN §13 pass on both iOS and Android
- [ ] After 1-week soak: promote to production

---

## Reference: secrets index (locations, NOT values)

| Secret | Where it lives |
|---|---|
| Apple App Store Connect API .p8 | `secrets/AuthKey_TP9C6PA769.p8` |
| Apple In-App Purchase Subscription Key | `secrets/SubscriptionKey_7K28U2Z2B2.p8` |
| Apple Issuer ID | Personal notes |
| RC test API key | Personal notes (`test_hvz...`) |
| RC iOS public SDK key | Personal notes (after Phase 1c capture) |
| RC Android public SDK key | Personal notes (after Phase 1c Android add) |
| RC Secret API Key | Personal notes + Azure Key Vault (`revenuecat-secret-api-key`) |
| RC webhook bearer | Personal notes + Azure Key Vault (`revenuecat-webhook-secret`) |
| Google Play service-account JSON | `secrets/<name>.json` (after Phase 1b) |

All of `secrets/` is gitignored via `*.p8`, `*.json` patterns. Verify nothing in there ever lands in a commit before pushing.

---

## Where to resume after a break

1. Open this file: `docs/GENE.md`
2. Look at "Where we are RIGHT NOW" at the top
3. Tell the assistant: "Resuming paywall work — see docs/GENE.md"
4. Next click is the Offerings page in RC to attach products to packages
