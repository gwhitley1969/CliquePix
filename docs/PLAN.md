# Clique Pix — Paywall + Free Trial + Review Prompts: Master Plan & Status

**Last updated:** 2026-06-02
**Branch:** `feat/paywall-trial-and-review-prompts` (all work below lives here; not yet merged to `main`)
**Owner doc:** this file is the single source of truth for "what's left." The deep specs/plans it points to have the exact code.

---

## TL;DR — where we are

Monetization is now **in scope for v1**. We are shipping a hard paywall fronted by a **7-day, no-card free trial of the whole app**, plus **native store-review prompts**. The RevenueCat backend plumbing was already built earlier (migration 012, webhook, entitlement service, `requireActiveEntitlement`). This effort revised the gate model (hard paywall → trial-first) and added the trial + review features.

- ✅ **Design spec** approved + committed.
- ✅ **5 implementation plans** written + committed.
- ✅ **Plan 1 (backend trial) — code complete, reviewed (spec ✅ + quality ✅), 174/174 tests green, build clean.** NOT yet deployed.
- ✅ **Plan 5 (docs/legal/pricing) — edits complete + committed** (CLAUDE.md, PRD §5.16/§5.17/§13, ARCHITECTURE, privacy + terms HTML, repo `$39.99` sweep). Remaining: Gene's store-side price change + **Task 7 web deploy** of the legal pages before App Store submission.
- ⏳ **Plans 2–4** not started. **Gene’s manual config + Task 6 deploy gate most of them** (see Dependencies).

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
- [ ] **Add RevenueCat MCP server** (so the assistant can help inspect/verify dashboard state).
- [ ] **Log into the Azure subscription** (so the assistant can run/verify the Task 6 deploy + DB migration).

### B. RevenueCat dashboard — Phase 1c (from `docs/GENE.md`, IN PROGRESS)
- [ ] Attach `plus_monthly` → Monthly package and `plus_annual` → Annual package in the `default` offering.
- [ ] Verify Transfer Behavior = **Keep with previous App User ID** (`KEEP_ATTRIBUTION`).
- [ ] Configure webhook → `https://api.clique-pix.com/api/internal/revenuecat-webhook` with a `Bearer <secret>`; save the secret for Key Vault.
- [ ] Generate **Secret API Key** (`sk_...`) → save for Key Vault.
- [ ] Capture **iOS public SDK key** (`appl_...`) and (later) **Android public SDK key** (`goog_...`) → these go into `app/lib/core/constants/revenuecat_constants.dart` (Plan 2, Task 1).
- [ ] Design the Paywalls v2 paywall (dark `#0E1525`, brand gradient header, annual highlighted "Best Value — 7-Day Free Trial", disclaimer block, Restore button).

### C. Pricing change (cheap now — do before App Store submission)
- [ ] App Store Connect → `plus_annual` price **$29.99 → $39.99** (it's "Ready to Submit," not live).
- [ ] When the Play subscription is created, set annual to **$39.99** from the start.

### D. Azure Key Vault + Function App (Phase 1d — after RC webhook secret + Secret API Key exist)
- [ ] Add to `kv-cliquepix-prod`: `revenuecat-webhook-secret`, `revenuecat-secret-api-key`.
- [ ] Add Function App `func-cliquepix-fresh` settings (Key Vault refs): `REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_SECRET_API_KEY`. Restart.
- [ ] Smoke: RC dashboard → "Send test event" → 200 OK + DB row updated.

### E. Google Play (Phase 1b — PAUSED on payments/tax verification, per GENE.md)
- [ ] Resolve IRS/EIN name mismatch (call IRS Business line, get Form 147c) OR submit W-9 as `BlueBuildApps, LLC` to unblock.
- [ ] Create `plus_monthly` / `plus_annual` subscriptions ($3.99 / $39.99), add 7-day trial offer on annual, activate base plans.
- [ ] Data safety: declare Purchase history + RevenueCat partner.
- [ ] License testing accounts; `revenuecat-play` service account + RTDN topic paste-back.

---

## TASK 6 — Backend deploy (ops; needs Azure login from step A)

Plan 1 code is committed but NOT live. Once Azure is reachable:
- [ ] Apply `backend/src/shared/db/migrations/013_user_trial.sql` to `pg-cliquepixdb`. Verify:
  - `trial_ends_at` column exists on `users`.
  - `SELECT count(*) FROM users WHERE trial_ends_at IS NULL;` → **0** (backfill covered everyone).
- [ ] Deploy: from `backend/`, `func azure functionapp publish func-cliquepix-fresh`. Confirm `GET https://api.clique-pix.com/api/health` → 200.
- [ ] Smoke: `GET /api/users/me` with a trial-user token → `entitlement.in_trial: true`, `effective_active: true`; a gated endpoint (e.g. `GET /api/events`) returns 200 (not 402).
- [ ] **Also deploy the already-built RevenueCat backend (migration 012 + webhook)** if it isn't live yet — Plan 1 assumed 012 ships with/before 013. Verify migration 012 is applied too.

> **Hard rule:** backend (012 + 013) MUST be deployed BEFORE the Plan 2 mobile build reaches TestFlight/Play. Old backend returns no `entitlement` object → mobile null-crash.

---

## REMAINING IMPLEMENTATION PLANS (status + how to run)

All to be executed subagent-driven on this branch, two-stage review per task (spec → quality), same as Plan 1.

### Plan 2 — Flutter paywall + trial gate  ⏳ BLOCKED
- **Blocked by:** Task 6 deploy live **and** RC public SDK keys captured (Config B).
- Code can be drafted with placeholder keys (`appl_...`/`goog_...` in `revenuecat_constants.dart`), but cannot build a real binary or be verified until keys land.
- Scope: `purchases_flutter` + `purchases_ui_flutter`, `EntitlementState` model + `UserModel.entitlement` parsing, `RevenueCatService` (configure/logIn/logOut/presentPaywall/restore/manage), paywall screen, **router gate on `effective_active`** (allowlist `/paywall`,`/profile`,`/login`), hide bottom nav off-access, lifecycle login/logout + `resetSession` logout, `Purchases.configure` in `performDeferredInit`, Profile Manage/Restore tiles + diagnostics section, **purchase-success optimistic flag + 30s auto-recovery**. Version bump `1.0.0+5`.

### Plan 3 — Flutter store review prompts  ✅ READY NOW (no blockers)
- Add `in_app_review`; `ReviewPromptService` (unit-tested eligibility); hook photo (`camera_capture_screen.dart` after `confirmUpload`) + video (`video_upload_screen.dart` after `notifier.succeed`); "Rate Clique Pix" Profile tile; telemetry.

### Plan 4 — Web subscription gating  ⏳ code now, verify after Task 6
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

---

## How to resume

Tell the assistant: *"Resume paywall work — see docs/PLAN.md."* Then pick an execution-order step above. If Azure login + RC MCP are in, the assistant can run Task 6 and verify; otherwise it executes the unblocked plans (3, 5) first.
