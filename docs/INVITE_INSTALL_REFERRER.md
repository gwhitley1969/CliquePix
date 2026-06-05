# Clique Pix — Install-Aware QR Invites (Deferred Deep Linking)

**Last Updated:** May 13, 2026

This doc explains how Clique Pix QR-code invites bridge the "scanner doesn't have the app installed" gap. It complements `docs/ARCHITECTURE.md` (top-level system) and `docs/WEB_CLIENT_ARCHITECTURE.md` (web client design).

---

## The Problem

A Clique Pix user generates an invite QR encoding `https://clique-pix.com/invite/{inviteCode}`. The recipient scans it on a phone that doesn't have Clique Pix installed. Without deferred-deep-link plumbing, the recipient gets dropped on a web page with no install path, OR they install the app and then have to manually type/scan the invite code a second time.

## The Solution

A four-phase design (Phase C split into interim + final after TestFlight confirmation):

| Phase | Platform | What it does | Status |
|---|---|---|---|
| **A** | Web | Install banner on `/invite/{code}` + benefit bullets + platform-appropriate Store badge | Shipped 2026-05-13 |
| **B** | Android | Play Install Referrer carries `invite_code=...` from the Play Store URL → Flutter reads it on first launch → auto-joins after sign-in | Shipped 2026-05-13 |
| **C-interim** | iOS | TestFlight badge on the iOS branch of the install banner → user installs via TestFlight → retaps original invite link from Messages → Universal Link routes into the app and joins | Shipped 2026-05-13 |
| **C-final** | iOS | Smart App Banner meta tag in `webapp/index.html` (`<meta name="apple-itunes-app">`) + `app-argument` rewrite; native Safari banner delivers the invite URL to the app via `NSUserActivity.webpageURL` post-install | Gated on iOS App Store listing approval |

Each phase ships independently; none blocks the others.

**iOS identifiers (for reference):**
- Apple ID (numeric, for Smart App Banner `app-id`): `6766294274`
- Bundle ID: `com.cliquepix.app`
- TestFlight public link: `https://testflight.apple.com/join/hWznNvJ6`
- AASA Team ID: `4ML27KY869`

---

## Phase A — Web invite page (shipped)

**File:** `webapp/src/features/cliques/InviteAcceptScreen.tsx`

When an unauthenticated user lands on `/invite/{code}`:

1. `detectPlatform()` returns `'android' | 'ios' | 'desktop'` from `navigator.userAgent` (see `webapp/src/lib/platform.ts`).
2. `<InstallBanner inviteCode={code} platform={platform} />` renders above the existing "Sign in to accept" CTA:
   - **Android + Desktop:** shows "Get the full Clique Pix experience" + benefit bullets + a `<PlayStoreBadge>` whose `href` is `https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix&referrer={URL-encoded invite_code=CODE}`.
   - **iOS:** same headline + bullets, but the badge is a `<TestFlightBadge>` pointing at `https://testflight.apple.com/join/hWznNvJ6`. A small caption underneath reads *"iOS is in public beta on TestFlight. After installing, tap your invite link again to join the Clique."* — sets the right expectation since iOS has no deferred-deep-link path post-install.
3. The existing "Sign in to accept" CTA stays exactly where it was. It's the explicit no-install alternative — anyone can join entirely on the web without ever touching a mobile app.

**Below the CTA**, a small caption nudges install on non-iOS platforms: *"Or install the app above — your invite will be waiting when you sign in."* (Android-specific because Play Install Referrer actually preserves the code through install; iOS users see the in-banner caption that sets the correct retap-after-install expectation.)

**No iOS Smart App Banner ships in Phase A or C-interim.** The `<meta name="apple-itunes-app">` tag requires a real App Store `app-id` AND a publicly listed app at that ID. The Apple ID `6766294274` exists in App Store Connect today but no public listing is approved yet (verified 2026-05-13 via `https://itunes.apple.com/lookup?id=6766294274` — `resultCount: 0`). Phase C-final activates the meta tag when Apple approves the public listing.

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

## Phase C-interim — iOS TestFlight badge (shipped)

**Files:**
- `webapp/src/features/landing/components/TestFlightBadge.tsx` (new) — visual chassis matches `AppStoreBadge.tsx` (dark background, Apple icon from `lucide-react`); copy "Get it via / TestFlight". `target="_blank" rel="noopener noreferrer"` so the TestFlight enrollment URL opens cleanly outside the React app.
- `webapp/src/features/cliques/InstallBanner.tsx` — iOS branch renders `<TestFlightBadge href={TESTFLIGHT_URL}>` + retap-after-install caption.

### Flow (iOS, app not installed, pre-public-App-Store)

```
1. iOS user scans Clique invite QR
2. Mobile Safari opens https://clique-pix.com/invite/{code}
3. InstallBanner renders with TestFlightBadge + retap caption
4. User taps badge → opens https://testflight.apple.com/join/hWznNvJ6 in Safari
5. If TestFlight app NOT installed: prompt to install TestFlight from App Store
6. TestFlight app opens → "Accept" Clique Pix beta → install
7. User opens Clique Pix → signs in → lands on Home (no invite code preserved)
8. User retaps original invite link from Messages / wherever Person A shared it
9. Safari sees `clique-pix.com/invite/{code}` cross-domain navigation from Messages
   ↓ Universal Link via .well-known/apple-app-site-association fires
   ↓ App opens at JoinCliqueScreen with the code
10. JoinCliqueScreen auto-joins → user lands in clique detail
```

### Known iOS limitations (documented in the banner caption)

- **No deferred-deep-link.** No Apple equivalent of Play Install Referrer; the invite code is NOT carried through the TestFlight install.
- **Retap requirement.** User MUST retap the invite link AFTER install to trigger Universal Link routing. The in-banner caption tells them this explicitly.
- **TestFlight requires the TestFlight app.** First-time iOS testers install the TestFlight app from the App Store before they can install Clique Pix. ~2 taps of additional friction.

### TestFlight URL constant

Currently hardcoded as `TESTFLIGHT_URL` in `InstallBanner.tsx`. If the TestFlight enrollment link ever rotates (rare — it's tied to the public link Apple generates per-app), update the constant in one place.

---

## Phase C-final — iOS Smart App Banner (deferred, App Store listing dependency)

**Activation steps when the iOS App Store listing goes live (Apple approves the public submission):**

1. Confirm the public listing is live via `https://itunes.apple.com/lookup?id=6766294274` — `resultCount: 1`.
2. Add to `webapp/index.html` in `<head>` (Apple ID is `6766294274`):
   ```html
   <meta name="apple-itunes-app" content="app-id=6766294274">
   ```
3. In `webapp/src/features/cliques/InviteAcceptScreen.tsx`, add a `useEffect` that rewrites the meta tag's `content` attribute on mount to include `app-argument`:
   ```ts
   useEffect(() => {
     if (!code) return;
     const meta = document.querySelector('meta[name="apple-itunes-app"]') as HTMLMetaElement | null;
     if (!meta) return;
     const url = window.location.href; // https://clique-pix.com/invite/CODE
     meta.content = `app-id=6766294274, app-argument=${url}`;
   }, [code]);
   ```
4. Swap the `<TestFlightBadge>` in `InstallBanner.tsx` iOS branch for an `<AppStoreBadge href={'https://apps.apple.com/us/app/clique-pix/id6766294274'}>`. Update banner caption to drop the "retap after install" instruction (Smart App Banner's native "OPEN" flow delivers `app-argument` automatically).
5. On iPhone Safari, the page renders Apple's native install banner at the TOP of the viewport (above our in-page banner). `app-argument` is delivered to the app via `NSUserActivity.webpageURL` when the user taps "OPEN" — handled by the same Universal Link path that already works today.

**Caveat — Universal Links same-domain rule.** Apple's `NSUserActivity` Universal Link does NOT fire when navigating WITHIN `clique-pix.com` in Safari. Don't add an "Open in App" hyperlink on the invite page that points at the same URL — it silently does nothing. The Smart App Banner is the only viable in-page mechanism; OR direct the user to re-tap the original invite link from another app (Messages, Mail, etc.) where the navigation IS cross-domain.

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

> **Prerequisite — Android App Links must auto-verify on the running build.** The whole installed-app path (Play Install Referrer auto-join here, and the Universal/App Link retap routing) only fires if Android verifies the `clique-pix.com/invite` App Link for the running APK/AAB. That verification reads `https://clique-pix.com/.well-known/assetlinks.json`, which MUST list the SHA-256 fingerprint of the key that signed the running build. Because production AABs are re-signed by **Play App Signing** (not the upload key), `assetlinks.json` carries **both** fingerprints — the upload/debug key (`BD:B3:DE:...`) and the Play App Signing key (`4F:6E:1A:...`) — in both copies (`infrastructure/well-known/assetlinks.json` and `webapp/public/.well-known/assetlinks.json`). If the Play App Signing fingerprint is missing (it was, until the 2026-06-04 H4 fix), `clique-pix.com/invite` links open in the browser on production builds instead of routing into the app, silently defeating both the auto-join and the retap flows. The matching `<intent-filter android:autoVerify="true">` lives in `app/android/app/src/main/AndroidManifest.xml`. Baseline App Links / assetlinks setup is owned by `docs/AUTHENTICATION.md` / `docs/ARCHITECTURE.md`; this doc only depends on it being correct.

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
