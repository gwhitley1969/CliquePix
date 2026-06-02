# GENE.md — Paywall Rollout Punch List

Personal tracking file for Gene. Pick up here when resuming the Clique Pix Plus paywall implementation.

Full plan lives at `C:\Users\genew\.claude\plans\okay-this-is-what-inherited-deer.md`.

Last updated mid-session, working on Phase 1c (RevenueCat dashboard).

---

## Where we are RIGHT NOW

Wiring the imported Apple products into the RevenueCat **`default` offering** so the SDK can find them.

### Immediate next step

- [ ] **Product catalog → Offerings → `default`** → attach Apple products to packages
  - Monthly package → `plus_monthly` (Clique Pix App Store)
  - Annual / Yearly package → `plus_annual` (Clique Pix App Store)
  - Replace any Test Store placeholders that the wizard pre-attached

When that's done, packages are wired and the paywall has products to render.

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

### Still TODO on the iOS side

- [ ] **Attach `plus_monthly` to the Monthly package** in the `default` offering ← current step
- [ ] **Attach `plus_annual` to the Annual (Yearly) package** in the `default` offering
- [ ] **Verify Transfer Behavior = "Keep with previous App User ID"** (Project Settings → General). If it's still "Transfer to new App User ID", change it. Critical — preserves the KEEP_ATTRIBUTION model for shared Apple ID families
- [ ] **Configure webhook** (Project Settings → Webhooks → Add webhook):
  - URL: `https://api.clique-pix.com/api/internal/revenuecat-webhook`
  - Authorization header: `Bearer <generate random 32+ char secret>`
  - Save that secret — it becomes Azure Key Vault `revenuecat-webhook-secret` in Phase 1d
- [ ] **Generate Secret API Key** (Project Settings → API Keys → Secret keys → + Create):
  - Name: `Clique Pix backend`
  - Permissions: Read & Write on Subscribers + Entitlements
  - Save the key (`sk_...`) — becomes Azure Key Vault `revenuecat-secret-api-key` in Phase 1d
  - **Shown ONCE** — same as Apple's .p8
- [ ] **Capture production iOS public SDK key** (`appl_...`) from API Keys page
  - Goes into `app/lib/core/constants/revenuecat_constants.dart` in Phase 3
- [ ] **Design Paywalls v2 paywall** (Paywalls → Create):
  - Background dark `#0E1525`, gradient header `#00C2D1 → #2563EB → #7C3AED`
  - Headline "Clique Pix Plus", subhead "Unlimited private group sharing"
  - Package buttons (annual highlighted as "Best Value — 7-Day Free Trial")
  - Required disclaimer block (auto-renew language + Terms + Privacy links)
  - Restore Purchases button
  - Hero image: `app/assets/icon.png` or a screenshot

### Android side (do after Google Play Payments is Active and service account ready)

- [ ] Add Google Play app in Apps & providers (package `com.cliquepix.clique_pix`, upload service-account JSON)
- [ ] Import `plus_monthly` + `plus_annual` from Play, attach `plus` entitlement
- [ ] Attach to the same offering packages
- [ ] Capture Android public SDK key (`goog_...`)
- [ ] Configure RTDN — copy the Pub/Sub topic RC generates and paste into Play Console

---

## Phase 1d — Azure Key Vault + Function App settings

Once Phase 1c gives us the webhook secret + Secret API Key:

- [ ] Add to Key Vault `kv-cliquepix-prod`:
  - `revenuecat-webhook-secret` (the random bearer value pasted into RC webhook config)
  - `revenuecat-secret-api-key` (the `sk_...` from RC)
- [ ] Add app settings to Function App `func-cliquepix-fresh` as Key Vault references:
  - `REVENUECAT_WEBHOOK_SECRET`
  - `REVENUECAT_SECRET_API_KEY`
- [ ] Restart Function App to pick up the new settings
- [ ] Smoke test: in RC dashboard → Webhooks → "Send test event" → verify 200 OK + DB row updated

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

### Still TODO

- [ ] Write new jest tests for webhook + entitlement service (`backend/src/__tests__/revenuecatWebhook.test.ts`)
  - 9 event types + unknown-fallback + idempotency dedup + out-of-order timestamp + auth-fail
- [ ] Add 2 new operation declarations to `bicep/apim/main.bicep`:
  - `POST /api/internal/revenuecat-webhook`
  - `POST /api/users/me/entitlement/refresh`
  - **NO** rate-limit (per the 6-incident history)
- [ ] Run `npm run build && npm test` — target ~190/190 green
- [ ] Deploy backend: `func azure functionapp publish func-cliquepix-fresh`
- [ ] Apply migration 012 to `pg-cliquepixdb`

**Deploy order rule: backend deploys BEFORE mobile build hits TestFlight**, otherwise old backend returns no `entitlement` field and mobile crashes on null.

---

## Phase 3 — Flutter mobile

Once Phase 1c keys are captured + Phase 2 backend deployed.

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

## Phase 4 — Web client (minimal, mobile-first)

- [ ] Update `webapp/src/models/index.ts` (add `entitlement`)
- [ ] Create `webapp/src/features/paywall/SubscribeInAppScreen.tsx`
- [ ] Update web router (redirect to `/subscribe` if `!entitlement.active`)
- [ ] Update `webapp/src/features/profile/ProfileScreen.tsx` (Manage Subscription link)

---

## Phase 5 — Privacy + Terms

Required by Apple Guideline 3.1.2 + Google Play Subscriptions policy. Must ship to `clique-pix.com` BEFORE App Store / Play Store review.

- [ ] Update `website/docs/privacy.html`:
  - Subscription billing data section
  - RevenueCat as subprocessor (with link to `revenuecat.com/privacy/`)
- [ ] Update `website/docs/terms.html`:
  - Subscription title (Clique Pix Plus), length (Monthly / Annual), price ($3.99 / $39.99)
  - 7-day free trial on annual for new subscribers
  - Auto-renewal language ("renews unless canceled at least 24 hours before...")
  - "Payment will be charged to your Apple ID / Google Account at confirmation of purchase"
  - "Account will be charged for renewal within 24 hours prior to the end of the current period"
  - "Manage and cancel in App Store / Google Play settings"
- [ ] Deploy webapp via GH Actions

---

## Phase 6 — Beta tester + reviewer migration

**HARD SEQUENCING RULE**: must complete BEFORE mobile build hits TestFlight. Otherwise existing beta testers get locked out.

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
