# Clique Pix — Paywall + Free Trial + Review Prompts: Master Plan & Status

**Last updated:** 2026-06-02
**Branch:** `feat/paywall-trial-and-review-prompts` (all work below lives here; not yet merged to `main`)
**Owner doc:** this file is the single source of truth for "what's left." The deep specs/plans it points to have the exact code.

---

## TL;DR — where we are

Monetization is now **in scope for v1**. We are shipping a hard paywall fronted by a **7-day, no-card free trial of the whole app**, plus **native store-review prompts**. The RevenueCat backend plumbing was already built earlier (migration 012, webhook, entitlement service, `requireActiveEntitlement`). This effort revised the gate model (hard paywall → trial-first) and added the trial + review features.

- ✅ **Design spec** approved + committed.
- ✅ **5 implementation plans** written + committed.
- ✅ **Plan 1 (backend trial) — code complete AND DEPLOYED LIVE 2026-06-02.** Migrations 012+013 applied to prod (14 users backfilled, `trial_null=0`), `func publish` succeeded, `/api/health` 200, webhook verified. 174/174 tests.
- ✅ **Plan 3 (store review prompts) — complete + committed** (5 commits; 91/91 tests, release APK built).
- ✅ **Plan 5 (docs/legal/pricing) — edits complete + committed.** Remaining: **Task 7 web deploy** of the legal pages before App Store submission.
- ✅ **RevenueCat + Azure config — largely done this session** (see "Session 2026-06-02" below).
- ⏳ **Plan 2 (Flutter paywall) now UNBLOCKED** (backend live + iOS SDK key captured) — not started. **Plan 4 (web)** not started. **Plan 6 promo grants** not done — **7-day trial clock is now running.**

---

## ✅ Session 2026-06-02 — completed (assistant, via Azure + RevenueCat MCP)

**Backend deploy (Task 6 / Phase 2 deploy) — DONE & verified live:**
- Migrations **012 + 013** applied to `pg-cliquepixdb` (14 users backfilled → `trial_null = 0`; nobody locked out).
- `npm run build` clean, **174/174** jest, `func azure functionapp publish func-cliquepix-fresh` succeeded, app **Running**.
- Smoke: `GET /api/health` → 200; webhook 401 on bad/missing auth, **200** on correct Bearer (KV secret resolves). (Used a self-sent curl with `--ssl-no-revoke` instead of the dashboard "Send test event".)
- ⚠️ The paywall gate is **live** now — every existing user rides the backfilled 7-day trial. **Plan 6 promo grants must land within 7 days** or testers hit 402s.

**Azure (Function App + Key Vault) — DONE:**
- KV secrets present: `revenuecat-webhook-secret`, `revenuecat-secret-api-key` (Gene added).
- Function App `func-cliquepix-fresh` settings wired as Key Vault references: `REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`. MI confirmed `Key Vault Secrets User`.

**RevenueCat (project `proj04f5314d`) — DONE:**
- `plus_monthly` → `$rc_monthly`, `plus_annual` → `$rc_annual` attached in `default` offering (App Store products, alongside test-store).
- Webhook `whintgr721b9e5264` → `api.clique-pix.com/api/internal/revenuecat-webhook` (all envs/events, Bearer secret) — verified 200.
- iOS public SDK key captured: `appl_OvhNypnojnQSEebpQtBikJYTHBa`.
- `plus_annual` price **$29.99 → $39.99** (US + 6 available territories equalized) **+ 7-day intro offer added** — both were wrong/missing in live App Store Connect; fixed via MCP.
- Paywall AI **draft** `pw9ac01d9e31184633` created on `default` offering — **UNATTACHED; Gene must publish + attach in the dashboard** (RC has no publish/attach API).

**Still REMAINING (all dashboard/store, no code):** publish + attach the paywall; verify **Transfer Behavior = KEEP_ATTRIBUTION** (API can't read it); **submit** both IAPs; **Plan 6 promo grants** (urgent); fix **test-store prices** ($9.99/$79.99 → $3.99/$39.99); **Task 7** deploy legal pages; **Android** Play setup (blocked on W-9).
**Code remaining:** **Plan 2** (Flutter paywall, now unblocked) + **Plan 4** (web gating).

---

## Locked product decisions (do not silently change)

| Decision | Value |
|---|---|
| Free access | **7-day no-card free trial** of the full app, granted at first sign-in. Hard paywall after lapse. |
| Trial mechanism | Backend-granted, time-based: `users.trial_ends_at = NOW() + 7 days`, COALESCE-preserved on re-auth. Computed live; no reconciliation timer for trial. |
| Tier | Single tier, entitlement `plus`. |
| Monthly price | **$3.99 / month** |
| Annual price | **$39.99 / year** ("2 months free") — *raised from $29.99*. |
| Annual store intro offer | **Keep** the existing 7-day store intro offer (new subscribers only). |
| Effective access | `entitlement_active OR (trial_ends_at > NOW())` → emitted as `effective_active`. Clients gate on this. |
| Web client | Mobile-first; gated web routes → "subscribe in the mobile app." No Stripe in v1. |
| Reviewer / beta | RevenueCat **Promotional** entitlement grants (no DB override). |
| Transfer behavior | `KEEP_ATTRIBUTION`. |
| Review prompts | Native `in_app_review`, trigger on 3rd successful media upload (cross-session), 120-day cap, availability-gated, never on error/paywall path. Manual "Rate Clique Pix" tile (App Store ID `6766294274`). |

---

## Reference documents

| File | What it is |
|---|---|
| `docs/superpowers/specs/2026-06-01-paywall-trial-and-review-prompts-design.md` | The approved design spec (this effort). |
| `docs/superpowers/plans/2026-06-01-backend-trial-entitlement.md` | **Plan 1** — backend trial (DONE in code). |
| `docs/superpowers/plans/2026-06-01-flutter-paywall-trial-gate.md` | **Plan 2** — Flutter paywall + gate. |
| `docs/superpowers/plans/2026-06-01-flutter-store-review-prompts.md` | **Plan 3** — review prompts. |
| `docs/superpowers/plans/2026-06-01-web-subscription-gating.md` | **Plan 4** — web gating. |
| `docs/superpowers/plans/2026-06-01-docs-legal-pricing.md` | **Plan 5** — docs/legal/$39.99. |
| `~/.claude/plans/okay-this-is-what-inherited-deer.md` | Original RevenueCat base plan (backend Phase 2 already built; store/RC dashboard steps). |
| `docs/GENE.md` | Gene's personal RevenueCat rollout punch list (store + dashboard config status). |

---

## GENE'S MANUAL CONFIG (in progress / required) — no code can replace these

### A. Environment Gene is setting up now
- [x] **Add RevenueCat MCP server** — done (assistant used it this session).
- [x] **Log into the Azure subscription** — done (assistant ran Task 6 + verified).

### B. RevenueCat dashboard — Phase 1c
- [x] Attach `plus_monthly` → Monthly package and `plus_annual` → Annual package in the `default` offering. **(done via MCP)**
- [ ] Verify Transfer Behavior = **Keep with previous App User ID** (`KEEP_ATTRIBUTION`). **← STILL TODO — the API can't read this; Gene must check Project Settings.**
- [x] Configure webhook → `https://api.clique-pix.com/api/internal/revenuecat-webhook` with `Bearer <secret>`. **(webhook `whintgr721b9e5264` created + verified 200; secret in Key Vault)**
- [x] Generate **Secret API Key** (`sk_...`) → saved to Key Vault as `revenuecat-secret-api-key`.
- [x] Capture **iOS public SDK key** → `appl_OvhNypnojnQSEebpQtBikJYTHBa` (still needs to land in `revenuecat_constants.dart`, Plan 2). Android `goog_...` later (blocked).
- [~] Paywalls v2 paywall — **AI draft `pw9ac01d9e31184633` created** (dark, gradient, annual badge, disclaimer, Restore). **← Gene must publish + attach to `default` offering in the dashboard.**

### C. Pricing change
- [x] `plus_annual` price **$29.99 → $39.99** + **7-day intro offer** — done via MCP (US + 6 territories equalized). Live ASC was actually still $29.99 with no intro offer; now fixed.
- [ ] When the Play subscription is created, set annual to **$39.99** from the start. (blocked on Play)

### D. Azure Key Vault + Function App (Phase 1d) — DONE
- [x] Key Vault `kv-cliquepix-prod`: `revenuecat-webhook-secret`, `revenuecat-secret-api-key` present.
- [x] Function App `func-cliquepix-fresh` settings (Key Vault refs): `REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`. Restarted.
- [x] Smoke verified (self-sent curl): webhook 200 on correct Bearer, 401 on bad. (Optional: also click RC "Send test event" for RC-side delivery confirmation.)

### E. Google Play (Phase 1b — PAUSED on payments/tax verification, per GENE.md)
- [ ] Resolve IRS/EIN name mismatch (call IRS Business line, get Form 147c) OR submit W-9 as `BlueBuildApps, LLC` to unblock.
- [ ] Create `plus_monthly` / `plus_annual` subscriptions ($3.99 / $39.99), add 7-day trial offer on annual, activate base plans.
- [ ] Data safety: declare Purchase history + RevenueCat partner.
- [ ] License testing accounts; `revenuecat-play` service account + RTDN topic paste-back.

---

## TASK 6 — Backend deploy ✅ DONE 2026-06-02

Deployed live by the assistant (Azure + RC MCP). Both migration 012 and 013 applied; full backend (entitlement + webhook + trial) published.
- [x] Migrations **012 + 013** applied to `pg-cliquepixdb`. `trial_ends_at` present; `SELECT count(*) WHERE trial_ends_at IS NULL` → **0** (14 users backfilled).
- [x] Deployed: `func azure functionapp publish func-cliquepix-fresh`; `GET https://api.clique-pix.com/api/health` → **200**; app **Running**.
- [x] Smoke: webhook 401 on bad/missing auth, **200** on correct Bearer. (The `/api/users/me` trial-token check is left for Gene on-device — needs a real user JWT.)
- [x] Migration 012 (RevenueCat columns) confirmed applied alongside 013.

> **Hard rule:** backend (012 + 013) MUST be deployed BEFORE the Plan 2 mobile build reaches TestFlight/Play. Old backend returns no `entitlement` object → mobile null-crash.

---

## REMAINING IMPLEMENTATION PLANS (status + how to run)

All to be executed subagent-driven on this branch, two-stage review per task (spec → quality), same as Plan 1.

### Plan 2 — Flutter paywall + trial gate  🟢 UNBLOCKED (ready to start)
- **Was blocked by** Task 6 deploy + RC SDK keys — **both now satisfied**: backend live, iOS key `appl_OvhNypnojnQSEebpQtBikJYTHBa` captured. (Android `goog_` still pending → iOS-only build until Play unblocks.)
- Scope: `purchases_flutter` + `purchases_ui_flutter`, `EntitlementState` model + `UserModel.entitlement` parsing, `RevenueCatService` (configure/logIn/logOut/presentPaywall/restore/manage), paywall screen, **router gate on `effective_active`** (allowlist `/paywall`,`/profile`,`/login`), hide bottom nav off-access, lifecycle login/logout + `resetSession` logout, `Purchases.configure` in `performDeferredInit`, Profile Manage/Restore tiles + diagnostics section, **purchase-success optimistic flag + 30s auto-recovery**. Version bump `1.0.0+5`.

### Plan 3 — Flutter store review prompts  ✅ DONE 2026-06-02 (5 commits; 91/91 tests, analyze 54, release APK built)
- Add `in_app_review`; `ReviewPromptService` (unit-tested eligibility); hook photo (`camera_capture_screen.dart` after `confirmUpload`) + video (`video_upload_screen.dart` after `notifier.succeed`); "Rate Clique Pix" Profile tile; telemetry.

### Plan 4 — Web subscription gating  🟢 UNBLOCKED (backend live — can build + verify now)
- `User.entitlement` (camelCase post-camelize), `EntitlementGuard` → `/subscribe`, `SubscribeInAppScreen`, route wiring (`/profile` + `/subscribe` exempt), Profile "Manage Subscription" link.

### Plan 5 — Docs / legal / pricing $39.99  ✅ DONE (edits committed 2026-06-02; web deploy + store price change pending)
- CLAUDE.md (remove "no monetization", add paywall section + guardrail + review-prompt note), PRD §5.16/§5.17/§13, ARCHITECTURE users table + auth-response section, **privacy.html + terms.html subscription disclosures**, repo-wide `$29.99 → $39.99` sweep.
- **Status:** all doc/HTML edits committed (see "Done so far"). NOT yet deployed — **Task 7 (SWA deploy of legal pages)** + App Store Connect `plus_annual` price change remain (both ops/Gene).
- **Deadline:** privacy/terms pages MUST be deployed to `clique-pix.com/docs/*` BEFORE the gated mobile build is submitted (Apple checks the URLs).

---

## Plan 6 — Beta tester + reviewer migration (after backend live + mobile built, before TestFlight)
- [ ] `SELECT id, email_or_phone FROM users WHERE created_at < '<cutoff>';`
- [ ] RC dashboard → grant **Promotional** `plus`: `appreview@cliquepix.com` → lifetime; 4 beta testers → 1 year.
- [ ] App Store Connect review notes: explain promo grant + sandbox tester path. (Reviewer needs BOTH: promo grant to see the app, sandbox tester to exercise the IAP.)
- [ ] Document grants in `docs/BETA_OPERATIONS_RUNBOOK.md`.

> **Hard rule:** promo grants MUST be in place BEFORE the gated build reaches TestFlight/Play Internal, or existing testers get locked out of their own beta.

---

## Hard sequencing constraints (the three that can bite)

1. **Backend (012 + 013) deploys BEFORE the Plan 2 mobile build hits TestFlight/Play.** (Else null-crash.)
2. **Promo grants (Plan 6) in place BEFORE the gated build reaches testers.** (Else testers locked out.)
3. **Legal pages (Plan 5) live on `clique-pix.com` BEFORE App Store submission.** (Apple checks during review.)
4. Production promotion gated on a full paywall test pass on BOTH iOS and Android (real money — effectively irreversible).

Plans that parallelize freely: Plan 3 + Plan 5 can run now alongside Gene's config. Plan 2 + Plan 4 wait on Task 6 / keys.

---

## Suggested execution order from here

1. **Gene:** finish Config A (MCP + Azure login).
2. **Assistant (no blockers):** execute **Plan 3** + **Plan 5** subagent-driven.
3. **Gene:** Config B/C/D (RC dashboard, price, Key Vault) → then **Task 6** deploy (assistant can run/verify once Azure login is in).
4. **Assistant:** execute **Plan 2** + **Plan 4** (keys now available; backend live to verify).
5. **Gene + assistant:** **Plan 6** promo grants → build to TestFlight/Play Internal.
6. Full BETA_TEST_PLAN paywall pass on both platforms → promote to production.

---

## Done so far (commits on `feat/paywall-trial-and-review-prompts`)

- `96e0ed7` spec (design doc)
- `e0c0445` Plan 1 doc
- `d9119e9` Plans 2–5 docs
- `9a750ff` migration 013 (trial_ends_at)
- `21293da` emit in_trial/effective_active in auth response
- `24a3cda` trial passes requireActiveEntitlement
- `29bcdf9` stamp trial_ends_at at first sign-in
- `a78ee28` review nits (fixtures, boundary tests, comments)

**Backend trial: 174/174 jest green, `npm run build` clean. Not deployed.**

**Plan 5 (docs/legal/pricing) — 2026-06-02:**
- `8bf253e` CLAUDE.md — monetization in scope (paywall + trial + review prompts)
- `fb658ec` PRD — subscription + free trial + rate-the-app; roadmap
- `2ad674b` ARCHITECTURE — entitlement + trial_ends_at columns + auth response
- `432e4f5` privacy.html — subscription + RevenueCat subprocessor disclosure
- `83aaafd` terms.html — subscription disclosures ($3.99/$39.99)
- `c1e7cfa` annual price $29.99 → $39.99 sweep (docs/GENE.md)
- (`b61b7d2` separately: CLAUDE.md trim of 5 reference sections — unrelated to Plan 5)

**Plan 5 docs/HTML: complete + committed. NOT deployed (Task 7 SWA deploy pending).**

**Plan 3 (store review prompts) — 2026-06-02:**
- `41c7403` add in_app_review dependency
- `c04f504` ReviewPromptService + unit-tested eligibility
- `268af53` prompt after successful photo upload
- `0aaeb6a` prompt after successful video upload
- `c6db13c` manual "Rate Clique Pix" Profile tile

**Backend DEPLOYED live 2026-06-02** (no new commit — `func publish` of the committed branch + prod DB migrations 012/013). RevenueCat + Azure config changes are dashboard/cloud-side (no repo commits).

---

## How to resume

Tell the assistant: *"Resume paywall work — see docs/PLAN.md."* Then pick an execution-order step above. If Azure login + RC MCP are in, the assistant can run Task 6 and verify; otherwise it executes the unblocked plans (3, 5) first.
