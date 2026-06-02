# Docs + Legal + Pricing ($39.99) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the guardrail/architecture docs reflect that monetization is now in v1, publish the legally-required subscription disclosures (Apple Guideline 3.1.2 + Google Play) with the $39.99 annual price, and sweep the repo for the stale $29.99.

**Architecture:** Pure documentation + static HTML edits. No code, no tests. Mechanical but must ship to `clique-pix.com` BEFORE the gated mobile build hits TestFlight (Apple checks the URLs during review).

**Tech Stack:** Markdown + static HTML (the web client serves `webapp/public/docs/*.html`).

---

## Plan-wide context (read once)

**Plan 5 of 5.** Independent of code; can run in parallel with Plans 1–4. The legal pages MUST be deployed before App Store review of the gated build.

Canonical facts to thread through every edit:
- Free trial: **7 days, no payment required**, then a hard paywall.
- Tier: single (`plus`). **Monthly $3.99**, **Annual $39.99** ("2 months free").
- Annual store intro offer: 7-day free trial (new subscribers) — kept.
- Provider: RevenueCat (subprocessor on the privacy page).
- Auto-renew; manage/cancel in App Store / Google Play settings.

Legal files live at `webapp/public/docs/privacy.html` and `webapp/public/docs/terms.html` (the `webapp/dist/docs/*` copies are build output — do NOT edit those).

**Files:**
- Modify: `.claude/CLAUDE.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `webapp/public/docs/privacy.html`, `webapp/public/docs/terms.html`

---

## Task 1: CLAUDE.md — monetization is in scope

**Files:** Modify `.claude/CLAUDE.md`

- [ ] **Step 1: Remove the "Do Not Build" monetization line**

In the **Do Not Build** list, delete the line:
```
- Monetization, subscriptions, or paywalls
```

- [ ] **Step 2: Add a Subscription Paywall subsection**

Under **Build These** (at the end of that section, after the Avatars block), add:

```markdown
**Subscription Paywall + Free Trial (v1, RevenueCat — migration 012/013)**
- Single tier, entitlement `plus`. **Monthly $3.99 / Annual $39.99** ("2 months free"). Annual carries a 7-day store intro offer for new subscribers.
- **7-day no-card free trial of the full app**, granted at first sign-in (`users.trial_ends_at = NOW() + 7 days`, COALESCE-preserved). After it lapses unsubscribed, a hard paywall drops. Effective access = `entitlement_active OR (trial_ends_at > NOW())`, computed live (no reconciliation timer for trial).
- Backend is authoritative: `requireActiveEntitlement` 402s `SUBSCRIPTION_REQUIRED` unless subscribed OR in trial; `buildAuthUserResponse` emits `entitlement { active, in_trial, trial_ends_at, effective_active, ... }`. RevenueCat webhook at `POST /api/internal/revenuecat-webhook`; 6h `entitlementReconciliationTimer` for subscription (not trial) expiry.
- Mobile: `purchases_flutter` + `purchases_ui_flutter` (Paywalls v2). Router gates on `effective_active`; only `/paywall` + `/profile` reachable without access. Web: gated routes show "subscribe in the mobile app" (no Stripe in v1).
- Reviewer + beta testers: RevenueCat **Promotional** entitlement grants (no DB override).
- **Guardrail: do NOT regress to a free tier or remove the paywall without explicit product approval.** Monetization is now a v1 product requirement, not a future consideration.
```

- [ ] **Step 3: Add a store-review note**

Add a one-liner near the Notifications/feedback area:
```markdown
- **Store review prompts:** native `in_app_review` `requestReview()` fires after the user's 3rd successful media upload (cross-session), frequency-capped at 120 days, availability-gated, never on an error or paywall path. Manual "Rate Clique Pix" tile in Profile uses `openStoreListing(appStoreId: 6766294274)`.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs(claude): monetization in scope — paywall + trial + review prompts"
```

---

## Task 2: PRD.md — subscription product + roadmap

**Files:** Modify `docs/PRD.md`

- [ ] **Step 1: Add §5.16 Subscription & Free Trial**

After §5.15 (Privacy & Controls), add:

```markdown
### 5.16 Subscription & Free Trial

Clique Pix is a subscription product. Every new user gets a **7-day free trial of the entire app** — no credit card, no commitment — starting at sign-up. When the trial ends, a paywall appears and a subscription is required to keep using the app.

- **Clique Pix Plus** — single plan, two billing options:
  - **Monthly:** $3.99 / month
  - **Annual:** $39.99 / year (2 months free vs. monthly), with a 7-day free trial for new subscribers
- During the trial the full app works exactly as a paid subscription — create cliques and events, upload photos and videos, DMs, everything. The invite loop is preserved: someone invited to an event can sign in and immediately see it during their trial.
- Manage or cancel anytime in the App Store / Google Play account settings.
- Beta testers and the App Store reviewer receive complimentary access.

### 5.17 Rate the App

A gentle, well-timed prompt asks happy users to rate Clique Pix on the App Store / Google Play after they've shared a few times. A "Rate Clique Pix" option is always available in Profile. (No private in-app feedback channel in v1.)
```

- [ ] **Step 2: Update §13 Future Roadmap**

Change the line:
```markdown
- Premium subscription tier
```
to:
```markdown
- ~~Premium subscription tier~~ (implemented in v1 — 7-day free trial, then $3.99/mo or $39.99/yr; see §5.16)
```

- [ ] **Step 3: Check §6 Non-Goals**

If §6 (Non-Goals) contains any "no monetization / no subscription / no paywall" line, strike it the same way. (As of writing, §6 does not — verify and only edit if present.)

- [ ] **Step 4: Commit**

```bash
git add docs/PRD.md
git commit -m "docs(prd): add subscription + free trial + rate-the-app; update roadmap"
```

---

## Task 3: ARCHITECTURE.md — schema + entitlement response

**Files:** Modify `docs/ARCHITECTURE.md` (§7 users table)

- [ ] **Step 1: Add the trial + entitlement columns to the users table**

In §7's **users** table, add these rows (after `last_refresh_push_sent_at`):

```markdown
| revenuecat_customer_id | TEXT | Nullable. RevenueCat App User ID (usually = users.id). Migration 012 |
| entitlement_active | BOOLEAN | NOT NULL DEFAULT FALSE. Subscription gate (migration 012) |
| entitlement_product_id | TEXT | Nullable. `plus_monthly` / `plus_annual` |
| entitlement_period_type | TEXT | Nullable. `trial`/`intro`/`normal`/`promotional` |
| entitlement_will_renew | BOOLEAN | Nullable |
| entitlement_expires_at | TIMESTAMPTZ | Nullable. Subscription period end |
| entitlement_store | TEXT | Nullable. `APP_STORE`/`PLAY_STORE`/`PROMOTIONAL` |
| entitlement_last_event_id | TEXT | Nullable. Webhook idempotency |
| entitlement_updated_at | TIMESTAMPTZ | Nullable. Last webhook upsert |
| trial_ends_at | TIMESTAMPTZ | Nullable. App-granted 7-day free trial end (migration 013). Set NOW()+7d at first sign-in, COALESCE-preserved |
```

- [ ] **Step 2: Add an entitlement/trial note to the auth response section**

In §5 (Authentication Architecture) or §6 (API — Response Format), add a short subsection:

```markdown
### Entitlement + trial in the auth response

`buildAuthUserResponse` (the canonical user shape from `/api/auth/verify`, `/api/users/me`, and avatar endpoints) includes an `entitlement` object:

```json
{ "active": false, "product_id": null, "period_type": null, "will_renew": null,
  "expires_at": null, "store": null, "in_trial": true,
  "trial_ends_at": "2026-06-09T00:00:00.000Z", "effective_active": true }
```

`effective_active = active || in_trial` is the value clients gate on. The trial is time-based and computed live; only subscription expiry has a reconciliation timer (6h). `requireActiveEntitlement` 402s `SUBSCRIPTION_REQUIRED` unless `effective_active`. See `docs/superpowers/specs/2026-06-01-paywall-trial-and-review-prompts-design.md` and the base RevenueCat plan.
```

- [ ] **Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "docs(arch): document entitlement + trial_ends_at columns and auth response"
```

---

## Task 4: Privacy Policy — subscription disclosures

**Files:** Modify `webapp/public/docs/privacy.html`

- [ ] **Step 1: Add a subscription/billing data section**

Add a new numbered section (match the page's existing `<section>`/heading markup; insert before the contact/closing section). Content:

```html
<h2>Subscriptions &amp; Billing Data</h2>
<p>
  Clique Pix offers an auto-renewable subscription, Clique Pix Plus
  ($3.99/month or $39.99/year), after a 7-day free trial. We use
  <a href="https://www.revenuecat.com/privacy/" target="_blank" rel="noreferrer">RevenueCat</a>
  as a subprocessor to manage subscription state. Payment is processed by Apple
  (App Store) or Google (Google Play); we never receive or store your payment
  card details. We store your subscription status (active/expired, plan, renewal
  date) linked to your account so we can unlock the app on your devices. You can
  request deletion of this data by deleting your account.
</p>
```

- [ ] **Step 2: Bump the page's "Last updated"/effective date** to today and commit

```bash
git add webapp/public/docs/privacy.html
git commit -m "docs(legal): privacy policy subscription + RevenueCat subprocessor"
```

---

## Task 5: Terms of Service — subscription terms

**Files:** Modify `webapp/public/docs/terms.html`

- [ ] **Step 1: Add a subscription terms section**

Add a new numbered section with the Apple/Google-required disclosures verbatim:

```html
<h2>Subscriptions</h2>
<p>
  Clique Pix requires a subscription after a 7-day free trial. Clique Pix Plus
  is offered as a monthly subscription at $3.99 per month, or an annual
  subscription at $39.99 per year. New annual subscribers receive a 7-day free
  trial; the monthly plan is billed immediately.
</p>
<ul>
  <li>Payment will be charged to your Apple ID or Google Account at confirmation of purchase.</li>
  <li>Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period.</li>
  <li>Your account will be charged for renewal within 24 hours prior to the end of the current period, at the rate of your selected plan.</li>
  <li>You can manage or cancel your subscription in your account settings on the App Store or Google Play after purchase.</li>
  <li>Any unused portion of a free trial is forfeited when you purchase a subscription, where applicable.</li>
</ul>
```

- [ ] **Step 2: Bump the page's date and commit**

```bash
git add webapp/public/docs/terms.html
git commit -m "docs(legal): terms of service subscription disclosures ($3.99/$39.99)"
```

---

## Task 6: Price sweep — $29.99 → $39.99

**Files:** repo-wide doc/spec references

- [ ] **Step 1: Find stale annual-price references**

Run (from repo root): `grep -rn "29\.99" --include=*.md --include=*.html --include=*.ts --include=*.dart .`
Expected: hits in personal tracking docs and the base plan.

- [ ] **Step 2: Update each canonical reference to $39.99**

For every hit that refers to the **annual** Clique Pix Plus price (NOT unrelated numbers), change `$29.99` → `$39.99`. Notable known locations: `docs/GENE.md` (Phase 1a/1c lines), `~/.claude/plans/okay-this-is-what-inherited-deer.md` (Decisions table + Phase 1 + Phase 5). Leave the **monthly** $3.99 untouched. Do not touch `webapp/dist/` build output.

> The base plan + GENE.md live partly outside the repo (`~/.claude/plans/`); update the in-repo `docs/GENE.md` copy. The RevenueCat/App Store Connect product price is changed in the **dashboard** (ops step below), not in code.

- [ ] **Step 3: Commit**

```bash
git add -A docs/
git commit -m "docs: annual price $29.99 -> $39.99 across references"
```

- [ ] **Step 4 (ops, Gene): change the store-side price**

In App Store Connect → Clique Pix → Subscriptions → `plus_annual`, change the price from $29.99 to $39.99 BEFORE submitting (it's "Ready to Submit," not live). When the Play subscription is created, set it to $39.99 from the start. Verify RevenueCat re-imports the new price.

---

## Task 7: Deploy the legal pages

- [ ] **Step 1 (ops): ship the web client**

The privacy/terms edits are served from `webapp/public/docs/*`. Push the branch / merge so the SWA GitHub Actions deploy publishes `clique-pix.com/docs/privacy` + `/docs/terms` with the new sections BEFORE the gated mobile build is submitted to Apple. Verify both URLs render the new subscription sections in a browser.

---

## Self-review notes (already applied)

- **Spec coverage:** §5 doc table fully — CLAUDE.md (Task 1), PRD §5.16/§5.17/§13 (Task 2), ARCHITECTURE users table + auth response (Task 3), privacy + terms with $39.99 (Tasks 4,5), price sweep (Task 6). §1 "$39.99" threaded everywhere.
- **Consistency:** monthly $3.99 / annual $39.99 / 7-day trial repeated identically across CLAUDE.md, PRD, Terms, Privacy. Trial-vs-subscription reconciliation-timer distinction matches Plan 1.
- **Ordering:** Task 7 flags the legal-pages-before-App-Store-review constraint from spec §7.
