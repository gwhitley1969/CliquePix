# Web — Subscription Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate the React web client so authenticated users without `effective_active` (subscribed OR in trial) are redirected to a `/subscribe` screen that points them to the mobile app; trial/subscribed users get the full app. No web purchase flow.

**Architecture:** Extend the `User` interface with the `entitlement` object, add an `EntitlementGuard` that wraps the authenticated `AppLayout` and redirects to `/subscribe` when access is missing, and a dark-themed `SubscribeInAppScreen` reusing the existing store-badge components.

**Tech Stack:** React 18, TypeScript, React Router v6, `@tanstack/react-query`, `@azure/msal-react`, Tailwind. Build: `npm run build`; lint: `npm run lint` (from `webapp/`).

---

## Plan-wide context (read once)

**Plan 4 of 5.** Depends on **Plan 1 (backend) deployed** — the web client reads `entitlement.effective_active` from `/api/auth/verify`. MSAL.js refreshes silently, so there's no 5-layer concern here.

**Response-shape rule (critical):** the axios interceptor at `webapp/src/api/camelize.ts` converts every response `snake_case → camelCase`. So the backend's `effective_active` arrives at the TypeScript layer as **`effectiveActive`**, `in_trial` as `inTrial`, `trial_ends_at` as `trialEndsAt`, etc. The `User` interface must reflect the post-transform (camelCase) shape.

Confirmed surfaces:
- Router: `webapp/src/app/router.tsx` (`createBrowserRouter`, lines 20-61). `AuthGuard` at `webapp/src/auth/AuthGuard.tsx`. The authenticated shell is a pathless parent wrapping `<AuthGuard><AppLayout/></AuthGuard>` with children `/events`,`/cliques`,`/notifications`,`/profile`, etc.
- User model: `webapp/src/models/index.ts` (`User` interface, lines 14-27). Auth user surfaced via `useAuthVerify()` (`webapp/src/features/auth/useAuthVerify.ts`) which react-queries `verifyAuth()` (`webapp/src/api/endpoints/auth.ts`).
- Profile: `webapp/src/features/profile/ProfileScreen.tsx`.
- Store badges: `webapp/src/features/landing/components/{AppStoreBadge,PlayStoreBadge}.tsx`. Play URL `https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix`; App Store URL still `#`.
- Design tokens: Tailwind classes `bg-dark-bg` (#0E1525), `bg-gradient-primary`, `text-aqua`, `bg-dark-card`.

**Files:**
- Create: `webapp/src/auth/EntitlementGuard.tsx`, `webapp/src/features/paywall/SubscribeInAppScreen.tsx`
- Modify: `webapp/src/models/index.ts`, `webapp/src/app/router.tsx`, `webapp/src/features/profile/ProfileScreen.tsx`

---

## Task 1: Add `entitlement` to the `User` interface

**Files:** Modify `webapp/src/models/index.ts:14-27`

- [ ] **Step 1: Add the entitlement type + field**

In `webapp/src/models/index.ts`, add an `Entitlement` interface and the field on `User` (camelCase — post-camelize):

```typescript
export interface Entitlement {
  active: boolean;
  productId: string | null;
  periodType: string | null;
  willRenew: boolean | null;
  expiresAt: string | null;
  store: string | null;
  inTrial: boolean;
  trialEndsAt: string | null;
  effectiveActive: boolean;
}

export interface User extends AvatarFields {
  id: string;
  emailOrPhone: string;
  displayName: string;
  createdAt?: string;
  ageVerified?: boolean;
  shouldPromptForAvatar?: boolean;
  /** Subscription/trial state. Absent on a pre-paywall backend → treat as no access. */
  entitlement?: Entitlement;
}
```

- [ ] **Step 2: Build to verify types**

Run (from `webapp/`): `npm run build`
Expected: type-checks clean.

- [ ] **Step 3: Commit**

```bash
git add webapp/src/models/index.ts
git commit -m "feat(web): add entitlement to User model"
```

---

## Task 2: `SubscribeInAppScreen`

**Files:** Create `webapp/src/features/paywall/SubscribeInAppScreen.tsx`

- [ ] **Step 1: Create the screen**

Create `webapp/src/features/paywall/SubscribeInAppScreen.tsx`:

```tsx
import { useMsal } from '@azure/msal-react';
import { AppStoreBadge } from '../landing/components/AppStoreBadge';
import { PlayStoreBadge } from '../landing/components/PlayStoreBadge';

const PLAY_URL =
  'https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix';

export function SubscribeInAppScreen() {
  const { instance } = useMsal();
  return (
    <div className="min-h-screen bg-dark-bg flex flex-col items-center justify-center px-6 text-center">
      <div className="max-w-md w-full rounded-lg bg-dark-card border border-white/10 p-8">
        <div className="mx-auto mb-5 h-14 w-14 rounded-2xl bg-gradient-primary" />
        <h1 className="text-2xl font-bold mb-2">CLIQUE Pix Plus</h1>
        <p className="text-white/70 mb-6">
          Your free trial has ended. Subscribe in the CLIQUE Pix mobile app to
          keep sharing — your subscription unlocks the app everywhere, including
          here on the web.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3 mb-8">
          <AppStoreBadge />
          <PlayStoreBadge href={PLAY_URL} />
        </div>
        <button
          className="text-sm text-white/50 hover:text-white/80"
          onClick={() =>
            instance.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error)
          }
        >
          Sign out
        </button>
        <div className="mt-6 text-xs text-white/40 space-x-3">
          <a href="/docs/privacy" className="hover:underline">Privacy Policy</a>
          <span>·</span>
          <a href="/docs/terms" className="hover:underline">Terms of Service</a>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Build + commit**

Run: `npm run build`
Expected: clean.
```bash
git add webapp/src/features/paywall/SubscribeInAppScreen.tsx
git commit -m "feat(web): SubscribeInAppScreen"
```

---

## Task 3: `EntitlementGuard`

**Files:** Create `webapp/src/auth/EntitlementGuard.tsx`

- [ ] **Step 1: Create the guard**

Create `webapp/src/auth/EntitlementGuard.tsx`. It runs INSIDE `AuthGuard` (so the user is already authenticated), reads the verified user via `useAuthVerify()`, and redirects to `/subscribe` when access is missing:

```tsx
import { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuthVerify } from '../features/auth/useAuthVerify';

/** Render-gate for authenticated routes. Assumes AuthGuard already passed.
 *  Sends users without effective access to /subscribe. */
export function EntitlementGuard({ children }: { children: ReactNode }) {
  const { data: user, isLoading } = useAuthVerify();

  // Wait for the verify call before deciding — avoids a paywall flash.
  if (isLoading || !user) return null;

  const hasAccess = user.entitlement?.effectiveActive === true;
  if (!hasAccess) return <Navigate to="/subscribe" replace />;

  return <>{children}</>;
}
```

- [ ] **Step 2: Build + commit**

Run: `npm run build`
Expected: clean.
```bash
git add webapp/src/auth/EntitlementGuard.tsx
git commit -m "feat(web): EntitlementGuard redirect to /subscribe"
```

---

## Task 4: Wire routes

**Files:** Modify `webapp/src/app/router.tsx:20-61`

- [ ] **Step 1: Add `/subscribe` and wrap the shell**

In `router.tsx`:

(a) Add imports:
```typescript
import { EntitlementGuard } from '../auth/EntitlementGuard';
import { SubscribeInAppScreen } from '../features/paywall/SubscribeInAppScreen';
```

(b) Add a `/subscribe` route (authed but NOT entitlement-gated — it's where the gate sends people). Place it as a sibling of `/profile`-style routes but reachable behind AuthGuard only:
```typescript
  {
    path: '/subscribe',
    element: (
      <AuthGuard>
        <SubscribeInAppScreen />
      </AuthGuard>
    ),
  },
```

(c) Wrap the authenticated shell with `EntitlementGuard` INSIDE `AuthGuard`, but keep `/profile` reachable without entitlement. Two options — implement option A (split Profile out of the gated shell):

```typescript
  // Authenticated shell — entitlement-gated app.
  {
    element: (
      <AuthGuard>
        <EntitlementGuard>
          <AppLayout />
        </EntitlementGuard>
      </AuthGuard>
    ),
    children: [
      { path: '/events', element: <EventsListScreen /> },
      { path: '/events/:id', element: <EventDetailScreen /> },
      { path: '/events/:id/messages', element: <MessagesScreen /> },
      { path: '/events/:id/messages/new', element: <NewMessageScreen /> },
      { path: '/events/:id/messages/:threadId', element: <ThreadScreen /> },
      { path: '/cliques', element: <CliquesListScreen /> },
      { path: '/cliques/:id', element: <CliqueDetailScreen /> },
      { path: '/notifications', element: <NotificationsScreen /> },
    ],
  },
  // Profile stays reachable WITHOUT entitlement (account self-service) — inside
  // AuthGuard + AppLayout but outside EntitlementGuard.
  {
    element: (
      <AuthGuard>
        <AppLayout />
      </AuthGuard>
    ),
    children: [{ path: '/profile', element: <ProfileScreen /> }],
  },
```
`/` (landing), `/login`, `/auth/callback`, `/invite/:code`, `/docs/*` remain public and ungated (unchanged). This satisfies the allowlist (`/subscribe`, `/profile`, `/login`, `/docs/*`, `/`).

- [ ] **Step 2: Build + commit**

Run: `npm run build`
Expected: clean.
```bash
git add webapp/src/app/router.tsx
git commit -m "feat(web): gate app shell on entitlement, /profile + /subscribe exempt"
```

---

## Task 5: Profile "Manage Subscription" link

**Files:** Modify `webapp/src/features/profile/ProfileScreen.tsx:127-143`

- [ ] **Step 1: Add the link**

In the buttons section (above Sign out, ~line 127), add a link to the platform subscription pages (web can't manage a mobile sub directly — point users to their store):

```tsx
      <a
        href="https://apps.apple.com/account/subscriptions"
        target="_blank"
        rel="noreferrer"
        className="flex items-center w-full justify-start px-3 py-2 rounded-lg hover:bg-white/5 text-sm"
      >
        Manage Subscription
      </a>
```

> A single link to Apple's subscription management is sufficient for v1; Android users manage via the Play Store app. Keep it simple — no store-detection on web.

- [ ] **Step 2: Build + commit**

Run: `npm run build`
Expected: clean.
```bash
git add webapp/src/features/profile/ProfileScreen.tsx
git commit -m "feat(web): Manage Subscription link in Profile"
```

---

## Task 6: Verification

- [ ] **Step 1: Lint + build**

Run: `npm run lint && npm run build`
Expected: both clean.

- [ ] **Step 2: Local smoke (after Plan 1 deployed)**

Run: `npm run dev`, sign in as:
- A trial/subscribed user → full `/events` access, no redirect.
- An expired-trial unsubscribed user → redirected to `/subscribe`; `/profile` still reachable; store badges render; Sign out works.

---

## Self-review notes (already applied)

- **Spec coverage:** §3 web gating ("subscribe in mobile app", allowlist `/subscribe`,`/profile`,`/login`,`/docs/*`,`/`) — Tasks 3,4. Base-plan Phase 4 (User model entitlement, SubscribeInAppScreen reusing badges, Profile manage link) — Tasks 1,2,5.
- **Type consistency:** camelize means the interface uses `effectiveActive`/`inTrial`/`trialEndsAt` (Task 1), read identically in `EntitlementGuard` (`user.entitlement?.effectiveActive`, Task 3).
- **Allowlist correctness:** `/profile` is split into its own ungated shell branch (Task 4) so account self-service survives the gate; public routes untouched.
