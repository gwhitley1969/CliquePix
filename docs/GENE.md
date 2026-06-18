# GENE.md — Paywall Rollout Punch List

Personal tracking file for Gene. Pick up here when resuming the CLIQUE Pix paywall implementation.

Full plan lives at `C:\Users\genew\.claude\plans\okay-this-is-what-inherited-deer.md`.

Last updated **2026-06-18** — **✅ ANDROID PRODUCTION LIVE**: vc9 was **approved by Google and is live on the Play production track at 100%** — CLIQUE Pix's first production release on Google Play, first with working Android billing (confirmed via Play Console Publishing overview + Play Developer API). It published at 100% on approval (configured for 100%, not staged). **Short tail still owed:** (1) the purchase smoke test — now a *live-production* verification via Play Console → License testing (confirm a monthly + annual buy flips the entitlement + dismisses the paywall); (2) revert the temporary **Admin** grant on the RC service account (`revenuecat-play@clique-pix-d7fde.iam.gserviceaccount.com`) → least-privilege; (3) Android tester 1-year promos in RC (grantable once each tester's vc9 install creates their RC customer). Prior **2026-06-16** — **ANDROID BILLING UNBLOCKING**: the RevenueCat Play app is created and the **Android `goog_` SDK key is captured + wired into the client** (`goog_CxDvuOryuEQtBiylZjCbkabcdHF`, PR #62 merged to `main`, **versionCode bumped to 9**). RevenueCat is now fully wired for Android (Play products `plus_monthly:monthly` + `plus_annual:annual` active, both attached to the `plus` entitlement AND the `default` offering packages). **Two independent Google-side clocks remain before Android purchases work end-to-end:** (1) the service-account **"subscriptions API" permission** is still propagating (RC "Credentials need attention" shows ✅ inappproducts + ✅ monetization but ❌ subscriptions — the subscriptions API needs the **"Manage orders and subscriptions"** account permission; verified correct, now just Google propagation, ≤36h); (2) the **Payments-profile org-name verification** (BlueBuildApps→Xtend-AI docs submitted, in Google's review queue) — gates *activating/selling*. Full detail + the do-this-when-green steps: `DEPLOYMENT_STATUS.md` top entry. (Prior — 2026-06-11 **LOCKOUT INCIDENT RESOLVED**: all 14 users' backfilled trials expired 2026-06-09 → everyone hit the paywall, and Android's paywall rendered BLANK (placeholder `goog_` key + no PaywallView fallback); same-day fixes: trials extended **+30 days (now 2026-07-11)** via SQL; **reviewer `vwhitley1967@gmail.com` lifetime promo grant DONE + verified end-to-end**; two production backend bugs fixed + deployed; paywall never-blank fallback + router fixes on `main`. Prior: 2026-06-09 brand rename PR #47.)

---

## ✅ Session 2026-06-02 — what the assistant completed

- **Backend DEPLOYED live:** migrations 012+013 applied to `pg-cliquepixdb` (14 users backfilled, `trial_null=0`), `func publish` succeeded, `/api/health` 200, webhook verified 200. The paywall gate is **live** now → existing users ride a 7-day trial; **Phase 6 promo grants must land within 7 days.**
- **RevenueCat:** offering packages wired (`plus_monthly` → `$rc_monthly`, `plus_annual` → `$rc_annual`); webhook `whintgr721b9e5264` created + verified; iOS SDK key `appl_OvhNypnojnQSEebpQtBikJYTHBa` captured; `plus_annual` set to **$39.99 + 7-day intro offer** (live ASC had actually still been $29.99 with no intro offer until now); paywall `pw9ac01d9e31184633` **published + attached to `default`** (2026-06-03).
- **Azure:** KV secrets + Function App settings (`REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`) wired as Key Vault references and verified.

## Where we are RIGHT NOW — next clicks for Gene (all dashboard/store, no code)

0. **⏰ TRIAL CLOCK (2026-06-11):** every non-entitled user's trial now ends **2026-07-11**. Before that date either (a) finish Play billing so users can actually subscribe, (b) grant tester promos, or (c) extend trials again (same SQL — see DEPLOYMENT_STATUS 2026-06-11 entry). **Reviewer is permanently covered** (lifetime promo grant verified live). Tester grants: pick the 4 testers and grant 1-year promos in RC → Customers → Grant Promotional Entitlement — iOS testers' RC customers exist; Android-only testers won't until a versionCode-9 build with the real `goog_` key ships (grant returns 404 — skip, trial covers them).
   - **Android `goog_` key: ✅ DONE (2026-06-16)** — captured + wired into the client (PR #62, merged to `main`, versionCode 9). **Android billing is now fully unblocked (2026-06-17):** both Google clocks cleared (subscriptions-API credential VALIDATED + Payments-profile org-name verification approved), Play subscriptions created + active, and **RTDN wired**. **Remaining:** Android purchase smoke test on a vc9 build + revert the temporary Admin grant to least-privilege. See `DEPLOYMENT_STATUS.md` top entry "ANDROID BILLING".
1. ~~Publish + attach the paywall~~ **✅ DONE 2026-06-03** — `pw9ac01d9e31184633` published + attached to `default`. Subscription also renamed "CLIQUE Pix Plus" → "CLIQUE Pix" across legal pages, web, paywall, and App Store Connect (no free tier, so "Plus" was misleading).
2. **Verify Transfer Behavior = "Keep with previous App User ID"** (Project Settings → General). The API can't read it.
3. ~~Fix test-store prices~~ **WON'T FIX (2026-06-03)** — RevenueCat Test Store prices are **immutable once set** (greyed in dashboard, create-only API, no update/delete endpoint). Sandbox-only; real App Store prices already correct at $3.99/$39.99, so zero user impact.
4. **Submit** both IAPs (still `READY_TO_SUBMIT`) on the app version page.
5. **Phase 6 promo grants** (reviewer + 4 testers) — urgent, 7-day clock.
6. ~~Deploy legal pages~~ **✅ DONE 2026-06-03** — web client auto-deployed on merge; `clique-pix.com/docs/privacy` + `/docs/terms` verified live with the subscription disclosures.
7. **Android** (Phase 1b) — **tax verified 2026-06-03 ✅**; confirm **identity verification** is also green in Play Console (I can't check it), then the Android subscription setup + RevenueCat Play app proceed.

---

## 🔤 Brand rename → "CLIQUE Pix" — manual follow-ups (2026-06-09)

The wordmark was capitalized **"Clique Pix" → "CLIQUE Pix"** (whole word CLIQUE) across the codebase in PR #47 — 264 occurrences, 67 files. **Only the two-word brand phrase changed**; the feature noun "Clique"/"Cliques" and all identifiers (`cliquepix`, `clique_pix`, `clique-pix.com`, `com.cliquepix.*`, FCM channel ID, `CFBundleName=clique_pix`) are untouched.

**✅ Done + live (code-side — assistant completed):**
- **Web** — clique-pix.com landing + `/docs/privacy` + `/docs/terms` verified live as "CLIQUE Pix" (auto-deployed on merge).
- **Backend** — 2 user-facing error strings (age-gate + subscription-required) deployed via `func publish`; `/api/health` 200.
- **App display name** — `android:label` + iOS `CFBundleDisplayName` updated on `main`. Baked into the **Android AAB** (versionCode 6, rebuilt 2026-06-09, at `app/build/app/outputs/bundle/release/app-release.aab`) — **pending your Play upload**. iOS picks it up on the next `flutter build ipa` from the Mac.
- **Docs + memory** updated.

**⏳ Manual — dashboard / store / design only (assistant CANNOT do — no Apple/Google/Entra console access):**

*Stores*
- [ ] **App Store Connect** → App Information → **Name** → "CLIQUE Pix" (≤30 chars; rides the next version submission).
- [ ] **Play Console** → Main store listing → **App name** → "CLIQUE Pix".
- [ ] Verify the **subscription group + product display names** read "CLIQUE Pix" — the group was renamed to title-case "Clique Pix" on 2026-06-03 (before the all-caps decision), so update it to **CLIQUE Pix** (ASC Subscriptions + Play subscriptions).

*Sign-in screens (app name shown during auth — sourced from the identity provider, NOT our code)*
- [ ] **Entra app-registration display name** → "CLIQUE Pix" (Entra portal → App registrations → the app → Branding & properties) — shown on the CIAM sign-in/consent page.
- [ ] **Google OAuth consent screen** app name → "CLIQUE Pix" (Google Cloud Console → APIs & Services → OAuth consent screen) — used by Google federation.

*RevenueCat*
- [x] **Paywall copy — ✅ FIXED + PUBLISHED 2026-06-09.** The 3 stale strings in paywall `pw9ac01d9e31184633` — headline "Subscribe to Clique Pix" + the monthly/annual plan labels — were updated to "CLIQUE Pix" via the RevenueCat Paywall AI Editor (assistant) and verified (only those 3 strings changed; no layout/price/other-copy change — the paywall has no hardcoded prices, $39.99/$3.99 come from the store products at runtime). **Gene verified "Subscribe to CLIQUE Pix" and hit Publish 2026-06-09 — now live.**

*Design (wordmark rendered as pixels — needs redraw, not a text edit)*
- [ ] Logo / icon / splash: `app/assets/logo.png`, `app/assets/icon.png`, `webapp/public/assets/*`, iOS `LaunchImage`/`AppIcon`.
- [ ] App Store + Play **store screenshots** that show the old "Clique Pix" wordmark.

---

## Phase 1a — App Store Connect ✅ DONE

- ✅ Paid Apps Agreement Active
- ✅ Subscription Group: `CLIQUE Pix` (renamed from "CLIQUE Pix Plus" 2026-06-03 — no free tier, so "Plus" was misleading)
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

- [ ] App Store Connect → My Apps → CLIQUE Pix → App Information → **App Store Server Notifications V2**
  - Production Server URL: paste RC's URL
  - Sandbox Server URL: paste the SAME RC URL
  - Version: V2 (not V1 / legacy)

---

## Phase 1b — Google Play Console 🟢 UNBLOCKING (tax verified 2026-06-03)

**Update 2026-06-03:** Google emailed that the **tax information is VERIFIED ✅** — the EIN-name mismatch (IRS had "BlueBuildApps, LLC"; Google's TIN matching rejected "Xtend-AI LLC") is resolved. The Payments-profile blocker is clearing.

- ✅ **Tax info verified.**
- ❓ **Identity verification — CONFIRM IN PLAY CONSOLE.** Two checks were stacked; Google's email covered tax, not necessarily identity. The Payments profile is only **Active** when BOTH are verified. **The assistant CANNOT check this** — there's no Google Play Console / Google-account access via any connected MCP (only Azure + RevenueCat + GitHub). Verify manually at **Play Console → Setup → Payments profile** and **payments.google.com → Settings**: both Tax and Identity must show verified.

### ✅ RESOLVED — IRS / W-9 path (kept for history)

Tax is verified, so these are moot: the IRS-147c call (`800-829-4933`, EIN name-change BlueBuildApps → Xtend-AI, Form 147c letter) and the "retry W-9 as Xtend-AI" / "submit as BlueBuildApps" workaround. No further action on the tax side.

### Once Payments is fully Active (tax ✅ + identity confirmed) — DO THESE

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

- ✅ RevenueCat account + project `CLIQUE Pix` (project ID `04f5314d`)
- ✅ Entitlement `plus` created (verified)
- ✅ Offering `default` created (Monthly + Yearly packages; Lifetime removed)
- ✅ iOS app `CLIQUE Pix (App Store)` connected
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
- [x] **Paywalls v2 paywall** `pw9ac01d9e31184633` — **published + attached to `default` offering 2026-06-03.** Headline "Subscribe to CLIQUE Pix"; Terms/Privacy buttons → `clique-pix.com/docs/*`.

### Android side (updated 2026-06-17 — billing unblocked end-to-end)

- [x] **Add Google Play app in Apps & providers** (package `com.cliquepix.clique_pix`, service-account JSON uploaded). App `appbdff3c693e`.
- [x] **Import `plus_monthly` + `plus_annual` from Play, attach `plus` entitlement.** Play products `plus_monthly:monthly` (`prod346a7e0e37`) + `plus_annual:annual` (`prod8178fcaf60`) active in RC, both on entitlement `plus` (`entldcaccca2c3`).
- [x] **Attach to the offering packages** — assistant attached both Play products to `default` offering packages `$rc_monthly` + `$rc_annual` (2026-06-16; they were on the entitlement but missing from the packages, which would have left Android packages with no purchasable product).
- [x] **Capture Android public SDK key** → `goog_CxDvuOryuEQtBiylZjCbkabcdHF` (wired into the client, PR #62).
- [x] **Play subscriptions created + active (2026-06-16/17)** — `plus_monthly` "CLIQUE Pix (Monthly)" $3.99 (base plan `monthly`) + `plus_annual` "CLIQUE Pix (Annual)" $39.99 (base plan `annual`) + 7-day free-trial offer. Base-plan IDs link to RC `plus_monthly:monthly`/`plus_annual:annual`. Payments-profile org-name verification (BlueBuildApps→Xtend-AI) approved 2026-06-17, so they're activatable/sellable.
- [x] **Service-account "subscriptions API" permission — ✅ VALIDATED 2026-06-17.** Root cause was a **missing "Manage orders and subscriptions"** account-level permission (NOT propagation — the check sat at a stable 2-green/1-red for 24h+, the fingerprint of an absent permission, since all three checks share one JSON + one Google API). Granting it (temporarily via **Admin** on `revenuecat-play@clique-pix-d7fde.iam.gserviceaccount.com`) cleared the check within minutes. inappproducts + monetization were already ✅.
- [ ] **Revert Admin → least-privilege (security).** Swap the temporary Admin grant for the three permissions RC needs — View app info (read-only) · View financial data/orders · **Manage orders and subscriptions** — then re-validate once. The SA JSON is the production credential (gitignored `secrets/`); Admin is over-broad if it leaks.
- [x] **Configure RTDN — ✅ DONE 2026-06-17.** Topic `Play-Store-Notifications` via RC "Connect to Google" → pasted in Play Console (Monetize with Play → Monetization setup → Real-time developer notifications) → test received. Connect first failed with `"...users named in the policy do not belong to a permitted customer"` = **Domain Restricted Sharing** org policy (`iam.allowedPolicyMemberDomains`, on by default for orgs created ≥ 2024-05-03); fixed by temporarily overriding it to **Allow All** on project `clique-pix-d7fde` (IAM & Admin → Organization policies), then re-locking.
- [ ] *(cosmetic)* set the two Play products' RC `display_name` to `Plus Monthly`/`Plus Annual` (manual dashboard edit — no API tool for it; functionally irrelevant).

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
- [x] **Follow-up re-deploy 2026-06-05 (PR #21/#22/#23):** entitlement + webhook hardening re-published (`func azure functionapp publish func-cliquepix-fresh`). Webhook now returns **200 on any non-auth outcome** (no RC retry-storm) and **401 only** on bad/missing auth; non-UUID `app_user_id` is a clean no-op; `markExpired` TOCTOU closed; reviewer-lockout (null-expiry promo) fixed. `/api/health` 200; valid-signature webhook call verified 200. The two extra jest tests below (webhook event types + idempotency) shipped in #22/#23.

### Still TODO (non-blocking)

- [ ] Extra jest tests for webhook event types + idempotency dedup + out-of-order + auth-fail (`revenuecatWebhook.test.ts`).
- [ ] Add 2 operation declarations to `bicep/apim/main.bicep` (`/internal/revenuecat-webhook`, `/users/me/entitlement/refresh`) for IaC parity — **NO** rate-limit (6-incident history). APIM already routes them.

**Deploy order rule (satisfied): backend deployed BEFORE the Plan 2 mobile build hits TestFlight**, so the `entitlement` field exists and mobile won't null-crash.

---

## Phase 3 — Flutter mobile ✅ DONE 2026-06-02 (Plan 2)

Implemented + committed (6 commits): SDK v10, `EntitlementState` on `UserModel`, `RevenueCatService`, hosted paywall at `/paywall`, router gate on `effective_active`, nav hidden off-access, RC logIn/logOut in the auth lifecycle, `refreshEntitlement` + optimistic-flag/30s reconcile, Profile Manage/Restore + diagnostics, `version: 1.0.0+5`. **analyze 54 baseline · 96/96 tests · release APK green.**
- ✅ iOS public SDK key wired into `app/lib/core/constants/revenuecat_constants.dart` (`appl_OvhNypnojnQSEebpQtBikJYTHBa`).
- [x] **Android `goog_` SDK key wired (2026-06-16)** — `goog_CxDvuOryuEQtBiylZjCbkabcdHF` in `revenuecat_constants.dart` (PR #62, merged to `main`, versionCode 9). Replaces the placeholder + disarms the `isPlaceholderKey` short-circuit so `Purchases.configure()` runs on Android.
- [ ] **On-device smoke** + `flutter build ipa --release` — needs a device + the published paywall + an Apple sandbox tester.
- [~] **Android on-device purchase smoke** — both Google clocks cleared + subscriptions active; **vc9 was APPROVED by Google and is LIVE on the production track at 100% (2026-06-18)** — it published at 100% on approval, so this is now a *live-production* verification, not a pre-ramp gate. Still run it: test the buy via Play Console → Setup → **License testing** (no charge) and confirm the entitlement flips + paywall dismisses. If billing is broken, halt/roll back via a new release. See DEPLOYMENT_STATUS "ANDROID PRODUCTION RELEASE".

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
- lint clean, build green. ✅ **Deployed + verified live 2026-06-03** (auto-deploy on merge to main).

---

## Phase 5 — Privacy + Terms ✅ EDITED + COMMITTED 2026-06-02 (deploy pending)

Required by Apple Guideline 3.1.2 + Google Play Subscriptions policy. Must ship to `clique-pix.com` BEFORE App Store / Play Store review. **Files are `webapp/public/docs/*` (not `website/docs/*`).**

- [x] `webapp/public/docs/privacy.html`: subscription/billing data section + RevenueCat subprocessor link (commit `432e4f5`).
- [x] `webapp/public/docs/terms.html`: subscription terms — CLIQUE Pix Plus, $3.99/$39.99, 7-day trial, auto-renew/charge/cancel disclosures (commit `83aaafd`). Effective dates bumped to 2026-06-02.
- [x] **Deploy webapp via GH Actions** (= PLAN.md Task 7) — **✅ DONE 2026-06-03; live + verified at `clique-pix.com/docs/*` (App Store URL-check requirement met).**

---

## Phase 6 — Beta tester + reviewer migration

**HARD SEQUENCING RULE (CORRECTED 2026-06-02):** A promo grant requires the RevenueCat customer to ALREADY EXIST — created only when the account runs the SDK build and signs in (`Purchases.logIn(users.id)`). You **cannot** grant before the gated build ships (a grant to a never-seen App User ID returns 404). **Correct order: ship the gated build → reviewer + testers sign in once (the backfilled 7-day trial covers them, zero lockout) → grant the promos within that 7-day window.**

> **Reviewer account is `vwhitley1967@gmail.com`** (supersedes the bogus `appreview@cliquepix.com` from older notes — `cliquepix.com` is not an owned domain and never had a mailbox; the app domain is `clique-pix.com`, which also has no email addresses) → `users.id a16a8a7c-74ca-4efc-9460-27c08db4061e` (**recreated 2026-06-11** — the original `325e4455-…` account was created hours BEFORE the 2026-05-06 OTP→password flow switch and was permanently OTP per Microsoft behavior; deleted + re-signed-up under the password flow, **lifetime grant re-issued + verified active in Postgres**). Of the 11 tester emails, only 3 currently have `users` rows by email (`chasebatchelor`, `rfcarpen1`, + the reviewer); the rest signed in via Google/Apple federation where `email_or_phone` differs — reconcile via the full user list once each has signed in on the gated build.

> **Backend prerequisite — now SAFE (PR #21, deployed 2026-06-05):** this promo-grant path had a reviewer-lockout bug until recently. `forceSyncFromRcApi` required a non-null future `expires_date`, but Promotional/lifetime grants return `expires_date: null`, so a reviewer/tester who got a promo grant and tapped "Refresh Subscription" (or hit the 30s post-purchase auto-recovery) was force-deactivated and hard-paywalled out of the WHOLE app — an App Store reviewer-rejection risk on exactly this mechanism. Fixed: a `plus` grant with `expires_date===null` is now active-forever, and the lag-guard shields null-expiry promos. Live in prod (#22/#23 backend deploy 2026-06-05, health 200, webhook valid-signature verified). Phase 6 grants can now be exercised safely.

- [ ] Compile beta tester user IDs from Postgres:
  ```sql
  SELECT id, email_or_phone, created_at FROM users WHERE created_at < '<cutoff>';
  ```
- [ ] In RC dashboard → Customers → each ID → Grant Promotional Entitlement `plus`:
  - [x] `vwhitley1967@gmail.com` → **lifetime** — **✅ DONE 2026-06-11** (granted via RC MCP, expires 2101-01-01; **verified end-to-end**: webhook → fixed `app_user_id` resolution → `users.entitlement_active=TRUE`, store `PROMOTIONAL`. Note: the FIRST grant attempt was silently dropped by the pre-fix webhook bug — re-granting with a new expiry re-fired the event after the backend fix deployed.)
  - [ ] Each of the 4 current beta testers → **1 year** (their 30-day trial covers them until 2026-07-11; Android-only testers have no RC customer yet — grant after the `goog_` key ships)
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
