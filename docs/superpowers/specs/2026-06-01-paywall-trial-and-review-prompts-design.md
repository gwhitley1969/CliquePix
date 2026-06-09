# Design — Free-Trial Paywall + Store Review Prompts

**Date:** 2026-06-01
**Status:** Approved (brainstorming) → pending spec review → implementation plan
**Base plan this revises:** `~/.claude/plans/okay-this-is-what-inherited-deer.md` (RevenueCat paywall) and the `docs/GENE.md` punch list.

---

## 1. Summary

CLIQUE Pix is moving monetization in-scope for v1. The RevenueCat entitlement plumbing is already largely built (migration 012, webhook, entitlement service, `requireActiveEntitlement` on 39 endpoints — code complete, not yet deployed). This spec makes **two changes** on top of that base:

1. **Gate model:** flip from "hard paywall immediately after sign-in" to a **7-day, no-card free trial of the full app, then a hard paywall.**
2. **New feature:** native **store-rating prompts** via the `in_app_review` package, triggered after a sharing-success milestone.

Plus the mechanical doc updates to remove the now-obsolete "no monetization" guardrails.

### Locked product decisions

| Decision | Value |
|---|---|
| Free access model | 7-day **no-card** free trial of the entire app, granted at first sign-in. Hard paywall after lapse. |
| Tiers | Single tier, entitlement `plus` |
| Monthly price | $3.99 / month |
| **Annual price** | **$39.99 / year** ("2 months free" ≈ 10 × monthly; ~16% off full monthly) — *revised from $29.99* |
| Annual store intro offer | **Keep** the existing 7-day store intro offer on the annual plan (applies once per new subscriber; ~14 total free days when combined with the app trial) |
| Paywall UI | RevenueCat Paywalls v2 via `purchases_ui_flutter` |
| Web client | Mobile-first; gated web routes show "Subscribe in the mobile app" |
| Reviewer / beta access | RevenueCat **Promotional** entitlement grants (unchanged from base plan) |
| Transfer behavior | `KEEP_ATTRIBUTION` (unchanged) |
| Review prompts | Native `in_app_review`; trigger on 3rd successful media upload (cross-session); frequency-capped |

Everything in the base plan not contradicted here (RevenueCat dashboard setup, webhook auth, reconciliation timer for subscription expiry, gated-endpoint list, deploy sequencing, promo-grant migration) **carries forward unchanged**.

---

## 2. Trial entitlement model (backend)

The trial is **app-granted and purely time-based** — not a store product. This is the key architectural addition.

- **Migration `013_user_trial.sql`** adds `users.trial_ends_at TIMESTAMPTZ` (nullable).
- Set once in `authVerify` on the first user insert: `trial_ends_at = NOW() + INTERVAL '7 days'`. On returning logins the upsert uses `COALESCE(users.trial_ends_at, ...)` so the window can never be reset by re-auth (same pattern as `age_verified_at`).
- `buildAuthUserResponse` (`backend/src/shared/services/avatarEnricher.ts`) computes and emits, inside the existing `entitlement` object:
  - `in_trial: boolean` = `trial_ends_at IS NOT NULL AND trial_ends_at > NOW()`
  - `trial_ends_at: <ISO timestamp | null>`
  - `effective_active: boolean` = `entitlement_active OR in_trial`
- `requireActiveEntitlement` middleware passes when `entitlement_active OR in_trial`; otherwise 402 `SUBSCRIPTION_REQUIRED` (unchanged response shape).
- **No new reconciliation timer.** Trial expiry is computed live on every request, so there is no stored boolean to drift. The subscription-expiry reconciliation timer from the base plan is unchanged.
- **Promotional grants are unaffected.** A reviewer/beta promo grant sets `entitlement_active = true`, which makes `effective_active` true regardless of trial state — reviewers never see the paywall.

### Why no-card / backend-granted (rationale)
A store-side intro-offer trial would require the user to choose a plan and enter Apple/Google payment *before* using the app — which is functionally a paywall and breaks the "everyone gets full access at sign-up" intent. The backend-granted trial is the only model that preserves the **invite loop** (an invited guest signs in, lands in trial, and sees the event immediately) and gives the review prompt a real happy-moment window to fire in.

---

## 3. Paywall placement & client gating

- Client router gate keys on `entitlement.effective_active` (mobile `app_router.dart`, web router). While in trial OR subscribed → full app. When the trial lapses unsubscribed → `/paywall` (mobile) / `/subscribe` (web), with the same allowlist as the base plan (`/paywall`|`/subscribe`, `/profile`, `/login`, plus web `/docs/*`, `/`).
- The `EntitlementState` client model gains `inTrial` + `trialEndsAt` + `effectiveActive`; the router reads `effectiveActive`.
- **Mid-session expiry** is caught on the next API response or app-resume verify (the enriched user flips `in_trial` to false). No client-side countdown timer — YAGNI; navigation/refresh/resume re-evaluates within seconds.
- Optional (nice-to-have, not required for v1): a subtle "X days left in your trial" banner on Home driven by `trialEndsAt`. Out of scope unless explicitly added.

---

## 4. Store review prompt feature (new)

- **Dependency:** add `in_app_review` (resolve current major via `flutter pub add in_app_review`; lock in `pubspec.lock`).
- **New service:** `app/lib/services/review_prompt_service.dart`.
  - `maybeRequestReview()` — called from the existing photo-upload-confirm success path and video-commit success path (where `photo_upload_completed` / `video_upload_committed` telemetry fires).
  - State in `SharedPreferences`: `review_successful_upload_count`, `review_last_requested_at_ms`, `review_requested_for_version`.
  - **Guards (all must pass):** `InAppReview.isAvailable()` is true; successful-upload count ≥ 3; no prior request within ~120 days; the triggering action succeeded (never called from an error path); never invoked on the paywall / trial-expiry path.
  - On pass: `InAppReview.instance.requestReview()` (the OS decides whether to actually display — Apple throttles to ~3×/year; we never assume it showed).
- **Manual path:** a "Rate CLIQUE Pix" tile in `profile_screen.dart` calls `InAppReview.instance.openStoreListing(appStoreId: '6766294274')` — always available, not throttled.
- **Telemetry:** `review_prompt_requested`, `review_prompt_skipped { reason: 'unavailable'|'below_threshold'|'cooldown'|'version_repeat' }`, `review_store_listing_opened`.
- Not gated on subscription state — but trial/subscription gating already means only active users reach the upload flow.

---

## 5. Documentation updates

| Doc | Change |
|---|---|
| `.claude/CLAUDE.md` | Remove "Monetization, subscriptions, or paywalls" from *Do Not Build*. Add a **Subscription Paywall** section (7-day no-card trial, RevenueCat, $3.99/mo · $39.99/yr, single `plus` tier, effective-active = sub OR trial OR promo). Add a "do not regress to a free tier without explicit product approval" guardrail. Note the review-prompt trigger + guard rules. |
| `docs/PRD.md` | §6 Non-Goals: strike "Monetization, subscriptions, or paywalls." Add a new §5.x **Subscription & Free Trial** (user-visible: 7 days free, then $3.99/mo or $39.99/yr with 2 months free) and a **Rate the App** note. §13 Future Roadmap: strike "Premium subscription tier" (now shipped). |
| `docs/ARCHITECTURE.md` | Add `trial_ends_at` to the §7 users table. Add the entitlement/trial computation to the auth response section (cross-reference the base plan's RevenueCat architecture). |
| `docs/PRD.md` / Terms / Privacy / paywall disclaimer | Every place the annual price appears must read **$39.99** (the base plan's Phase 5 legal disclosures + the RC Paywalls v2 disclaimer block). |

(The base plan's broader Phase 8 doc set — `PAYWALL_ARCHITECTURE.md`, `REVENUECAT_RUNBOOK.md`, `BETA_TEST_PLAN.md` §13, etc. — is still owed and tracked there; this spec only calls out the deltas introduced by the trial + review changes.)

---

## 6. Out of scope / non-goals for this spec

- Stripe / web purchase flow (web stays "subscribe in mobile app").
- Multiple tiers, family plans, lifetime purchase.
- In-app private feedback collection (the chosen review path is **native store prompts only**).
- Trial extensions, win-back offers, or re-trial logic.
- A client-side trial countdown timer (banner is optional, deferred).

---

## 7. Sequencing & release notes

- The base plan's hard ordering constraints still hold: **backend deploys before the mobile build reaches TestFlight/Play Internal** (clients expect the `entitlement` object incl. the new trial fields); **promo grants for existing testers + reviewer must precede the gated build**; **production promotion gated on full paywall test pass.**
- The annual price change to $39.99 is cheap to make now — `plus_annual` is "Ready to Submit" in App Store Connect (not live/approved) and not yet created in Play. Edit the price before submission.
- Reviewer flow unchanged: promotional `plus` grant (no paywall) + a sandbox tester to exercise the actual purchase.

---

## 8. Open items for spec review

1. Confirm keeping the annual store intro offer (item in §1; recommendation = keep).
2. Confirm the optional trial-countdown banner stays **out** of v1 (recommendation = out).
