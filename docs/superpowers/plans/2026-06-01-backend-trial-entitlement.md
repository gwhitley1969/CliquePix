# Backend — Trial Entitlement + Response Delta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 7-day, no-card, app-granted free trial on top of the already-built RevenueCat entitlement backend, so clients can gate on "subscribed OR in trial."

**Architecture:** A new nullable `users.trial_ends_at` column (set to `NOW() + 7 days` at first sign-in, backfilled for existing users at migration time) is the only state. The trial is computed live on every request — no timer, no stored boolean to drift. `buildAuthUserResponse` emits `in_trial` + `trial_ends_at` + `effective_active` inside the existing `entitlement` object, and `requireActiveEntitlement` passes when the user is subscribed OR within the trial window. Subscription/promotional logic (migration 012) is untouched.

**Tech Stack:** Azure Functions (TypeScript/Node), PostgreSQL Flexible Server, Jest. Migrations are numbered `.sql` files applied in order.

---

## Plan-wide context (read once)

This plan is **Plan 1 of 5** for the free-trial paywall + review-prompts spec (`docs/superpowers/specs/2026-06-01-paywall-trial-and-review-prompts-design.md`). The RevenueCat backend is already code-complete (migration 012, webhook, `entitlementService.ts`, `requireActiveEntitlement.ts`, `avatarEnricher.ts`) but **not yet applied/deployed**. This plan layers the trial on top of it. Plans 2–5 (Flutter paywall, Flutter review prompts, web gating, docs/legal) come after.

Files this plan touches:

- **Create:** `backend/src/shared/db/migrations/013_user_trial.sql`
- **Create:** `backend/src/__tests__/trialEntitlement.test.ts`
- **Modify:** `backend/src/shared/services/avatarEnricher.ts` (entitlement response shape + trial computation)
- **Modify:** `backend/src/shared/middleware/requireActiveEntitlement.ts` (pass trial users)
- **Modify:** `backend/src/shared/middleware/authMiddleware.ts` (SELECT + `AuthenticatedUser.trialEndsAt`)
- **Modify:** `backend/src/shared/models/user.ts` (add `trial_ends_at`)
- **Modify:** `backend/src/functions/auth.ts` (stamp `trial_ends_at` in the `authVerify` upsert)

Run all backend commands from the `backend/` directory unless noted. Test runner: `npm test` (jest). Type check: `npm run build`.

---

## Task 1: Migration 013 — `trial_ends_at` column + backfill

**Files:**
- Create: `backend/src/shared/db/migrations/013_user_trial.sql`

- [ ] **Step 1: Write the migration**

Create `backend/src/shared/db/migrations/013_user_trial.sql`:

```sql
-- App-granted free trial (no payment info required).
--
-- Layers on top of migration 012's RevenueCat entitlement columns. Effective
-- access = entitlement_active OR (trial_ends_at > NOW()). The trial is purely
-- time-based and computed live on every request (buildAuthUserResponse +
-- requireActiveEntitlement) — there is no stored boolean and therefore no
-- reconciliation timer for trial expiry.
--
-- Lifecycle:
--   * New users: auth.ts authVerify stamps trial_ends_at = NOW() + 7 days on
--     INSERT, and COALESCE-preserves it on every returning sign-in so re-auth
--     can never reset the window.
--   * Existing users at deploy time: backfilled to NOW() + 7 days below, so
--     nobody currently signed up is locked out the instant the gate goes live.
--     (Current beta testers + the reviewer also carry RevenueCat promotional
--     grants, which set entitlement_active = TRUE and trump trial state.)
--
-- Additive + nullable: safe for a rolling deploy. Old backend ignores the
-- column; new backend starts emitting in_trial / effective_active.

ALTER TABLE users ADD COLUMN trial_ends_at TIMESTAMPTZ;

UPDATE users SET trial_ends_at = NOW() + INTERVAL '7 days' WHERE trial_ends_at IS NULL;
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/shared/db/migrations/013_user_trial.sql
git commit -m "feat(db): migration 013 — app-granted trial_ends_at column"
```

> Migration application to `pg-cliquepixdb` happens in Task 6 (deploy), not here. There is no jest test for raw SQL; the column's behavior is exercised by Tasks 2–4.

---

## Task 2: Emit trial fields in the entitlement response

`buildEntitlementResponse` currently returns `{ active, product_id, period_type, will_renew, expires_at, store }`. Add `in_trial`, `trial_ends_at`, and `effective_active`. Export the function so it can be unit-tested directly (it's pure).

**Files:**
- Modify: `backend/src/shared/services/avatarEnricher.ts:108-158`
- Test: `backend/src/__tests__/trialEntitlement.test.ts`

- [ ] **Step 1: Write the failing test**

Create `backend/src/__tests__/trialEntitlement.test.ts`:

```typescript
import { buildEntitlementResponse, AuthUserRow } from '../shared/services/avatarEnricher';

// Minimal row factory — only the fields buildEntitlementResponse reads.
function row(overrides: Partial<AuthUserRow> = {}): AuthUserRow {
  return {
    id: 'u1',
    display_name: 'Test',
    email_or_phone: 't@example.com',
    avatar_blob_path: null,
    avatar_thumb_blob_path: null,
    avatar_updated_at: null,
    avatar_frame_preset: 0,
    avatar_prompt_dismissed: false,
    avatar_prompt_snoozed_until: null,
    created_at: new Date('2026-06-01T00:00:00Z'),
    ...overrides,
  };
}

const NOW = new Date('2026-06-10T00:00:00Z');

describe('buildEntitlementResponse — trial', () => {
  it('reports in_trial + effective_active when trial_ends_at is in the future', () => {
    const r = buildEntitlementResponse(
      row({ trial_ends_at: new Date('2026-06-15T00:00:00Z') }),
      NOW,
    );
    expect(r.in_trial).toBe(true);
    expect(r.effective_active).toBe(true);
    expect(r.active).toBe(false);
    expect(r.trial_ends_at).toBe('2026-06-15T00:00:00.000Z');
  });

  it('reports not-in-trial when trial_ends_at has passed and no subscription', () => {
    const r = buildEntitlementResponse(
      row({ trial_ends_at: new Date('2026-06-05T00:00:00Z') }),
      NOW,
    );
    expect(r.in_trial).toBe(false);
    expect(r.effective_active).toBe(false);
  });

  it('effective_active is true for an active subscriber even with an expired trial', () => {
    const r = buildEntitlementResponse(
      row({
        entitlement_active: true,
        trial_ends_at: new Date('2026-06-05T00:00:00Z'),
      }),
      NOW,
    );
    expect(r.active).toBe(true);
    expect(r.in_trial).toBe(false);
    expect(r.effective_active).toBe(true);
  });

  it('handles a null trial_ends_at (never stamped)', () => {
    const r = buildEntitlementResponse(row({ trial_ends_at: null }), NOW);
    expect(r.in_trial).toBe(false);
    expect(r.trial_ends_at).toBeNull();
    expect(r.effective_active).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- trialEntitlement`
Expected: FAIL — `buildEntitlementResponse` is not exported (TS error) and `EntitlementResponse` has no `in_trial`/`effective_active`.

- [ ] **Step 3: Implement**

In `backend/src/shared/services/avatarEnricher.ts`:

(a) Add `trial_ends_at` to the `AuthUserRow` interface (after the entitlement fields, around line 125):

```typescript
  entitlement_store?: string | null;
  // App-granted free trial (migration 013). Null until first sign-in stamps it.
  trial_ends_at?: Date | string | null;
}
```

(b) Extend the `EntitlementResponse` interface (around line 133):

```typescript
export interface EntitlementResponse {
  active: boolean;
  product_id: string | null;
  period_type: string | null;
  will_renew: boolean | null;
  expires_at: string | null;
  store: string | null;
  // Trial (migration 013). effective_active = active || in_trial — this is the
  // value the client paywall gate keys off.
  in_trial: boolean;
  trial_ends_at: string | null;
  effective_active: boolean;
}
```

(c) Replace `buildEntitlementResponse` (lines 142-158) with an exported, `now`-injectable version:

```typescript
export function buildEntitlementResponse(
  row: AuthUserRow,
  now: Date = new Date(),
): EntitlementResponse {
  let expiresAtIso: string | null = null;
  if (row.entitlement_expires_at) {
    expiresAtIso =
      row.entitlement_expires_at instanceof Date
        ? row.entitlement_expires_at.toISOString()
        : String(row.entitlement_expires_at);
  }

  let trialEndsAtIso: string | null = null;
  let inTrial = false;
  if (row.trial_ends_at) {
    const trialEnds =
      row.trial_ends_at instanceof Date
        ? row.trial_ends_at
        : new Date(row.trial_ends_at);
    trialEndsAtIso = trialEnds.toISOString();
    inTrial = trialEnds > now;
  }

  const active = row.entitlement_active ?? false;

  return {
    active,
    product_id: row.entitlement_product_id ?? null,
    period_type: row.entitlement_period_type ?? null,
    will_renew: row.entitlement_will_renew ?? null,
    expires_at: expiresAtIso,
    store: row.entitlement_store ?? null,
    in_trial: inTrial,
    trial_ends_at: trialEndsAtIso,
    effective_active: active || inTrial,
  };
}
```

(`buildAuthUserResponse` already calls `buildEntitlementResponse(row)` at line 181 — the default `now` keeps it working with no change there.)

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- trialEntitlement`
Expected: PASS (4 tests in the "trial" describe block).

- [ ] **Step 5: Commit**

```bash
git add backend/src/shared/services/avatarEnricher.ts backend/src/__tests__/trialEntitlement.test.ts
git commit -m "feat(entitlement): emit in_trial/effective_active in auth response"
```

---

## Task 3: Pass trial users through `requireActiveEntitlement`

The gate currently reads `authUser.entitlementActive`. It must also pass users inside the trial window. That requires `AuthenticatedUser.trialEndsAt`, which requires pulling the column in the `authMiddleware` SELECT and adding it to the `User` model.

**Files:**
- Modify: `backend/src/shared/models/user.ts`
- Modify: `backend/src/shared/middleware/authMiddleware.ts:30-48` (interface), `:87-95` (SELECT), `:114-129` (mapping)
- Modify: `backend/src/shared/middleware/requireActiveEntitlement.ts:24-28`
- Test: `backend/src/__tests__/trialEntitlement.test.ts` (append)

- [ ] **Step 1: Write the failing test**

Append to `backend/src/__tests__/trialEntitlement.test.ts`:

```typescript
import { requireActiveEntitlement } from '../shared/middleware/requireActiveEntitlement';
import type { AuthenticatedUser } from '../shared/middleware/authMiddleware';
import { SubscriptionRequiredError } from '../shared/utils/errors';

// Minimal AuthenticatedUser — requireActiveEntitlement only reads two fields.
function authUser(overrides: Partial<AuthenticatedUser> = {}): AuthenticatedUser {
  return {
    id: 'u1',
    externalAuthId: 'ext1',
    displayName: 'Test',
    emailOrPhone: 't@example.com',
    avatarBlobPath: null,
    avatarThumbBlobPath: null,
    avatarUpdatedAt: null,
    avatarFramePreset: 0,
    entitlementActive: false,
    entitlementProductId: null,
    entitlementPeriodType: null,
    entitlementWillRenew: null,
    entitlementExpiresAt: null,
    entitlementStore: null,
    trialEndsAt: null,
    ...overrides,
  };
}

const NOW2 = new Date('2026-06-10T00:00:00Z');

describe('requireActiveEntitlement — trial', () => {
  it('passes a subscribed user', () => {
    expect(() =>
      requireActiveEntitlement(authUser({ entitlementActive: true }), NOW2),
    ).not.toThrow();
  });

  it('passes a user within the trial window', () => {
    expect(() =>
      requireActiveEntitlement(
        authUser({ trialEndsAt: new Date('2026-06-15T00:00:00Z') }),
        NOW2,
      ),
    ).not.toThrow();
  });

  it('throws for an unsubscribed user with an expired trial', () => {
    expect(() =>
      requireActiveEntitlement(
        authUser({ trialEndsAt: new Date('2026-06-05T00:00:00Z') }),
        NOW2,
      ),
    ).toThrow(SubscriptionRequiredError);
  });

  it('throws for an unsubscribed user with no trial stamped', () => {
    expect(() => requireActiveEntitlement(authUser(), NOW2)).toThrow(
      SubscriptionRequiredError,
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- trialEntitlement`
Expected: FAIL — `AuthenticatedUser` has no `trialEndsAt`, and `requireActiveEntitlement` takes only one argument.

- [ ] **Step 3: Implement**

(a) In `backend/src/shared/models/user.ts`, add the column to the `User` interface (next to the entitlement fields):

```typescript
  trial_ends_at: Date | null;
```

(b) In `backend/src/shared/middleware/authMiddleware.ts`, add to the `AuthenticatedUser` interface (after `entitlementStore`, line 47):

```typescript
  entitlementStore: string | null;
  // App-granted trial window (migration 013). null = never stamped / pre-013.
  trialEndsAt: Date | null;
}
```

(c) Add `trial_ends_at` to the SELECT column list (line 91-92):

```typescript
            entitlement_active, entitlement_product_id, entitlement_period_type,
            entitlement_will_renew, entitlement_expires_at, entitlement_store,
            trial_ends_at
```

(d) Map it in the returned object (after `entitlementStore`, line 128):

```typescript
    entitlementStore: user.entitlement_store ?? null,
    trialEndsAt: user.trial_ends_at ?? null,
  };
```

(e) Replace the body of `requireActiveEntitlement` (`backend/src/shared/middleware/requireActiveEntitlement.ts:24-28`):

```typescript
export function requireActiveEntitlement(
  authUser: AuthenticatedUser,
  now: Date = new Date(),
): void {
  const inTrial = authUser.trialEndsAt != null && authUser.trialEndsAt > now;
  if (!authUser.entitlementActive && !inTrial) {
    throw new SubscriptionRequiredError();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- trialEntitlement`
Expected: PASS (all 8 tests — 4 from Task 2, 4 here).

- [ ] **Step 5: Commit**

```bash
git add backend/src/shared/models/user.ts backend/src/shared/middleware/authMiddleware.ts backend/src/shared/middleware/requireActiveEntitlement.ts backend/src/__tests__/trialEntitlement.test.ts
git commit -m "feat(entitlement): trial window passes requireActiveEntitlement gate"
```

---

## Task 4: Stamp `trial_ends_at` at first sign-in

`authVerify` upserts the user on every sign-in. Stamp the trial on INSERT and COALESCE-preserve it on returning logins so re-auth can't reset the window.

**Files:**
- Modify: `backend/src/functions/auth.ts:147-157`

- [ ] **Step 1: Update the upsert**

Replace the `INSERT INTO users ...` statement (lines 147-157) with:

```typescript
    const user = await queryOne<User>(
      `INSERT INTO users (external_auth_id, display_name, email_or_phone, age_verified_at, trial_ends_at)
       VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days')
       ON CONFLICT (external_auth_id) DO UPDATE SET
         display_name = EXCLUDED.display_name,
         email_or_phone = EXCLUDED.email_or_phone,
         age_verified_at = COALESCE(users.age_verified_at, EXCLUDED.age_verified_at),
         trial_ends_at = COALESCE(users.trial_ends_at, EXCLUDED.trial_ends_at),
         updated_at = NOW()
       RETURNING *`,
      [externalAuthId, displayName, email, ageVerifiedAt],
    );
```

> `getMe` (line 174) and `deleteMe` (line 292) use `SELECT *`, so they pick up `trial_ends_at` with no change. `buildAuthUserResponse(user)` already receives the full row and now emits the trial fields via Task 2.

- [ ] **Step 2: Type-check**

Run: `npm run build`
Expected: PASS (no TS errors). This confirms the `User` model field from Task 3 lines up with `RETURNING *`.

- [ ] **Step 3: Commit**

```bash
git add backend/src/functions/auth.ts
git commit -m "feat(auth): stamp 7-day trial_ends_at on first sign-in"
```

---

## Task 5: Full suite green + fix any response-shape fixtures

Adding `in_trial`/`trial_ends_at`/`effective_active` to the entitlement object can break existing tests that do exact-object matching (`toEqual`) on an auth/profile response — notably `backend/src/__tests__/avatarEnricher.test.ts`.

**Files:**
- Modify (if red): `backend/src/__tests__/avatarEnricher.test.ts` and any other fixture asserting the entitlement object shape.

- [ ] **Step 1: Run the entire backend test suite**

Run: `npm test`
Expected: All suites pass. Baseline before this plan was 164/164; the target is 164 + the 8 new trial tests = **172 passing**.

- [ ] **Step 2: If any test fails on the entitlement object shape, update its expectation**

For each failing `toEqual`/`toMatchObject` that asserts the `entitlement` block, add the three new keys to the expected object. For a non-subscribed, non-trial fixture (no `trial_ends_at` on the input row) the additions are:

```typescript
      in_trial: false,
      trial_ends_at: null,
      effective_active: false,
```

Prefer `toMatchObject` over `toEqual` only if the existing test already used it — do not loosen assertions that were intentionally strict; just add the missing keys.

- [ ] **Step 3: Re-run until green**

Run: `npm test`
Expected: 172/172 (or 164 + 8 + however many fixtures existed) — zero failures.

- [ ] **Step 4: Commit (only if fixtures changed)**

```bash
git add backend/src/__tests__/
git commit -m "test: update auth-response fixtures for trial fields"
```

---

## Task 6: Apply migration + deploy + smoke (ops)

These are operational steps run by Gene against production Azure resources. No code changes.

- [ ] **Step 1: Apply migration 013 to `pg-cliquepixdb`**

Apply `013_user_trial.sql` using the same path used for migrations 008–012 (psql against the Flexible Server, or the project's migration runner). Verify:

```sql
SELECT column_name FROM information_schema.columns
  WHERE table_name = 'users' AND column_name = 'trial_ends_at';
-- expect one row
SELECT count(*) FROM users WHERE trial_ends_at IS NULL;
-- expect 0 (backfill covered all existing rows)
```

- [ ] **Step 2: Deploy the backend**

Run (from `backend/`): `func azure functionapp publish func-cliquepix-fresh`
Expected: deploy succeeds; `GET https://api.clique-pix.com/api/health` returns HTTP 200.

- [ ] **Step 3: Smoke the response shape**

With a valid bearer token for a normal (non-promo) test account whose trial is still active:

```bash
curl -s -H "Authorization: Bearer <token>" https://api.clique-pix.com/api/users/me | python -m json.tool
```

Expected: the `data.entitlement` object includes `in_trial: true`, a future `trial_ends_at`, and `effective_active: true`. A gated endpoint (e.g. `GET /api/events`) returns 200 (trial passes the gate), NOT 402.

> Do NOT ship the Flutter build that hard-gates on `effective_active` (Plan 2) until this deploy is live — older clients are unaffected (additive fields), but the new client depends on these fields existing.

---

## Self-review notes (already applied)

- **Spec coverage:** §2 (trial model: migration, `in_trial`/`effective_active` emission, `requireActiveEntitlement` pass, `COALESCE`-preserved stamp, no reconciliation timer, promo-grant precedence) — all covered by Tasks 1–4. §7 deploy-before-client ordering — Task 6 note.
- **Type consistency:** `trial_ends_at` (DB/row, snake_case) ↔ `trialEndsAt` (`AuthenticatedUser`, camelCase) ↔ `in_trial`/`effective_active`/`trial_ends_at` (response JSON, snake_case) are used consistently across Tasks 2–4. `buildEntitlementResponse` signature `(row, now=new Date())` matches its call site in `buildAuthUserResponse` (default `now`) and the tests (explicit `now`).
- **Out of scope (later plans):** client `EntitlementState` parsing, paywall gate, review prompts, web, docs/legal/$39.99 — Plans 2–5.
