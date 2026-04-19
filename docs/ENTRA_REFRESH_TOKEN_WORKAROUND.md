# Microsoft Entra External ID Refresh Token Workaround — Clique Pix

**Last updated:** 2026-04-19
**Status:** 5-layer defense, silent-push edition. Shipping in migration 009 + client/backend changes.
**Issue type:** Known Microsoft bug — no portal-based fix.

---

## Problem summary

Clique Pix uses Microsoft Entra External ID (CIAM) with Google / Apple / email-OTP sign-in. Entra External ID tenants enforce a **hardcoded 12-hour inactivity timeout** on refresh tokens. Standard Entra ID tenants get 90 days; External ID does not, and the setting is not exposed anywhere.

Symptom: after ~12 hours without opening the app, the next silent refresh fails with:

```
AADSTS700082: The refresh token has expired due to inactivity.
The token was issued on 2026-04-18T21:19:36Z and was inactive for 12:00:00.
```

Microsoft Q&A (April 2026) confirms the timeout cannot be raised. Their documented workaround — in the Azure Communication Services chat tutorial, "Implement registration renewal → Solution 2: Remote Notification" — is **silent push + background refresh**. That is what we implement.

Two additional moving parts the design accounts for:

- **MSAL iOS #2871** — federated users (Google / Apple — i.e., all Clique Pix users) hit `AADSTS500210` on `acquireTokenSilent` because MSAL targets the wrong authority URL. We detect this error code and route to Layer 5 rather than attempt an MSAL patch.
- **iOS silent push is opportunistic.** Apple throttles background pushes and will not wake a user-force-killed app or an app with Background App Refresh disabled. For those users, Layer 5 Welcome Back is the only recourse — documented, not hidden.

---

## History — what was here before, and why it didn't work

The codebase previously contained all five service classes (`AlarmRefreshService`, `AppLifecycleService`, `BatteryOptimizationService`, `BackgroundTokenService`, `WelcomeBackDialog`) — but:

- `AuthRepository` declared `alarmRefreshService` and `backgroundTokenService` as **optional** constructor parameters, and `authRepositoryProvider` never supplied them. Every `?.` callsite was a silent no-op.
- `AppLifecycleService.start()` was never called — the observer never registered.
- `BatteryOptimizationService` was never instantiated.
- `WelcomeBackDialog.show()` had no caller anywhere in the codebase.
- `BackgroundTokenService.callbackDispatcher` had a `TODO` where the MSAL call should be. The WorkManager callback always returned `true`, reporting "success" without doing anything.
- `main.dart` filtered the `TOKEN_REFRESH_TRIGGER` notification payload but nothing triggered a refresh in response.

On top of that, the original Layer 2 design was architecturally flawed: `flutter_local_notifications.zonedSchedule` with `exactAllowWhileIdle` **only schedules a notification to display** at a time — it does not execute code. `onDidReceiveNotificationResponse` fires only on user tap. A silent `Importance.min` notification the user never saw was never tapped, so no code ever ran. The primitive was the wrong tool.

The current architecture deletes the notification-based Layer 2 entirely and replaces it with a server-triggered silent push.

---

## The 5 layers (as-shipped)

| Layer | Mechanism | Trigger | Platforms | Purpose |
|-------|-----------|---------|-----------|---------|
| 1 | Battery-optimization exemption | First home-screen frame after login (Android only) | Android | Allows Layer 4 (WorkManager) + OS processes that deliver FCM to run reliably on Samsung/Xiaomi/Huawei |
| 2 | **Server-triggered silent FCM push** | Backend timer every 15 min, targeting users inactive 9–11h | both | Wakes the app in the background; app runs `acquireTokenSilent` in an isolate. If in-isolate MSAL fails (iOS plugin-channel limits), a fallback flag triggers a Layer-3 refresh on next resume |
| 3 | Foreground refresh on app resume | Every `AppLifecycleState.resumed` if token age ≥ 6h or pending flag set | both | Primary, most-reliable defense. Catches anyone who opens the app |
| 4 | WorkManager periodic task | Every ~8h with network constraint | Android | Best-effort backup. Less reliable than Layer 2 (silent push) and Layer 3 (foreground) but adds another wake opportunity |
| 5 | Graceful re-login via Welcome Back | When silent refresh fails with AADSTS700082 / AADSTS500210 / no cached account | both | One-tap re-auth with `loginHint` pre-fill. Shown by `LoginScreen` when `AuthState` is `AuthReloginRequired` |

Key timing:
- Microsoft inactivity timeout: **12 hours** (hardcoded)
- Token "stale" threshold (Layer 3): **6 hours** — `AppConstants.tokenStaleThresholdHours`
- WorkManager interval (Layer 4): **8 hours** — `AppConstants.workManagerIntervalHours`
- Silent push window (Layer 2): user inactive between **9 and 11 hours** (2h window before the 12h cliff)
- Silent push dedup: max 1 push per user per **6 hours** (`users.last_refresh_push_sent_at`)

---

## Architecture

### Client

```
app/lib/
  core/constants/
    msal_constants.dart                  (new) — single source of MSAL config
    app_constants.dart                   — tokenStaleThresholdHours + workManagerIntervalHours
  features/auth/
    domain/
      auth_repository.dart               — refreshToken + refreshTokenDetailed(errorCode)
      auth_state.dart                    — AuthReloginRequired (new variant)
      app_lifecycle_service.dart         — Layer 3 observer + pending-flag consumer
      background_token_service.dart      — Layer 4 WorkManager isolate, full MSAL refresh
      battery_optimization_service.dart  — Layer 1 dialog + runtime permission request
    presentation/
      auth_providers.dart                — the wiring layer; instantiates every service
      login_screen.dart                  — ref.listen → WelcomeBackDialog on AuthReloginRequired
      welcome_back_dialog.dart           — Layer 5 UX
  services/
    telemetry_service.dart               (new) — Dio POST /api/telemetry/auth + SharedPreferences ring buffer
    push_notification_service.dart       — foreground onMessage handles type: 'token_refresh'
    token_storage_service.dart           — lastRefreshTime, isTokenStale, lastKnownUser
  main.dart                              — _firebaseMessagingBackgroundHandler runs Layer-2 silent refresh
  features/profile/presentation/
    profile_screen.dart                  — tap-7-times unlock on version text
    token_diagnostics_screen.dart        (new) — telemetry buffer viewer
```

### Backend

```
backend/src/
  shared/db/migrations/
    009_user_activity_tracking.sql       (new) — last_activity_at + last_refresh_push_sent_at
  shared/middleware/
    authMiddleware.ts                    — fire-and-forget last_activity_at update + verifyJwtAllowExpired
  shared/services/
    fcmService.ts                        — FcmMessage.silent, sendSilentToMultipleTokens, buildFcmMessageBody
  functions/
    timers.ts                            — refreshTokenPushTimer (CRON 7,22,37,52 */h)
    telemetry.ts                         (new) — POST /api/telemetry/auth
```

### Request flow (Layer 2 — the new part)

1. Any authenticated API call hits `authMiddleware.authenticateRequest`; that handler validates the JWT and fires a `UPDATE users SET last_activity_at = NOW() WHERE id = $1 AND (last_activity_at IS NULL OR last_activity_at < NOW() - INTERVAL '1 minute')` — capped at one write per minute per user, fire-and-forget (no await).
2. `refreshTokenPushTimer` runs at :07, :22, :37, :52 every hour. It selects `(user_id, token, platform)` tuples where `last_activity_at BETWEEN NOW() - INTERVAL '11 hours' AND NOW() - INTERVAL '9 hours'` and the user hasn't been pushed in 6h. Per user, it sends a silent FCM push with `data: { type: 'token_refresh', userId }`, no `notification` block.
3. `sendSilentToMultipleTokens` builds the FCM v1 body via `buildFcmMessageBody({silent: true})`, which sets `apns-push-type: background`, `apns-priority: 5`, `apns-topic: com.cliquepix.app`, `apns.payload.aps.content-available: 1`, and `android.priority: high`.
4. iOS wakes the app via APNs background push; Android wakes via high-priority data message. Both land in `_firebaseMessagingBackgroundHandler` (top-level, `@pragma('vm:entry-point')`).
5. The handler branches on `message.data['type'] == 'token_refresh'`. It constructs a fresh `SingleAccountPca` from `MsalConstants`, calls `acquireTokenSilent`, writes the new access token via `TokenStorageService.saveTokens` (which updates `lastRefreshTime`), and records `silent_push_refresh_success` in the pending-telemetry ring buffer.
6. If step 5 throws (iOS plugin-channel limits in a background isolate are a known risk), the handler writes `SharedPreferences[pendingRefreshFlagKey] = true` and records `silent_push_fallback_flag_set`.
7. `AppLifecycleService._onAppResumed` reads both `isTokenStale()` and the pending flag; if either is set, it runs Layer 3 immediately, clears the flag, and reports success/failure.

### Cold-start recovery (Layer 5 entry)

If the app is cold-started after > 12h, `AuthNotifier.checkAuthStatus` → `silentSignIn` → MSAL throws (`AADSTS700082` / `AADSTS500210` / "no account in the cache"). `_handleSilentSignInFailure` inspects the message and, if `lastKnownUser.email` is non-null, emits `AuthReloginRequired(email, name)`. `LoginScreen` watches `authStateProvider` and shows `WelcomeBackDialog.show()` with `loginHint = email` — one tap re-signs in.

---

## Known unknowns / honest limitations

1. **iOS `msal_auth` in a background FCM isolate.** The Keychain cache is process-wide so the account is visible. But `msal_auth`'s iOS plugin channel registration may or may not succeed in a background isolate. If `acquireTokenSilent` throws, the fallback flag keeps us correct — refresh happens on next foreground inside the 12h window because the silent push arrived at 9–11h. Worst case we fall to Layer 5 for users who got the silent push but didn't open the app for the next hour.
2. **APNs throttling.** Apple delivers background pushes "opportunistically." The `refresh_push_timer_ran.sent` vs `silent_push_received` ratio in App Insights will quantify real-world deliverability.
3. **Force-killed iOS apps do not receive silent pushes.** iOS policy. Layer 5 is the only recourse.
4. **Android SCHEDULE_EXACT_ALARM (API 31+).** We no longer use `exactAllowWhileIdle` scheduled notifications, so this permission is not on the critical path for Layer 2 anymore. The manifest still declares it for future use; revisit if anything else needs exact alarms.
5. **Disabled Background App Refresh (iOS).** Background handler never runs; Layer 5 handles the re-login.

---

## Verifying in production

App Insights Kusto:

```kql
// Layer health, all 5 layers, last 24h
customEvents
| where timestamp > ago(24h)
| where name in ("battery_exempt_granted",
                 "silent_push_received", "silent_push_refresh_success",
                 "silent_push_refresh_failed", "silent_push_fallback_flag_set",
                 "foreground_refresh_success", "foreground_refresh_failed",
                 "wm_refresh_success", "wm_refresh_failed",
                 "welcome_back_shown", "cold_start_relogin_required")
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

Target: `foreground_refresh_success` + `silent_push_refresh_success` + `wm_refresh_success` ≫ `welcome_back_shown`. If `welcome_back_shown` is dominant, a background layer is broken.

Silent push deliverability:

```kql
customEvents
| where timestamp > ago(7d)
| where name in ("refresh_push_timer_ran", "silent_push_received")
| extend value = iff(name == "refresh_push_timer_ran",
                     toint(customDimensions.sent), 1)
| summarize sent = sumif(value, name == "refresh_push_timer_ran"),
            received = countif(name == "silent_push_received")
| extend delivery_pct = 100.0 * received / sent
```

Per-device diagnostics: tap the version text 7 times on the Profile screen to unlock the Token Diagnostics screen. It shows current token age, pending-refresh flag, battery-exempt status, and the last 50 telemetry events (drained from the cross-isolate ring buffer).

---

## Files that change together if policy ever shifts

- `MsalConstants` (`app/lib/core/constants/msal_constants.dart`)
- `msal_config.json` (`app/assets/msal_config.json`)
- Entra app registration 7db01206-135b-4a34-a4d5-2622d1a888bf
- `authMiddleware.ts` — `TENANT_ID`, `CLIENT_ID`, issuer, audience
