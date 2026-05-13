# Clique Pix — Install-Aware QR Invites (Deferred Deep Linking)

**Last Updated:** May 13, 2026

This doc explains how Clique Pix QR-code invites bridge the "scanner doesn't have the app installed" gap. It complements `docs/ARCHITECTURE.md` (top-level system) and `docs/WEB_CLIENT_ARCHITECTURE.md` (web client design).

---

## The Problem

A Clique Pix user generates an invite QR encoding `https://clique-pix.com/invite/{inviteCode}`. The recipient scans it on a phone that doesn't have Clique Pix installed. Without deferred-deep-link plumbing, the recipient gets dropped on a web page with no install path, OR they install the app and then have to manually type/scan the invite code a second time.

## The Solution

A three-phase design:

| Phase | Platform | What it does | Status |
|---|---|---|---|
| **A** | Web | Install banner on `/invite/{code}` + benefit bullets + platform-appropriate Store badge | Shipped 2026-05-13 |
| **B** | Android | Play Install Referrer carries `invite_code=...` from the Play Store URL → Flutter reads it on first launch → auto-joins after sign-in | Shipped 2026-05-13 |
| **C** | iOS | Smart App Banner meta tag in `webapp/index.html` (`<meta name="apple-itunes-app">`); native Safari banner with `app-argument` delivered via `NSUserActivity` after install | Gated on iOS App Store listing — pending |

Each phase ships independently; none blocks the others.

---

## Phase A — Web invite page (shipped)

**File:** `webapp/src/features/cliques/InviteAcceptScreen.tsx`

When an unauthenticated user lands on `/invite/{code}`:

1. `detectPlatform()` returns `'android' | 'ios' | 'desktop'` from `navigator.userAgent` (see `webapp/src/lib/platform.ts`).
2. `<InstallBanner inviteCode={code} platform={platform} />` renders above the existing "Sign in to accept" CTA:
   - **Android + Desktop:** shows "Get the full Clique Pix experience" + benefit bullets + a `<PlayStoreBadge>` whose `href` is `https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix&referrer={URL-encoded invite_code=CODE}`.
   - **iOS:** banner is hidden entirely (returns `null`) until the App Store listing is live and Phase C ships. iOS users go straight to the existing web sign-in CTA.
3. The existing "Sign in to accept" CTA stays exactly where it was. It's the explicit no-install alternative — anyone can join entirely on the web without ever touching a mobile app.

**Below the CTA**, a small caption nudges install on non-iOS platforms: *"Or install the app above — your invite will be waiting when you sign in."*

**No iOS Smart App Banner ships in Phase A.** The `<meta name="apple-itunes-app">` tag requires a real App Store `app-id` and renders a console warning in Safari without one. Phase C activates it when the App Store listing goes live.

---

## Phase B — Android Play Install Referrer (shipped)

**Files:**
- `app/lib/services/install_referrer_service.dart` (new)
- `app/lib/main.dart` (`performDeferredInit` invokes the service)
- `app/lib/app/app.dart` (`_CliquePixState` consumes the pending code)
- `app/pubspec.yaml` (`play_install_referrer: ^0.5.0`)

### Flow

```
1. User taps Play Store badge on web invite page
   ↓ URL: https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix&referrer=invite_code%3DABC123
2. Play Store installs the AAB; referrer string captured by Play
3. First app launch — `performDeferredInit()` runs after first frame
   ↓ `InstallReferrerService.readAndPersistOnce()`
   ↓ Calls `PlayInstallReferrer.installReferrer` once (gated by `install_referrer_consumed` SharedPreferences flag)
   ↓ Parses `invite_code=ABC123` out of the referrer string
   ↓ Persists to SharedPreferences key `install_referrer_pending_invite_code`
   ↓ Records `install_referrer_read{had_invite_code=true|false}` to the pending-isolate telemetry queue
4. User signs in (or was already authed at bootstrap)
   ↓ AuthNotifier transitions to AuthAuthenticated
5. `_CliquePixState._consumePendingInstallReferrerInvite()` fires (via post-frame callback OR `ref.listen` on AuthState)
   ↓ Reads the pending code from SharedPreferences
   ↓ Clears the key
   ↓ Records `install_referrer_auto_join_attempted`
   ↓ `router.go('/invite/ABC123')`
6. `JoinCliqueScreen.initState` calls `_joinClique()` automatically
   ↓ `cliquesRepository.joinByInviteCode('ABC123')`
   ↓ On success: routes to `/cliques/{id}` (existing behavior)
   ↓ On error: existing graceful error UI ("That invite is no longer valid" etc.)
```

### Idempotency invariants

- **`install_referrer_consumed`** flag is set after the FIRST read attempt regardless of result. Subsequent cold starts skip the Play API call entirely (saves battery; the Play API is expensive).
- **`install_referrer_pending_invite_code`** is cleared as soon as the auth-state listener consumes it. A force-stop + cold-restart after consumption does NOT re-fire the auto-join.
- **`_inviteAutoJoinChecked`** in-memory flag in `_CliquePixState` guards against re-firing within the same process. Reset to `false` when the user transitions OUT of `AuthAuthenticated` (sign-out → sign-in as new user) so a new pending invite can be consumed.
- **Uninstall + reinstall** clears Android's per-app SharedPreferences, so a new referrer is correctly captured.

### Edge cases handled

| Case | Handling |
|---|---|
| User installs via referrer, never signs in | Pending code stays in SharedPreferences indefinitely. Consumed only after first `AuthAuthenticated`. |
| User installs WITHOUT a referrer (organic, sideload, ADB install) | Service no-ops; SharedPreferences key never written; `_consumePendingInstallReferrerInvite` finds nothing and returns. |
| User already a member of the target clique | `cliquesRepository.joinByInviteCode` returns success or 409; `JoinCliqueScreen`'s existing flow handles either. |
| Invite expired between web-tap and app-install | `cliquesRepository.joinByInviteCode` returns 404/410; `JoinCliqueScreen` shows its existing error UI; user lands on home. |
| Network failure during auto-join | `JoinCliqueScreen` shows the error inline; user can retry from the same screen. Pending code is already cleared so no infinite retry loop. |
| Sign-in fails (wrong account, MSAL cancellation) | Pending code remains in SharedPreferences; consumed on the next successful sign-in. |
| iOS install | `Platform.isAndroid` check makes the service a no-op. SharedPreferences key is never written. |

### Why SharedPreferences, not a Riverpod provider

The pending invite code must survive process death between the referrer-read (fires during `performDeferredInit` post-first-frame) and the consume (fires after `AuthAuthenticated` post-sign-in, which may be minutes or days later if the user closes the app between install and first sign-in). SharedPreferences is the durable primitive; a Riverpod provider would be lost when the process dies.

---

## Phase C — iOS Smart App Banner (deferred)

**Activation steps when the iOS App Store listing goes live:**

1. Get the App Store ID for Clique Pix (a numeric value Apple assigns to the listing).
2. Add to `webapp/index.html` in `<head>`:
   ```html
   <meta name="apple-itunes-app" content="app-id=APPSTORE_ID_HERE">
   ```
3. In `InviteAcceptScreen.tsx`, add a `useEffect` that rewrites the meta tag's `content` attribute on mount to include `app-argument`:
   ```ts
   useEffect(() => {
     if (!code) return;
     const meta = document.querySelector('meta[name="apple-itunes-app"]') as HTMLMetaElement | null;
     if (!meta) return;
     const url = window.location.href; // https://clique-pix.com/invite/CODE
     meta.content = `app-id=APPSTORE_ID_HERE, app-argument=${url}`;
   }, [code]);
   ```
4. On iPhone Safari, the page renders Apple's native install banner at the top. `app-argument` is delivered to the app via `NSUserActivity.webpageURL` when the user taps the banner — handled by the same Universal Link path that already works today.
5. Remove the `if (platform === 'ios') return null;` early-return in `InstallBanner.tsx` if a secondary in-page App Store badge is desired alongside Apple's banner. Optional.

**Caveat — Universal Links same-domain rule.** Apple's `NSUserActivity` Universal Link does NOT fire when navigating WITHIN `clique-pix.com` in Safari. Don't add an "Open in App" hyperlink on the invite page that points at the same URL — it silently does nothing. The Smart App Banner is the only viable mechanism; OR direct the user to re-tap the original invite link from another app (Messages, Mail, etc.) where the navigation IS cross-domain.

---

## Telemetry events

All events flow through the standard pipelines per `CLAUDE.md`.

| Event | Properties | Emitter | Pipeline |
|---|---|---|---|
| `web_invite_install_banner_shown` | `platform: 'android'\|'desktop'` | `InstallBanner.tsx` | `webapp/src/lib/ai.ts` → App Insights |
| `web_invite_install_badge_clicked` | `platform: 'android'` | `InstallBanner.tsx` onClick | Same |
| `web_invite_web_signin_clicked` | — | `InviteAcceptScreen.tsx` onSignIn | Same |
| `install_referrer_read` | `had_invite_code=true\|false` (in `errorCode` slot of the pending-isolate queue format) | `InstallReferrerService` | `auth_telemetry_pending` SharedPreferences → drained by `TelemetryService.drainPendingIsolateEvents` → `/api/telemetry/auth` → App Insights |
| `install_referrer_auto_join_attempted` | — | `_CliquePixState._consumePendingInstallReferrerInvite` | `telemetryServiceProvider.record` → `/api/telemetry/auth` |

Success/failure of the actual clique join (existing `clique_joined` event in the cliques handler) tracks whether the auto-join lands.

---

## Verification

### Local Android (simulating Play Install Referrer via adb)

```bash
# 1. Install a debug build via `flutter run` or `flutter install`.
# 2. BEFORE first sign-in, simulate the referrer:
adb shell am broadcast \
  -a com.android.vending.INSTALL_REFERRER \
  -n com.cliquepix.clique_pix/com.google.android.finsky.installer.BroadcastReceiver \
  --es referrer "invite_code=TESTCODE123"

# 3. Open the app, sign in. Expect: lands on /invite/TESTCODE123 → JoinCliqueScreen.
```

If you need a real invite code instead of a fake one, generate it from another device's Clique Pix install (Cliques → invite → copy code) and use it in the broadcast.

### Real Play Store install

1. Ship a new AAB to Open Testing or Production with the `play_install_referrer` integration (current AAB versionCode=3 is pre-integration; you'll need versionCode=4+ for Phase B to take effect).
2. Wait for Play approval.
3. On a clean Android device, navigate to `https://clique-pix.com/invite/{any-real-code}` in Chrome → tap the Play Store badge → install → sign in.
4. Confirm App Insights shows `install_referrer_read{had_invite_code=true}` followed by `install_referrer_auto_join_attempted` and the existing `clique_joined` event.

### Web invite page UA detection

Open `clique-pix.com/invite/test-code-here`:
- On Android phone (Chrome): banner shows, Play badge has the referrer URL
- On iPhone (Safari): banner is hidden; only the sign-in CTA renders
- On desktop browser: banner shows, Play badge has the referrer URL

---

## What this is NOT

- **Not a third-party deferred-deep-link service.** No Branch.io, no AppsFlyer, no Firebase Dynamic Links (deprecated August 2025 anyway).
- **Not an iOS clipboard hack.** The Smart App Banner is the native Apple primitive; we don't fight Apple by writing to UIPasteboard from Safari.
- **Not iOS App Clips.** App Clips are a separate Xcode target with its own Apple review — out of scope for v1.
- **Not a backend change.** The existing `POST /api/cliques/_/join` endpoint serves both Phase A (web join) and Phase B (Flutter auto-join). No new endpoints, no schema changes.

---

## Related docs

- `docs/ARCHITECTURE.md` — top-level system architecture
- `docs/WEB_CLIENT_ARCHITECTURE.md` — web client overall design, MSAL, hosting
- `docs/BETA_TEST_PLAN.md` — Section 2 (Cliques) includes the install-aware-QR test cases that exercise this flow
- `CLAUDE.md` — Deep Linking section and Tech Stack lock-in
