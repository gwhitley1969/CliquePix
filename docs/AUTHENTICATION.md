# Authentication — Clique Pix

**Last Updated:** 2026-05-06
**Status:** Email + password is the primary local sign-in method (migrated from email OTP on 2026-05-06 to satisfy Apple App Store reviewer credential requirements). Google + Apple federation unchanged. Existing pre-2026-05-06 OTP users preserved per Microsoft documented behavior.

---

## What this document covers

This is the orientation document for Clique Pix authentication. It answers:

- What sign-in options does a user see?
- Which Azure / Microsoft services power auth?
- What happens end-to-end from "Get Started" tap to "lands on Events"?
- Where does the JWT come from, what claims does it carry, and how does the backend validate it?
- How does the app stay signed in across days/weeks despite the CIAM 12-hour bug?
- What credentials does Apple App Review use?
- Where do I look for code, configuration, and operational troubleshooting?

For depth on specific subsystems, this doc points to the specialized companion docs rather than duplicating them. See "Companion documents" at the bottom.

---

## At a glance

| Aspect | Value |
|---|---|
| Identity provider (consumer) | Microsoft Entra External ID (CIAM tenant `cliquepix.onmicrosoft.com`, tenant ID `27748e01-d49f-4f0b-b78f-b97c16be69dc`) |
| App registration | Clique Pix, client ID `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Authority | `https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/` |
| Custom API scope | `api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user` |
| User flow | `SignUpSignIn` |
| Local-account method | **Email + password** (since 2026-05-06; was Email OTP previously) |
| Federated providers | Google, Apple |
| Minimum age | 13 (enforced via `dateOfBirth` claim, backend-validated) |
| Mobile MSAL library | `msal_auth ^3.3.0` (Flutter) |
| Web MSAL library | `@azure/msal-browser` + `@azure/msal-react` (React SPA, PKCE) |
| Token storage (mobile) | `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences on Android) |
| Token storage (web) | `sessionStorage` (per-tab, survives reload) |
| Session lifetime quirk | Entra External ID enforces hardcoded 12-hour refresh-token inactivity timeout — defended via 5-layer system (see ENTRA_REFRESH_TOKEN_WORKAROUND.md) |

---

## What users see

### First-time user

1. Open app → first frame is **LoginScreen** with "Get Started" button enabled (no spinner, no splash).
2. Tap **Get Started** → browser opens (iOS: ASWebAuthenticationSession; Android: Chrome Custom Tabs; Web: full-page redirect).
3. Entra-hosted page renders three options:
   - Email field + password field + "Sign up" link
   - "Sign in with Google" button
   - "Sign in with Apple" button
4. User chooses path. For email+password sign-up: types email → sets password → confirms password → fills date-of-birth attribute (required) → submits.
5. Backend validates the access token, runs the age gate (13+). If pass: user upserted, lands on **Events** screen. If fail (under 13): red banner, Entra account best-effort deleted via Microsoft Graph.

### Returning user (cached session)

1. Open app → first frame is **Events** (optimistic-auth bootstrap reads cached token + cached `UserModel` from secure storage before `runApp`).
2. Background `_verifyInBackground` fires `silentSignIn` (8s timeout); on success, cached user is replaced with the authoritative server record. Invisible to user.

### Returning user (session expired past 12h)

1. Open app → ~2s flash of Events shell → **WelcomeBackDialog** appears with email pre-filled.
2. Tap → MSAL re-launches browser with `loginHint=email`; Entra page prefills email and asks for password (or shows Google/Apple buttons depending on the original sign-in method).
3. One-tap re-auth lands user back on Events.

### Returning user (signed out, OR force-killed iOS app past 12h)

1. Open app → first frame is LoginScreen with "Get Started" button enabled.
2. Identical to first-time user from here.

---

## Authentication providers

### Email + password (primary, since 2026-05-06)

The default local-account method. Users:
- Sign up with email → set password (Entra enforces complexity) → fill DOB attribute → land in app.
- Sign in with email + password.
- Recover via "Forgot password?" link on the hosted page (uses email-OTP as the SSPR verification factor — separate from the local-account method).

**Why this method (vs. email-OTP):** Apple App Store Review requires static credentials reviewers can hand-type. OTP codes are sent to the user's email, which a reviewer can't access. Password works for App Review and is more familiar to general users. See migration history below.

### Google federation

Users tap "Sign in with Google" on the Entra-hosted page → Google OAuth consent → Entra brokers the auth → app receives an Entra access token (NOT a Google token). User identity is keyed on the JWT `sub` claim, stable across the Google account.

Configured in Google Cloud Console as a Web Application OAuth client; authorized domains: `ciamlogin.com`, `microsoftonline.com`, `clique-pix.com`.

### Apple federation (Sign in with Apple)

Users tap "Sign in with Apple" → Apple authorization → Entra brokers via the Sign in with Apple Services ID `com.cliquepix.app.service` (Team ID `4ML27KY869`, Key ID `4NYXZNV9VD`). The `.p8` client secret renews **September 2026** (calendar reminder required).

Required by Apple Guideline 4.8 since the app offers other social sign-in options.

### Legacy email-OTP users (preserved)

Per Microsoft's documented behavior: changing a user flow's local-account method only affects new users. Existing accounts created under the OTP flow continue to sign in with OTP indefinitely; they do not have a password and don't need one. These accounts can be migrated to password later via SSPR if desired (out of scope for v1).

---

## End-to-end flow

### Interactive sign-in (mobile)

```
LoginScreen "Get Started" tap
  → AuthNotifier.signIn()
  → AuthRepository.signIn()
  → SingleAccountPca.acquireToken(scopes, prompt: Prompt.login)
     ├─ iOS:    ASWebAuthenticationSession (ephemeral, via Broker.msAuthenticator)
     └─ Android: Chrome Custom Tabs (browser_sign_out_enabled: true)
  → Entra-hosted page (cliquepix.ciamlogin.com)
     ├─ Email + password OR Google OR Apple
     └─ DOB attribute on signup
  → MSAL receives access_token (audience = client ID, signed by CIAM keys)
  → AuthRepository.verifyAndGetUser(token, 10s timeout)
  → POST https://api.clique-pix.com/api/auth/verify
     → APIM (apim-cliquepix-003) → Function authVerify
     → JWT validation (issuer, audience, signature via JWKS)
     → decideAgeGate(dateOfBirth claim)
        ├─ ≥13: upsert user with age_verified_at = NOW(), age_gate_passed
        └─ <13: HTTP 403 AGE_VERIFICATION_FAILED + Microsoft Graph user delete
  → Returns enriched UserModel
  → TokenStorageService.saveTokens(token, lastRefreshTime = NOW())
  → AuthNotifier.state = AuthAuthenticated(user)
  → GoRouter redirects to /events
```

### Cold start (returning user with cached session)

```
main()
  → Firebase.initializeApp() (BEFORE runApp)
  → FirebaseMessaging.onBackgroundMessage(...)  (BEFORE runApp)
  → TokenStorageService.getAccessToken() + getCachedUser()
     ├─ Both present: bootstrapState = AuthAuthenticated(cachedUser)
     └─ Either missing: bootstrapState = AuthUnauthenticated
  → Hydrate ListCacheService (events + cliques) with 250ms timeout
  → runApp(ProviderScope with seeded providers)
  → First frame: Events (or LoginScreen) — NO SPLASH
  → AuthNotifier._verifyInBackground (8s timeout)
     ├─ Success: replace cached UserModel with server record
     ├─ Session-expired (AADSTS700082 / AADSTS500210 / no_account_found):
     │  emit AuthReloginRequired → router → WelcomeBackDialog
     └─ Network hiccup: keep optimistic AuthAuthenticated; retry on resume / 401
```

### Session refresh — the 5-layer defense

Entra External ID has a documented 12-hour inactivity timeout on refresh tokens. Five overlapping mechanisms keep users signed in:

| Layer | Mechanism | Trigger | Platform |
|---|---|---|---|
| 1 | Battery-optimization exemption | First home-screen frame after login | Android |
| 2 | Server-triggered silent FCM push | Backend timer every 15 min, users inactive 9–11h | both |
| 3 | Foreground refresh on app resume | `AppLifecycleState.resumed` if token ≥ 6h stale | both |
| 4 | WorkManager periodic task | Every ~8h, network-connected (4h floor) | Android |
| 5 | Graceful re-login via WelcomeBackDialog | All silent paths failed | both |

Full details, telemetry, and Kusto queries: **`docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`**.

### Web — no 5-layer defense needed

MSAL.js uses hidden iframes for silent token renewal. The 12-hour CIAM bug does NOT manifest because MSAL.js refreshes proactively on every token use. Web is simpler:

```
LandingPage / LoginScreen "Get Started" tap
  → useMsal().instance.loginRedirect(loginRequest)
  → Full-page redirect to cliquepix.ciamlogin.com
  → Entra-hosted page (same as mobile)
  → Redirects back to /auth/callback
  → MSAL handles the redirect, stores tokens in sessionStorage
  → useAuthVerify hook → POST /api/auth/verify (once per session)
  → Lands on /events
```

The `setApiMsalInstance(msalInstance)` call in `webapp/src/main.tsx` MUST happen AFTER `await msalInstance.initialize()` and BEFORE `ReactDOM.createRoot(...).render(...)` — see `WEB_CLIENT_ARCHITECTURE.md §4.1`. A previous regression built a fallback PCA on the fly that was never initialized, silently dropped the `Authorization` header, and presented empty-state UI as if the user had no data. `getPca()` now throws a loud dev error if the wiring is skipped.

---

## Platform specifics

### iOS — `Broker.msAuthenticator` + ASWebAuthenticationSession (load-bearing)

All three PCA-creation sites (`auth_repository.dart:55-59`, `main.dart:81`, `background_token_service.dart:68`) use `Broker.msAuthenticator` (NOT `Broker.safariBrowser`).

**Why:** `msal_auth` 3.3.0 unconditionally sets `prefersEphemeralWebBrowserSession = true` on iOS 13+, but the flag is only honored when `webviewType` falls into the `default:` case (ASWebAuthenticationSession). `Broker.safariBrowser` overrides to `safariViewController`, which has a per-app **persistent** cookie jar that ignores the ephemeral flag. Result with `safariBrowser`: signing out user A and trying to sign in as user B traps on CIAM's "Continue as A" prompt because the session cookie at `cliquepix.ciamlogin.com` survives `pca.signOut()`.

`Broker.msAuthenticator` falls through to ASWebAuthenticationSession ephemeral; cookies are destroyed at session end. For B2C/CIAM tenants MSAL never brokers via the Authenticator app (B2C is unsupported), so the enum name is misleading — the actual behavior is "use ASWebAuthenticationSession with ephemeral session."

**Fixed 2026-05-04.** Do NOT revert without re-introducing the account-switching bug.

### iOS — required Info.plist entries

- `CFBundleURLSchemes` includes `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` (auto-resolves to `msauth.com.cliquepix.app`)
- `LSApplicationQueriesSchemes` includes `msauthv2`, `msauthv3` (required for the `brokerAvailability=.auto` path that comes with `Broker.msAuthenticator`)
- `Runner.entitlements` keychain group: `$(AppIdentifierPrefix)com.microsoft.adalcache` (required for MSAL token caching + sign-out)
- `AppDelegate.swift` calls `MSALPublicClientApplication.handleMSALResponse()` in `application(_:open:options:)`

**Do NOT declare `BGTaskSchedulerPermittedIdentifiers`** unless you also register a launch handler via `BGTaskScheduler.shared.register(...)` in `AppDelegate.swift`. iOS 13+ raises `NSInternalInconsistencyException` (SIGABRT) the moment it inspects scheduling state for an unregistered identifier. This caused the "app vanishes after MSAL/Safari sign-in" bug fixed 2026-05-01.

### iOS — cloud playback note (unrelated to auth, but easy to confuse)

`VideoPlayerController` bypasses Dio's `AuthInterceptor`, so video URLs use User Delegation SAS tokens (15-min expiry) embedded in the URL — not Bearer tokens. iOS goes straight to MP4 (skipping HLS) because of an AVPlayer hang on `Uri.file()` HLS manifests with absolute SAS segment URLs. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 15.

### Android — `browser_sign_out_enabled: true`

`app/assets/msal_config.json` sets `"authorization_user_agent": "BROWSER"` and `"browser_sign_out_enabled": true`. On `signOut`, Android MSAL navigates to the OIDC `oauth2/v2.0/logout` endpoint inside Chrome Custom Tabs to clear the cookie server-side. Without this, signing out + signing back in could re-authenticate via the residual session cookie.

iOS doesn't read `msal_config.json` at all — `browser_sign_out_enabled` is dead config on iOS, and the iOS-equivalent is the ASWebAuthenticationSession ephemeral session (see above).

### Android — required permissions

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Battery-optimization exemption (Layer 1 of the 5-layer defense) is requested at runtime via `Permission.ignoreBatteryOptimizations.request()` — manifest declaration alone is not sufficient on API 23+.

### Web — sessionStorage cache

`@azure/msal-browser` is configured to use **`sessionStorage`** (per-tab, survives reload, clears on tab close). Safer than `localStorage` against XSS. Trade-off: tab-close = sign-out. If beta feedback says this is painful, switch to `localStorage` and accept the XSS risk.

---

## Backend

### JWT validation (`backend/src/shared/middleware/authMiddleware.ts`)

Every authenticated endpoint runs through this middleware. The validation rules:

| Field | Expected value |
|---|---|
| Issuer | `https://27748e01-d49f-4f0b-b78f-b97c16be69dc.ciamlogin.com/27748e01-d49f-4f0b-b78f-b97c16be69dc/v2.0` (tenant **ID** as subdomain — CIAM quirk, NOT tenant name) |
| Audience | `7db01206-135b-4a34-a4d5-2622d1a888bf` (app client ID) |
| Signature | Verified via JWKS at `https://cliquepix.ciamlogin.com/{tenantId}/discovery/v2.0/keys` (tenant **NAME** as subdomain — different CIAM quirk) |

**Do NOT confuse the issuer URL with the JWKS URL** — they use different subdomain conventions. Both correct.

The middleware also fires-and-forgets a `last_activity_at` update on the user row (capped 1/min/user) — this feeds the Layer-2 silent-push timer.

### Age gate (claim-based)

The `dateOfBirth` claim rides on every access token (configured in the app reg as `extension_<b2cAppId>_dateOfBirth` from the Directory schema extension). On first login, `authVerify`:

1. Reads the claim via `extractDobFromClaims` (handles GUID-prefixed key form via case-insensitive substring match)
2. Computes age via `ageUtils.calculateAge`
3. Branches:
   - **≥13:** `INSERT ... ON CONFLICT (external_auth_id) DO UPDATE SET age_verified_at = COALESCE(users.age_verified_at, NOW())`. The `COALESCE` preserves the original timestamp on returning logins.
   - **<13:** Returns HTTP 403 `AGE_VERIFICATION_FAILED`, fires `age_gate_denied_under_13` telemetry, calls `deleteEntraUserByOid(oid)` via Microsoft Graph (best-effort; failure logged as `age_gate_entra_delete_failed` but does not block the 403).

Returning users are never re-prompted — the COALESCE preserves `age_verified_at` and Entra holds the DOB on the user principal.

**Privacy posture:** Clique Pix's `users` table stores only `age_verified_at` (a timestamp), never DOB. Entra stores DOB on the user principal.

Full details: **`docs/AGE_VERIFICATION_RUNBOOK.md`**.

### User upsert

After age-gate pass, `authVerify` upserts the user row keyed on the JWT `sub` claim (fallback `oid`). `email_or_phone`, `display_name`, and `external_auth_id` are sourced from the token claims. The response wraps the user via `buildAuthUserResponse` from `backend/src/shared/services/avatarEnricher.ts` — single source of truth for the canonical auth response shape.

### Telemetry

Successful sign-ins fire `auth_verify_success`. Age-gate decisions fire `age_gate_passed { ageBucket }` (coarse bucket, never raw DOB) or `age_gate_denied_under_13`. Authentication failures during silent refresh fire layer-specific events: `silent_push_refresh_success/_failed`, `foreground_refresh_success/_failed`, `wm_refresh_success/_failed`, `welcome_back_shown { source: 'interceptor' | 'lifecycle', reason: <AADSTS code> }`, `cold_start_relogin_required`.

Useful Kusto queries: see `BETA_OPERATIONS_RUNBOOK.md` §2 ("User reports unexpected re-login").

---

## Apple App Store demo account

### Why dedicated

Apple App Review Guideline 2.1 requires working credentials reviewers can hand-type. The dedicated `appreview@cliquepix.com` account:

- Decouples reviewer access from any real user account (revocable post-review without disrupting anyone)
- Stays usable across resubmissions (Apple reuses the same credentials)
- Pre-seeded with content so the reviewer sees the app working immediately, not an empty Events screen

### Account specifics

| Attribute | Value |
|---|---|
| Username (email) | `appreview@cliquepix.com` |
| Password | Strong random 16+ chars (mixed case + digits + symbols) |
| Password storage | Azure Key Vault `kv-cliquepix-prod/apple-review-credentials` |
| DOB | 1985-01-01 (clearly past age gate) |
| Membership | Member of "Apple Review Demo" Clique with one helper account (Gene's primary) |
| Pre-seeded content | One 7-day Event with 4–6 sample photos + 1 short video (≤30 sec) uploaded by helper |

### Re-seed cadence

Events expire after 7 days. **Re-seed within 48 hours of every App Store submission.** The seed user (`appreview`) and helper (Gene's primary) accounts are NEVER deleted — only the Event content is recreated. `events.created_by_user_id` is `ON DELETE SET NULL` (migration 004), so account deletion wouldn't cascade-remove the demo content, but the simpler operational rule is "never delete the seed accounts."

### App Store Connect → App Review Information

| Field | Value |
|---|---|
| Sign-in required | Yes |
| Username | `appreview@cliquepix.com` |
| Password | (from Key Vault) |
| Notes | Short paragraphs explaining (a) the pre-seeded Clique with sample content, (b) age gate (DOB ≥ 13), (c) Google + Apple federation also available but reviewer should use supplied credentials, (d) where Privacy Policy is linked from inside the app |
| Contact | `genewhitley2017@gmail.com` + phone |

---

## Configuration reference

### Azure resources

- **Resource group:** `rg-cliquepix-prod` (eastus)
- **CIAM tenant:** `cliquepix.onmicrosoft.com` (ID `27748e01-d49f-4f0b-b78f-b97c16be69dc`)
- **App registration:** Clique Pix (client ID `7db01206-135b-4a34-a4d5-2622d1a888bf`)
- **API Management:** `apim-cliquepix-003` (Basic v2, $150/month, 99.95% SLA — migrated from Developer-tier `apim-cliquepix-002` on 2026-05-05)
- **Function App:** `func-cliquepix-fresh` (validates JWTs)
- **Front Door:** `fd-cliquepix-prod`
- **Custom domain:** `api.clique-pix.com` (Front Door → APIM → Function App)
- **Web origin:** `clique-pix.com` (Static Web App; CORS-allowlisted at APIM)
- **Web PubSub:** `wps-cliquepix-prod` (real-time DM + `video_ready` + `new_event`)

### MSAL scopes (mobile + web)

```
['api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user']
```

**Custom API scope only.** OIDC scopes (`openid`, `profile`, `email`) are added implicitly by MSAL. Mixing custom + OIDC scopes causes `MsalDeclinedScopeException`. `offline_access` must NOT be requested explicitly — CIAM declines it without admin consent; MSAL handles refresh tokens internally.

### Without a custom API scope, auth WOULD silently fail

If the MSAL config requested only OIDC scopes (no custom API scope), `result.accessToken` would be a Microsoft Graph token signed by Graph keys — not the CIAM tenant's keys. Backend JWT verification would fail with `invalid signature`. This was bug #1 in the 2026-03-26 auth fix; documented here so future maintainers don't strip the custom scope.

### Redirect URIs (configured in Entra app registration)

| Platform | URI |
|---|---|
| Android (debug) | `msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D` |
| iOS | `msauth.com.cliquepix.app://auth` (auto-generated by Entra from bundle ID) |
| Web (prod) | `https://clique-pix.com/auth/callback` |
| Web (dev) | `http://localhost:5173/auth/callback` |

### File locations

**Mobile (Flutter):**

| What | Where |
|---|---|
| MSAL constants (authority, client ID, scopes) | `app/lib/core/constants/msal_constants.dart` |
| MSAL JSON config (Android-only) | `app/assets/msal_config.json` |
| Auth repository (signIn, silentSignIn, refreshToken) | `app/lib/features/auth/domain/auth_repository.dart` |
| Auth state machine | `app/lib/features/auth/presentation/auth_providers.dart` (the catch block at lines 174-200 is the canonical sign-in error router) |
| Login screen | `app/lib/features/auth/presentation/login_screen.dart` |
| Welcome Back dialog | `app/lib/features/auth/presentation/welcome_back_dialog.dart` |
| 5-layer refresh services | `app/lib/features/auth/domain/{app_lifecycle_service,background_token_service,battery_optimization_service}.dart` |
| Token storage | `app/lib/services/token_storage_service.dart` |
| Auth interceptor (401 → silent refresh → WelcomeBack) | `app/lib/services/auth_interceptor.dart` |
| iOS Info.plist | `app/ios/Runner/Info.plist` |
| iOS entitlements | `app/ios/Runner/Runner.entitlements` |
| iOS AppDelegate URL handler | `app/ios/Runner/AppDelegate.swift` |
| Android manifest | `app/android/app/src/main/AndroidManifest.xml` |

**Web (React):**

| What | Where |
|---|---|
| MSAL config | `webapp/src/auth/msalConfig.ts` |
| MSAL singleton wiring (load-bearing) | `webapp/src/main.tsx` (MUST call `setApiMsalInstance` after `await initialize()`) |
| Auth callback | `webapp/src/features/auth/AuthCallback.tsx` |
| `useAuthVerify` hook | `webapp/src/features/auth/useAuthVerify.ts` |
| AuthGuard | `webapp/src/auth/AuthGuard.tsx` |
| Env config | `webapp/.env.{development,production,example}` |

**Backend:**

| What | Where |
|---|---|
| Auth middleware (JWT validation + last-activity update) | `backend/src/shared/middleware/authMiddleware.ts` |
| `authVerify` endpoint + age gate | `backend/src/functions/auth.ts` |
| Age-gate utils | `backend/src/shared/utils/ageUtils.ts` |
| Microsoft Graph client (under-13 cleanup) | `backend/src/shared/auth/entraGraphClient.ts` |
| User table avatar enricher (canonical response shape) | `backend/src/shared/services/avatarEnricher.ts` |
| Migration: `users.age_verified_at` | `backend/src/shared/db/migrations/008_user_age_verification.sql` |
| Migration: `users.last_activity_at` + `last_refresh_push_sent_at` | `backend/src/shared/db/migrations/009_user_activity_tracking.sql` |

---

## Sign out

### Mobile

```
ProfileScreen "Sign Out" tap
  → confirmDestructive() dialog
  → AuthNotifier.signOut()
  → AuthRepository.signOut()
     ├─ pca.signOut() (clears MSAL keychain at com.microsoft.adalcache)
     ├─ TokenStorageService.clearAll()
     ├─ ListCacheService.clearAll() (events + cliques cache)
     ├─ Background services stopped: AppLifecycleService.stop, WorkManager cancelled, DmRealtimeService.disconnect
     ├─ FridayReminderService.cancel()
     └─ _pca = null (forces fresh PCA on next sign-in — prevents stale cached state regression)
  → AuthNotifier.state = AuthUnauthenticated
  → GoRouter redirects to /login
```

### Web

```
ProfileScreen "Sign out" tap
  → msalInstance.logoutRedirect()
  → MSAL clears sessionStorage cache + redirects to OIDC logout endpoint
  → Browser returns to /
  → Top-right CTA swaps from "My Events →" back to "Sign in"
```

### Critical iOS post-2026-05-04 behavior

After signOut, the next sign-in MUST get a clean session — see the `Broker.msAuthenticator` rationale above. If you're testing account-switching and seeing CIAM's "Continue as <previous user>" prompt, the broker config has been reverted.

---

## Account deletion

```
ProfileScreen "Delete Account" → confirmDestructive() → AuthNotifier.deleteAccount()
  → DELETE /api/users/me
     → Function deleteMe:
        ├─ Delete user's avatar blobs (avatars/{userId}/original.jpg + thumb.jpg)
        ├─ Delete user's photo + video blobs from blob storage
        ├─ For sole-owner cliques: delete clique blobs + cascade DB row
        ├─ For shared cliques/events: ON DELETE SET NULL preserves them for other members
        └─ DELETE FROM users WHERE id = $1 (CASCADE removes clique_members, push_tokens, notifications)
  → AuthNotifier.signOut() (local cleanup as above)
  → Redirect to /login
```

The Entra account is NOT deleted — only the Clique Pix application data is purged. Users who want to fully delete the Entra account too must contact support OR use the Microsoft account recovery flow (this is a v1.5 enhancement to wire `deleteEntraUserByOid` from `entraGraphClient.ts` into the user-initiated path).

---

## Troubleshooting

For incident-response procedures, see `BETA_OPERATIONS_RUNBOOK.md` §2:

- **User reports unexpected re-login** — 5-layer defense health Kusto queries, per-user debugging via Token Diagnostics
- **User reports raw `DioException` on the home screen** — coordination between `AuthInterceptor` + `AuthNotifier` + `home_screen.dart` for clean session-expired UX
- **iOS user reports "app vanishes after sign-in"** — `BGTaskSchedulerPermittedIdentifiers` SIGABRT trap
- **iPhone account-switch trapped on "Continue as previous user"** — `Broker.msAuthenticator` config check
- **User reports stuck "Get Started" spinner** — cold-start health, escape-hatch detection
- **Photos/videos not loading — SAS errors** — managed identity RBAC, User Delegation SAS expiry
- **Web users report empty data** — MSAL singleton wiring (PR #4 regression), envelope unwrap (PR #5 regression)

For developer-side diagnostics: tap the version number 7× on the Profile screen to unlock **Token Diagnostics** — shows current token age, pending-refresh flag, battery-exempt status, and a 50-event ring buffer of telemetry events.

---

## Migration history

### 2026-05-06: Email OTP → Email + password

**Trigger:** Apple App Store Review requires static credentials a reviewer can hand-type. OTP codes are sent to the user's email and can't be intercepted by Apple's reviewer.

**Change:** Switched the `SignUpSignIn` user flow's local-account identity provider from "Email one-time passcode" to "Email with password" via the Entra admin center. Single property change; Google + Apple federation unchanged.

**Migration impact:** Per Microsoft documented behavior, the change affects only NEW users. Existing OTP users continue to sign in with OTP indefinitely. No forced password reset, no migration script.

**Doc surface area:** 11 doc edits across `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DEPLOYMENT_STATUS.md`, `docs/BETA_TEST_PLAN.md`, `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`, `.claude/CLAUDE.md`, `webapp/public/docs/privacy.html`, plus this new doc.

**Plan reference:** `C:\Users\genew\.claude\plans\velvety-kindling-dragon.md`.

### 2026-05-04: iOS broker config

`Broker.safariBrowser` → `Broker.msAuthenticator` at all 3 PCA-creation sites. Fixed account-switching trap on iOS (CIAM "Continue as previous user" prompt that survived `pca.signOut()`). See `DEPLOYMENT_STATUS.md` "iOS account-switching trapped in previous user's CIAM session."

### 2026-05-01: BGTask SIGABRT fix

Removed `BGTaskSchedulerPermittedIdentifiers` from `app/ios/Runner/Info.plist`. Layer 4 of the 5-layer refresh defense is Android-only (WorkManager); the iOS plist entry without a registered launch handler caused SIGABRT when FlutterViewController re-attached after Safari dismissed. See `DEPLOYMENT_STATUS.md` "BGTask SIGABRT iOS post-auth crash."

### 2026-05-03: Raw DioException leak fix

`home_screen.dart` switched to `friendlyApiErrorMessage(err, resourceLabel:)` instead of `error.toString()`. `AuthInterceptor` now signals `AuthNotifier.triggerWelcomeBackOnSessionExpiry()` on session-expired refresh failure so the UI transitions to WelcomeBackDialog before the AsyncError reaches the screen. See `DEPLOYMENT_STATUS.md` "Raw DioException leak on session-expired 401."

### 2026-04-19: 5-layer defense rewrite (silent push edition)

Replaced the broken `flutter_local_notifications.zonedSchedule` Layer 2 (which only displays notifications, doesn't execute code) with server-triggered silent FCM pushes. Wired up all five services (previously many were dead code with optional constructor params never supplied). See `ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

### 2026-04-18: Age gate (claim-based)

Pivoted from a Custom Authentication Extension (unsupported in External ID per Microsoft's own migration docs) to claim-based backend validation. `dateOfBirth` collected once by the user flow, emitted on every access token, validated by `authVerify`. Privacy posture: Postgres stores only `age_verified_at` timestamp, never DOB. See `AGE_VERIFICATION_RUNBOOK.md`.

### 2026-03-26: Custom API scope

Added the `api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user` scope. Without it, MSAL returned a Microsoft Graph token signed by Graph keys (not CIAM keys) and backend JWT validation failed with `invalid signature`.

---

## Companion documents

| Document | What it covers |
|---|---|
| `ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Full 5-layer refresh defense — code samples, telemetry, Kusto queries, per-layer behavior, iOS / Android limitations |
| `AGE_VERIFICATION_RUNBOOK.md` | 13+ age gate — claim emission, backend validation, deprecated CAE attempt, troubleshooting |
| `WEB_CLIENT_ARCHITECTURE.md` | Web client auth (MSAL.js singleton wiring, sessionStorage cache, no 5-layer needed) |
| `BETA_OPERATIONS_RUNBOOK.md` | Auth incident response (10+ documented scenarios with diagnostic Kusto queries and fix paths) |
| `BETA_TEST_PLAN.md` §1 | Manual auth smoke-test checklist (cold start, OTP regression, password sign-up, federation, SSPR, reviewer account, edge cases) |
| `ARCHITECTURE.md` §5 | High-level auth section in the broader architecture doc |
| `DEPLOYMENT_STATUS.md` | Reverse-chronological deployment log including all auth-related incidents and migrations |
| `CLAUDE.md` "Entra External ID — Known Bug & Required Workaround" | Development guardrails for the 12-hour timeout and 5-layer defense |
