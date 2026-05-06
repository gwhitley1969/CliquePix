# Clique Pix — Beta Operations Runbook

**Last Updated:** May 4, 2026

Operational procedures for the Clique Pix open beta. Covers incident response, common troubleshooting, and maintenance tasks.

---

## Contacts

| Role | Contact |
|------|---------|
| Primary operator | Gene Whitley (bluebuildapps@gmail.com) |
| Azure subscription | `25410e67-...` (rg-cliquepix-prod) |
| Budget alerts | bluebuildapps@gmail.com (80% of $50/month) |

---

## Quick Reference — Key Resources

| Resource | Name | Portal Link |
|----------|------|-------------|
| Function App | `func-cliquepix-fresh` | Azure Portal → Function Apps |
| Container Apps Job | `caj-cliquepix-transcoder` | Azure Portal → Container Apps |
| PostgreSQL | `pg-cliquepixdb` | Azure Portal → Azure Database for PostgreSQL |
| Storage Account | `stcliquepixprod` | Azure Portal → Storage Accounts |
| App Insights | `appi-cliquepix-prod` | Azure Portal → Application Insights |
| APIM | `apim-cliquepix-003` (Basic v2, since 2026-05-05) | Azure Portal → API Management |
| Web PubSub | `wps-cliquepix-prod` | Azure Portal → Web PubSub |
| ACR | `cracliquepix` | Azure Portal → Container Registries |

---

## 1. Incident Response

### Severity Levels

| Level | Definition | Response Time | Examples |
|-------|-----------|---------------|----------|
| **P1** | Service down — users can't sign in or load content | 15 minutes | Function App crash, DB down, Front Door 503 |
| **P2** | Feature broken — core feature not working | 1 hour | Video upload fails, photos not loading, push not delivering |
| **P3** | Degraded — feature works but poorly | 4 hours | Slow uploads, delayed notifications, intermittent errors |
| **P4** | Minor — cosmetic or edge case | Next business day | UI glitch, non-critical error in logs |

### Triage Steps

1. **Check App Insights** — look for spike in exceptions or failures
   ```kql
   exceptions
   | where timestamp > ago(30m)
   | summarize count() by type, outerMessage
   | order by count_ desc
   ```

2. **Check Function App health** — Azure Portal → func-cliquepix-fresh → Overview → check for failures

3. **Check database** — connect via `psql` and verify connectivity
   ```bash
   psql "$PG_CONNECTION_STRING" -c "SELECT 1"
   ```

4. **Check storage** — verify blob access
   ```bash
   az storage container list --account-name stcliquepixprod --auth-mode login
   ```

---

## 2. Common Troubleshooting

### User reports seeing another user's events / photos after a sign-out → sign-up

**Symptoms:** A user reports that after signing out and a different account signing in / signing up on the same device (typical on shared family iPhone or beta-test device), the new user sees the prior user's events, cliques, and photos in their feed and can navigate into events and view photos.

**This is the cross-account data leak fixed 2026-05-06.** If a user reports this on a build dated 2026-05-06 or later, it means the invalidation listener regressed. Treat it as a P0 privacy incident.

**Diagnosis:**

1. Confirm the user's app version. The fix shipped 2026-05-06; pre-fix builds will exhibit the bug by design.

2. On the affected device, capture `flutter logs` (debug builds) or sysdiagnose / `idevicesyslog` (release builds) and search for:
   ```
   [AUTH] invalidating user-scoped state on identity change
   ```
   This debugPrint fires on every identity transition (sign-out, sign-up as a different user). Expected: exactly one occurrence per sign-out. If absent, the `ref.listen` in `app/lib/app/app.dart:_CliquePixState.build()` is not firing.

3. Verify the listener is wired:
   ```bash
   grep -n "ref.listen<String?>(currentUserIdProvider" app/lib/app/app.dart
   grep -n "_invalidateUserScopedState" app/lib/app/app.dart
   ```
   Both should return one match. If either is missing, the fix has been reverted.

4. Verify the bootstrap user_id tagging is in place:
   ```bash
   grep -n "bootstrapUserIdProvider" app/lib/main.dart app/lib/core/cache/list_bootstrap_providers.dart
   grep -n "bootstrapUserId == currentUserId" app/lib/features/events/presentation/events_providers.dart app/lib/features/cliques/presentation/cliques_providers.dart
   ```

5. Run the regression tests locally:
   ```bash
   cd app && flutter test test/events_provider_optimistic_test.dart test/cliques_provider_optimistic_test.dart
   ```
   The tests `rejects bootstrap when bootstrapUserId differs from currentUserId` and `returns empty list when currentUserId is null (signed out)` MUST both pass. If they fail, the fail-closed bootstrap logic is regressed.

**Common causes (post-fix regression):**
- Someone added a new user-scoped `FutureProvider.family` (e.g., a new feature endpoint) and forgot to add it to `_invalidateUserScopedState` in `app.dart`.
- Someone migrated `AuthNotifier` to a `Notifier` and the `ref.listen` in `app.dart` was incidentally removed.
- Someone changed the `currentUserIdProvider` definition so it doesn't emit on auth changes (e.g., switched from `ref.watch(authStateProvider)` to a constant).

**Resolution:**
- Restore the listener + invalidation list per `docs/AUTHENTICATION.md` "Sign out" section and `docs/DEPLOYMENT_STATUS.md` "iOS cross-account data leak after sign-out → sign-up."
- Add the new provider to `_invalidateUserScopedState` if a feature was added without invalidation.
- Ship a hotfix immediately. This is a privacy-disclosure regression with App Store / Play Store policy implications.

**Reference:** plan file `~/.claude/plans/okay-here-is-the-cozy-shamir.md`; commit history near 2026-05-06.

### Video stuck in "Processing..."

**Symptoms:** User uploads a video, card stays in processing state indefinitely.

**Diagnosis:**
1. Check if the queue message was created:
   ```bash
   az storage message peek --queue-name video-transcode-queue --account-name stcliquepixprod --auth-mode login
   ```

2. Check Container Apps Job executions:
   ```bash
   az containerapp job execution list -n caj-cliquepix-transcoder -g rg-cliquepix-prod -o table
   ```

3. Check for job failures in App Insights:
   ```kql
   customEvents
   | where name == "video_transcoding_failed"
   | where timestamp > ago(1h)
   | project timestamp, customDimensions
   ```

**Common causes:**
- KEDA scaler not triggering — verify with `az containerapp job show` and check scale rules
- FFmpeg crash on unusual source file — check job logs in Log Analytics
- Callback endpoint unreachable — verify function key hasn't been rotated

**Resolution:**
- Re-queue the message manually if the job never started
- If the job failed, check the video's `processing_status` in the DB and update to `failed` if stuck

### Push notifications not delivering

**Symptoms:** Users don't receive push notifications.

**Diagnosis:**
1. Verify FCM credentials are valid:
   ```kql
   customEvents
   | where name == "notification_send_failed"
   | where timestamp > ago(24h)
   ```

2. Check for stale tokens:
   ```sql
   SELECT COUNT(*) FROM push_tokens;
   SELECT COUNT(*) FROM push_tokens WHERE updated_at < NOW() - INTERVAL '30 days';
   ```

3. Verify the user has a token:
   ```sql
   SELECT * FROM push_tokens WHERE user_id = '<user_id>';
   ```

**Common causes:**
- FCM credentials expired or rotated in Firebase Console
- User revoked notification permissions on their device
- Token stale — user hasn't opened the app in a while

**Resolution:**
- If FCM credentials expired: update `FCM_CREDENTIALS` in Key Vault, restart Function App
- Stale tokens are cleaned up automatically on send failure

### User can't sign in — Entra token issues

**Symptoms:** User gets "Authentication required" or is prompted to re-login repeatedly.

**Diagnosis:**
1. Check if it's the 12-hour inactivity timeout:
   - User hasn't opened the app in >12 hours
   - Layer 5 (graceful re-login) should handle this with a one-tap "Welcome back"

2. Check if Entra External ID tenant is healthy:
   ```bash
   az rest --method GET --url "https://graph.microsoft.com/v1.0/organization"
   ```

3. Check App Insights for auth errors:
   ```kql
   customEvents
   | where name in ("foreground_refresh_failed", "silent_push_refresh_failed",
                    "wm_refresh_failed", "cold_start_relogin_required")
   | where timestamp > ago(24h)
   ```

**Common causes:**
- Entra 12-hour inactivity timeout (expected — Layer 5 handles it)
- JWKS endpoint unreachable (rare, usually Azure outage)
- Client ID or tenant ID misconfigured

### User reports unexpected re-login (5-layer defense troubleshooting)

**Symptoms:** "I haven't opened the app all day and now I have to sign in again." This is what the 5-layer defense exists to prevent.

**Quickest signal — App Insights health:**
```kql
// If welcome_back_shown is the dominant event, a background layer is broken.
customEvents
| where timestamp > ago(24h)
| where name in ("foreground_refresh_success", "silent_push_refresh_success",
                 "wm_refresh_success", "welcome_back_shown")
| summarize count() by name
| order by count_ desc
```

**Silent-push deliverability (Layer 2) — the most failure-prone layer:**
```kql
// sent = timer tried to deliver; received = device woke and ran handler
customEvents
| where timestamp > ago(7d)
| where name in ("refresh_push_timer_ran", "silent_push_received")
| extend sentCount = iff(name == "refresh_push_timer_ran",
                         toint(customDimensions.sent), 1)
| summarize sent = sumif(sentCount, name == "refresh_push_timer_ran"),
            received = countif(name == "silent_push_received")
| extend delivery_pct = 100.0 * received / sent
```

iOS deliverability below ~60% is expected (Apple throttles background pushes). If Android deliverability is below 80%, check the Layer 1 battery-exempt grant rate:
```kql
customEvents
| where timestamp > ago(7d)
| where name in ("battery_exempt_prompted", "battery_exempt_granted")
| summarize count() by name
```

**Per-user debugging:** have the user tap the version number 7 times on the Profile screen — this unlocks the Token Diagnostics screen. Have them screenshot the event ring buffer. Interpret by layer:
- Layer 3 firing (`foreground_refresh_success`) = healthy daily user
- Layer 2 firing (`silent_push_received` → `silent_push_refresh_success`) = healthy backgrounded user
- Layer 2 fallback fired (`silent_push_fallback_flag_set` + `foreground_refresh_success`) = iOS isolate couldn't run MSAL but recovered on next foreground — acceptable
- Layer 4 firing (`wm_refresh_success`) = Android WorkManager backup working
- Layer 5 fired (`welcome_back_shown`) = all background layers failed; user was caught gracefully
- `cold_start_relogin_required` = user was > 12h inactive AND app was force-killed before the silent push arrived

**Known expected Layer 5 cases (not bugs):**
- User force-killed the app + waited 12+ hours (iOS policy prevents background pushes to force-killed apps)
- User disabled Background App Refresh (iOS)
- User's device was off / in airplane mode during the 9-11h push window
- Samsung/Xiaomi aggressive battery optimization that never got the Layer 1 exemption

**Fix for "Layer 5 shows up too often on one device":**
1. Confirm `last_activity_at` is being updated for the user:
   ```sql
   SELECT id, last_activity_at, last_refresh_push_sent_at FROM users WHERE id = '<user-id>';
   ```
   `last_activity_at` should advance roughly every time the user opens the app. If it's stale, the auth middleware's fire-and-forget write is broken.
2. Confirm the push-token row exists and is fresh:
   ```sql
   SELECT platform, LEFT(token, 20), created_at, updated_at FROM push_tokens WHERE user_id = '<user-id>';
   ```
3. For Android users: confirm battery-optimization exemption was granted (`battery_exempt_granted` event for that user). If not, ask the user to grant it in system Settings → Apps → Clique Pix → Battery → Unrestricted.

### User reports a raw "DioException [bad response]: ... 401" on the home screen

**Symptoms:** "I opened the app and it showed a long red error message starting with 'DioException [bad response]'. It went away after a few seconds and asked me to sign in, but I saw the technical error first."

**Resolution:** confirmed and fixed 2026-05-03. The user-reported leak path was: returning user with cached MSAL token past Entra's 12-hour inactivity timeout (AADSTS700082) → cold-start `AllEventsNotifier.build()` called `repo.listAllEvents()` directly with no try/catch → 401 → `AuthInterceptor` attempted refresh, MSAL failed, but the interceptor only `debugPrint`'d the failure → AsyncNotifier transitioned to AsyncError → `home_screen.dart:292` rendered `eventsAsync.error.toString()` (the raw DioException). Concurrently, `_verifyInBackground` was racing to transition state to AuthReloginRequired, but the user saw the raw error first. Fix shipped:
- `home_screen.dart` now uses `friendlyApiErrorMessage(err, resourceLabel: ...)` instead of `error.toString()` — never renders raw DioException text
- `AuthInterceptor` switched to `authRepository.refreshTokenDetailed()` (returns structured `RefreshResult`) and on session-expired refresh failure (AADSTS700082 / AADSTS500210 / no_account_found) fires `AuthNotifier.triggerWelcomeBackOnSessionExpiry()` to transition state immediately — racing the AsyncError to the screen
- New `welcome_back_shown { source: 'interceptor' | 'lifecycle' }` telemetry split lets us measure how often the interceptor path fires vs the legacy on-resume path

**If this symptom recurs in a future build:**
1. Have the user screenshot the error (the verbatim "DioException" text vs the friendly mapping is the smoking gun for whether `friendlyApiErrorMessage` is being called)
2. Check App Insights for the welcome-back source split:
   ```kql
   customEvents
   | where timestamp > ago(24h)
   | where name == "welcome_back_shown"
   | extend source = tostring(customDimensions.source),
            reason = tostring(customDimensions.reason)
   | summarize count() by source, reason
   ```
   - `source=interceptor` rows mean the coordination is firing — the user shouldn't have seen the raw error at all. If they did, the home_screen.dart friendly-message change is missing
   - All `source` empty (legacy events only) or `source=lifecycle` only — the interceptor coordination is broken. Check `AuthInterceptor._isSessionExpired` matches the actual `errorCode` returned by `refreshTokenDetailed()` (the regex must stay in sync with `AuthRepository._extractAadstsCode`)
3. Most common regression cause: a future change reverts `home_screen.dart` to render `error.toString()` directly. Re-apply the `friendlyApiErrorMessage` import and call.
4. Second-most-common: a new screen surfaces a raw `DioException` via SnackBar/Dialog with `Text('$e')` or `Text(e.toString())`. Audit:
   ```bash
   cd app && grep -rn "SnackBar.*Text.*\$e\|content: Text(.*toString" lib/
   ```
   For any local action (delete photo, share video, delete account), the error is narrow-scope and a generic "Failed to X: ..." message is acceptable. For any bootstrap/refresh path that fires on cold start, the error MUST go through `friendlyApiErrorMessage` to avoid leaking raw DioException text.

**Three sites must stay in sync** (regex-matched session-expired pattern): `app/lib/services/auth_interceptor.dart::_isSessionExpired`, `app/lib/features/auth/domain/auth_repository.dart::_extractAadstsCode`, `app/lib/features/auth/presentation/auth_providers.dart::_handleSilentSignInFailure`. Adding a new pattern (e.g., a future Entra error code) requires updating all three. The comment on each site notes the others.

### iPhone user reports "video spinner spins forever"

**Symptoms:** "I tap a video on my iPhone and it just spins. Never plays. Same video plays fine on Android."

**Resolution:** confirmed and fixed 2026-05-03. Root cause was a documented iOS AVPlayer limitation: `VideoPlayerController.networkUrl(Uri.file(<m3u8 path>), formatHint: VideoFormat.hls)` with a manifest whose segment lines are absolute `https://*.blob.core.windows.net/...` SAS URLs leaves `AVPlayerItem` in `Status: Unknown` indefinitely. `controller.initialize()` returns a `Future` that NEVER resolves and NEVER throws. ExoPlayer (Android) handles cross-scheme manifest→segment fine, which masked the bug for the entire video v1 ship cycle. Fix shipped:
- `Platform.isIOS` branch in `_initializePlayer` cloud tier — skips HLS entirely on iOS, goes straight to MP4. v1 single-rendition HLS = MP4-equivalent.
- Universal `_initWithTimeout` helper wraps every `controller.initialize()` site (8s local file, 15s cloud/preview/HLS/MP4) — disposes controller on failure to prevent orphaned `AVPlayerItem` from wedging subsequent attempts.
- `[VPS]` `debugPrint` markers at every step — visible via Xcode device console for triage.

**If this symptom recurs in a future build:**
1. Get the user to install a release build (`flutter build ios --release` then install via Xcode → Run). On iOS 26.x, `flutter run --debug` triggers the LLDB launch-watchdog issue and the app blank-screens before any code runs — `--release` (or `--profile`) is the only diagnostic path. `debugPrint` output still flows to Xcode device console (Window → Devices and Simulators → iPhone → bottom log pane) in release mode.
2. Have the user tap a video. Watch for `[VPS]` log lines.
   - **`[VPS] tier=cloud: iOS — skipping HLS, going to MP4`** then `tier=mp4: initialize() returned OK` → fix is working, bug is elsewhere
   - **No `[VPS]` lines at all** → `_initializePlayer` never ran. Check the navigation/router state, the videoId, the Riverpod provider chain
   - **`[VPS] tier=mp4: initialize() FAILED` with TimeoutException** → MP4 SAS URL is unreachable. Verify the URL works in Safari from the same network. Check `Content-Type` on the blob (must be `video/mp4`, not `application/octet-stream`)
   - **`[VPS] tier=mp4: initialize() FAILED` with a different error** → blob auth or codec issue. Inspect the error message
3. If the iOS branch is gone (e.g., reverted), Phase 2A in `DEPLOYMENT_STATUS.md` "iPhone video playback hang — fixed (2026-05-03)" is the canonical fix. Re-add the `Platform.isIOS` branch in `app/lib/features/videos/presentation/video_player_screen.dart::_initializePlayer` cloud tier (after `repo.getPlayback()` resolves, before the HLS attempt).
4. **Do NOT re-enable HLS on iOS** unless `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 15 is updated and the v1.5 backend raw-m3u8 endpoint is shipped first. The `file://` workaround will hang again.

**Do not be misled by:** "blank white screen on launch" reports from iPhone users running profile-mode debug builds with `flutter run --profile` — that's just slow profile-mode startup + `flutter run` failing to attach the VM service, NOT a `main()` hang. The app DOES load; the user just hasn't waited long enough or has been distracted by the missing splash. Confirm by asking the user to wait 60+ seconds, or by deploying via Xcode → Run instead of `flutter run`.

### iPhone-recorded video plays sideways on Android viewer

**Symptoms:** "I uploaded a portrait video from my iPhone. On my iPhone it looks fine. My friend on Samsung sees the dog/face/scene rotated 90° — the floor is on the right side of the screen instead of the bottom."

**Resolution:** confirmed and fixed 2026-05-04. Root cause: iPhones store a rotation hint in the MOV container (legacy `tags.rotate` or modern Display Matrix side data) but record at the sensor's native landscape orientation. The transcoder's `-c copy` fast path (`remuxHlsAndMp4`) writes HLS MPEG-TS segments — and **MPEG-TS has no rotation atom**, so the hint is silently dropped, ExoPlayer plays raw landscape pixels in a portrait viewport. iPhone viewers were partly masked by Decision 15 (iOS plays MP4 directly, where `-c copy` sometimes preserves enough metadata for AVPlayer). Android viewers always tried HLS first and always lost. Fix shipped:
- New `extractRotation` + `rotation` field on `FfprobeResult`.
- `canStreamCopy` now requires `rotation === 0` — rotated sources drop to the slow re-encode path. There the libx264 encoder writes correctly-oriented pixels into both HLS segments and MP4 fallback (FFmpeg's default `autorotate` does the rotation at decode time).
- Slow path adds `-metadata:s:v:0 rotate=0` so the residual legacy `tags.rotate` atom doesn't propagate to the MP4 output and cause double-rotation.
- Slow-path scale filter now caps the long edge at 1920 (`scale=min(1920\,iw):min(1920\,ih):force_original_aspect_ratio=decrease`) instead of capping height. Without this, iPhone portrait videos (1080×1920) would have been crushed to 608×1080 by the prior landscape-only filter.
- Backend telemetry: `video_transcoding_completed` gains `sourceRotation: 0 | 90 | 180 | 270`.

See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 16 for the full design.

**If this symptom recurs in a future build:**

1. Confirm the user's APK is post-2026-05-04. Pre-fix builds always send rotated sources through the fast path.
2. Pull telemetry for the affected video:
   ```kql
   customEvents
   | where name == "video_transcoding_completed"
   | where timestamp > ago(2h)
   | where customDimensions.videoId == "<video-uuid-from-photos-row>"
   | project timestamp, processingMode = tostring(customDimensions.processingMode),
             sourceRotation = tostring(customDimensions.sourceRotation),
             durationSeconds = tostring(customDimensions.durationSeconds)
   ```
   - **`sourceRotation=0` and `processingMode=stream_copy`** → expected for any video that should play right-side up. If this video is sideways anyway, the bug is on the playback side (player aspect ratio, viewport sizing) rather than transcode-side rotation.
   - **`sourceRotation != 0` and `processingMode=stream_copy`** → REGRESSION. `canStreamCopy` should have rejected this. Check that the deployed transcoder image is the post-fix version, not a rolled-back v0.1.6. Image SHA in `az containerapp job show -n caj-cliquepix-transcoder -g rg-cliquepix-prod --query 'properties.template.containers[0].image' -o tsv`.
   - **`sourceRotation != 0` and `processingMode=transcode`** → fix path ran but output is still sideways. Either FFmpeg autorotate failed to fire (Dockerfile pin changed?) or `-metadata:s:v:0 rotate=0` failed to clear the residual atom. Pull the original blob from `photos/{cliqueId}/{eventId}/{videoId}/original.mp4`, run `ffprobe` locally, compare to the transcoded `fallback.mp4` and `hls/manifest.m3u8` to isolate.
3. Health check across all recent transcodes:
   ```kql
   customEvents
   | where name == "video_transcoding_completed"
   | where timestamp > ago(7d)
   | extend rot = toint(customDimensions.sourceRotation),
            mode = tostring(customDimensions.processingMode)
   | summarize count() by rot, mode
   ```
   Healthy: ~30–50% `rot != 0, mode=transcode` rows; zero `rot != 0, mode=stream_copy` rows.
4. **Rollback** if needed: `az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --image cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.6`. New uploads will revert to broken-rotation behavior; in-flight transcodes finish on whichever image was running when they started.

### iOS user reports "app vanishes the second I sign in"

**Symptoms:** "I tap Get Started, Safari opens, I sign in, Safari closes — and the app is just gone. I tap the icon again and I'm signed in fine, but it crashed once on the way in."

**Resolution:** confirmed and fixed 2026-05-01. Root cause was `app/ios/Runner/Info.plist` declaring `BGTaskSchedulerPermittedIdentifiers = [com.cliquepix.tokenRefresh]` without a corresponding `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` call in `AppDelegate.swift`. iOS 13+ raises `NSInternalInconsistencyException` and SIGABRTs the app the moment it inspects scheduling state for the unregistered identifier — typically when the FlutterViewController re-attaches after `SFSafariViewController` dismisses. Fix shipped: removed the `BGTaskSchedulerPermittedIdentifiers` array entirely (Layer 4 of the Entra refresh-token defense is Android-only — `com.cliquepix.tokenRefresh` is only used by `Workmanager`). See `DEPLOYMENT_STATUS.md` "BGTask SIGABRT iOS post-auth crash" for the full incident.

**If this symptom recurs in a future build:**
1. Reproduce on a tethered iPhone with `flutter run --debug` from `app/`. Watch the terminal for `*** Terminating app due to uncaught exception 'NSInternalInconsistencyException'`. Release builds silently SIGABRT — `--debug` is the only way to see the message in real time.
2. If the message names a `BGTaskScheduler` identifier, verify `app/ios/Runner/Info.plist` does NOT declare `BGTaskSchedulerPermittedIdentifiers`. If a future contributor re-added it, remove or pair it with a registered handler in `AppDelegate.swift`.
3. If the message names something else, capture the full backtrace via Xcode → Window → Devices and Simulators → select iPhone → View Device Logs → look for the most recent `Runner` crash. Attach to the incident.
4. iOS 26.x debug builds suffer a launch-watchdog issue when LLDB cannot find the dyld shared cache (warning `libobjc.A.dylib is being read from process memory`). If the app SIGKILLs at startup with `flutter run --debug` but launches fine with `--release`, this is the cause — pivot to release-build + Xcode device logs for diagnostics. The watchdog kill is not a code bug.

### User reports stuck "Get Started" spinner on cold launch

**Symptoms:** "When I open the app, the Get Started button just spins forever. Force-closing and reopening doesn't help."

This was the pre-optimistic-auth failure mode. With the current architecture (`main.dart` seeds AuthNotifier from cached storage before `runApp`), returning users skip LoginScreen entirely and first-time users see an enabled button on the first frame. If a user is reporting this *now*, either (a) they are a first-time user experiencing the interactive-sign-in hang (MSAL or backend) after tapping the button, or (b) the optimistic bootstrap is failing.

**Quickest signal — cold-start health:**
```kql
customEvents
| where timestamp > ago(24h)
| where name in ("cold_start_optimistic_auth", "cold_start_unauthenticated",
                 "cold_start_bootstrap_failed",
                 "background_verification_success",
                 "background_verification_timeout",
                 "login_screen_escape_hatch_shown",
                 "login_screen_escape_hatch_tapped")
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

Target: `cold_start_optimistic_auth` + `background_verification_success` dominate. `background_verification_timeout` and `escape_hatch_shown` should be < 1% of launches.

**Per-user debugging:**
1. Have the user tap "Get Started" once. If the spinner persists past 15 seconds, the "Having trouble? Sign in with a different account" link should appear. Tapping it clears the MSAL cache and retries. If they report this link doesn't appear, the client build is outdated.
2. Fetch their user id and check App Insights:
   ```kql
   customEvents
   | where user_Id == "<user-id>"
   | where timestamp > ago(1h)
   | where name startswith "cold_start_" or name startswith "background_verification_"
              or name startswith "login_screen_escape_hatch"
   | order by timestamp desc
   ```
3. If `cold_start_bootstrap_failed` fires repeatedly, the `FlutterSecureStorage` read in `main.dart` is throwing — likely a corrupt secure-storage bucket. Instruct user to reinstall the app.
4. If `background_verification_timeout` fires and is followed by `cold_start_relogin_required`, the user's cached session is stale / MSAL is wedged. This is the expected graceful-degradation path — the user should see the WelcomeBackDialog within ~8 seconds.

### Photos/videos not loading — SAS errors

**Symptoms:** Feed shows broken images or video player shows error.

**Diagnosis:**
1. Check if SAS generation is working:
   ```kql
   exceptions
   | where outerMessage contains "SAS" or outerMessage contains "delegation"
   | where timestamp > ago(1h)
   ```

2. Verify storage account accessibility:
   ```bash
   az storage account show -n stcliquepixprod -g rg-cliquepix-prod --query "allowSharedKeyAccess"
   ```
   Should return `false` — all access is via managed identity.

3. Verify managed identity role assignments:
   ```bash
   az role assignment list --assignee $(az functionapp identity show -n func-cliquepix-fresh -g rg-cliquepix-prod --query principalId -o tsv) --scope /subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Storage/storageAccounts/stcliquepixprod -o table
   ```

**Common causes:**
- User Delegation Key expired (cached for 1 hour, auto-refreshes)
- Managed identity role assignment removed accidentally
- Storage account network rules changed

### Avatar upload fails with AuthorizationFailure (shipped 2026-04-24)

**Symptoms:** Profile → tap avatar → pick photo → crop → Save → "Upload failed. Please try again." toast. Network tab shows a 403 on the direct `PUT https://stcliquepixprod.blob.core.windows.net/photos/avatars/{userId}/original.jpg?...` call with body `<Code>AuthorizationFailure</Code>`.

**Root-cause history:** the SAS service's upload permission set was regressed once before (commit `8d8decf`, 2026-03-24) — it shipped only `write` when Put Blob against a brand-new path requires both `write` AND `create`. Photos hit the regression because photo paths were always unique per photo ID; avatars would hit it the same way for every user's first upload. Reverted in the same round of fixes that shipped the client error mapper.

**Verify the fix is in place:**
```bash
grep -A 3 "permissions.write = true" backend/src/shared/services/sasService.ts
# Should show BOTH permissions.write = true AND permissions.create = true
```

If `create = true` is missing, the regression is back — re-add it, run `npm run build && npm test`, redeploy. If it's there, the 403 is coming from elsewhere (storage network rules, managed identity RBAC, clock skew on the client's SAS `se=` parameter).

### Avatar doesn't update on other users' feed cards

**Symptom:** User A uploads a new avatar. User B sees A's old avatar on A's photo/video cards for longer than expected.

**Expected behavior:** A's own Profile screen updates instantly (via `authStateProvider` push). A's feed cards still show the OLD avatar until the next 30-second feed poll (or pull-to-refresh). B's feed cards update on their next poll cycle. This is by design — invalidating every event's photo/video provider globally would be expensive for no real UX benefit.

**Not a bug unless:** B still sees the old avatar after multiple pull-to-refresh cycles. That would indicate the cache key isn't churning — check that `avatar_updated_at` is being emitted in the response (`customDimensions` on a recent `avatar_uploaded` telemetry event) and that the client's `cacheKey` computation references `avatar_updated_at.millisecondsSinceEpoch`.

### User reports avatar doesn't appear at all (stuck on initials)

**Symptoms:** User tapped "Add a photo" → picked an image → hit Save with no error toast → back on Profile → still sees initials.

**Diagnosis order:**

1. **DB check** — is the blob path actually stored?
   ```sql
   SELECT id, display_name, avatar_blob_path, avatar_thumb_blob_path, avatar_updated_at
   FROM users WHERE email_or_phone = '<user-email>';
   ```
   - All NULL → confirm endpoint never ran or failed silently. Check App Insights for `POST /api/users/me/avatar` around the upload time; look for exceptions
   - `avatar_blob_path` set but `avatar_thumb_blob_path` NULL → sharp thumb gen failed. Feed cards will fall through to the full 512px original (acceptable) but the feed was sized for thumbs. Re-run: client can re-upload or call confirm again

2. **Blob check** — does the blob actually exist?
   ```bash
   az storage blob exists --account-name stcliquepixprod --container-name photos --name "avatars/{userId}/original.jpg"
   ```

3. **Client cache check** — if DB and blob both look right but user STILL sees initials, `CachedNetworkImageProvider` may be serving a stale negative cache (404 was cached). Have the user kill + reopen the app; Flutter's cache entries with missing bytes are short-lived. Web users: hard refresh.

### Photo / video upload returns "Too many requests" (HTTP 429)

**Should not happen in beta** — all four APIM policy scopes (Global, Product, API, Operation) AND `bicep/apim/main.bicep` were verified clean as of 2026-05-05 (see `apim_policy.xml` in-file comment for the six-incident history). The Azure Monitor alert `apim-429-detected` fires on any APIM 429 within 5 minutes; if it triggers, run the Phase 0+A audit BELOW first, before anything else.

#### Phase 0+A — Audit ALL FOUR APIM policy scopes AND `bicep/apim/main.bicep`

The 2026-04-29 incident (#5) reproduced because the prior cleanup only touched the API-scope policy. The 2026-05-05 incident (#6) reproduced because the audit script only inspects LIVE APIM, not IaC — six op-scope rate-limit-by-key resources were declared in `bicep/apim/main.bicep` and a bicep deploy reintroduced what the previous live-APIM cleanup had removed. APIM has FOUR scopes (Global, Product, API, Operation) and a rate-limit at any of them produces the same 429 body. The `bicep/apim/main.bicep` source of truth is a fifth surface that can re-introduce orphaned policies on next deploy. **Always audit all five.**

```bash
BAK="/c/Users/genew/AppData/Local/Temp/apim-bak-$(date +%Y%m%d-%H%M)"
mkdir -p "$BAK"
SUB=25410e67-b3c8-49a2-8cf0-ab9f77ce613f
RG=rg-cliquepix-prod
APIM=apim-cliquepix-003
API=cliquepix-v1

# Global scope
az rest --method GET --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/policies/policy?api-version=2022-08-01&format=rawxml" --output-file "$BAK/global.xml" 2>/dev/null

# API scope
az rest --method GET --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/$API/policies/policy?api-version=2022-08-01&format=rawxml" --output-file "$BAK/api.xml"

# Product scopes
az apim product list -g "$RG" --service-name "$APIM" --query "[].name" -o tsv > "$BAK/products.txt"
while read -r p; do
  az rest --method GET --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/products/$p/policies/policy?api-version=2022-08-01&format=rawxml" --output-file "$BAK/product-$p.xml" 2>/dev/null
done < "$BAK/products.txt"

# Operation scopes
az apim api operation list -g "$RG" --service-name "$APIM" --api-id "$API" --query "[].name" -o tsv > "$BAK/ops.txt"
while read -r op; do
  az rest --method GET --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/$API/operations/$op/policies/policy?api-version=2022-08-01&format=rawxml" --output-file "$BAK/op-$op.xml" 2>/dev/null
done < "$BAK/ops.txt"

# The grep that names the culprit:
grep -l 'rate-limit\|<quota' "$BAK"/*.xml || echo "ALL LIVE-APIM SCOPES CLEAN"

# Also audit IaC — bicep/apim/main.bicep is the source of truth and can re-introduce
# what the live-APIM cleanup removed on the next bicep deploy. Incident #6
# (2026-05-05) was caused by exactly this kind of drift.
echo
echo "=== bicep/apim/main.bicep IaC audit ==="
grep -nE 'apis/operations/policies' /c/backup\ dev03/CliquePix/bicep/apim/main.bicep | tee "$BAK/bicep-op-policy-resources.txt"
echo
echo "=== bicep policy resources containing rate-limit-by-key ==="
grep -nE 'rate-limit-by-key|<quota' /c/backup\ dev03/CliquePix/bicep/apim/main.bicep | tee "$BAK/bicep-rate-limit-matches.txt" || echo "bicep/apim/main.bicep: NO rate-limit-by-key declarations"
```

Flagged file or bicep grep match → corresponding scope or IaC declaration is the source of the 429. Note: the Echo API sample (3 echo-api operation policies in bicep/apim/main.bicep) is the default APIM scaffolding and is unrelated to Clique Pix — its policies don't contain rate-limit-by-key, but if you ever see one there, it's still benign because Echo API isn't routed to from the client.

#### Phase B — Remove the rate-limit from the flagged scope

For a **product** scope (most likely — APIM ships default-product policies), PUT a clean replacement:

```bash
echo '{"properties":{"format":"rawxml","value":"<policies><inbound><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"}}' > "$BAK/product-clean.json"
az rest --method PUT --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/products/<PRODUCT>/policies/policy?api-version=2022-08-01" --headers "Content-Type=application/json" --body "@$BAK/product-clean.json"
```

For an **operation** scope, DELETE the policy entirely (APIM falls back to API scope):

```bash
az rest --method DELETE --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/$API/operations/<OP>/policies/policy?api-version=2022-08-01"
```

For the **API** scope, redeploy `apim_policy.xml` (the local source of truth — see commands in its in-file comment).

**ALSO edit `bicep/apim/main.bicep` to remove or simplify any matching `apis/operations/policies@2025-03-01-preview` resources** — otherwise the next `az deployment group create` re-introduces what you just deleted (the lesson of incident #6, 2026-05-05). The pattern: locate the resource at the line numbers reported by the bicep audit grep above, replace the entire `resource ... { ... }` block with a one-line comment explaining why it was removed and pointing at this incident in `apim_policy.xml`'s history. Operation resources themselves (`apis/operations` — declared elsewhere in bicep/apim/main.bicep) MUST stay — they define URL routing.

#### Phase C — Force counter-cache invalidation (Developer-tier gotcha)

APIM Developer tier has a single in-memory counter cache. Even after the policy clears, in-flight counters can keep firing for one ~60s window:

```bash
sleep 90
az apim api update -g rg-cliquepix-prod -n apim-cliquepix-003 --api-id cliquepix-v1 --protocols https
```

The `--protocols https` toggle is idempotent and forces APIM to refresh policies on the gateway pod.

#### Other 429 sources (rule-out only — none have been observed)

- **Azure Storage `Throttling Errors`** on `stcliquepixprod` — Storage 429 → `BlobUploadFailure` on the client, surfaced with the Azure error code. Extremely unlikely at beta volumes.
- **Front Door WAF** — Standard tier has no built-in rate limit but a custom WAF rule could 429. Currently no WAF configured.
- **Old APK** — pre-2026-04-29 APKs do NOT have the silent-retry safety net and will surface the 429 banner directly. Have the user install the latest `app-release.apk`.

### WorkManager (Layer 4) firing too often

Symptom: `customEvents | where name == "wm_refresh_success"` shows the event >1× per minute when it should fire ~3× per day.

Root cause (fixed 2026-04-27 in `app/lib/features/auth/domain/background_token_service.dart`):
- `Workmanager().registerPeriodicTask(... existingWorkPolicy: ExistingPeriodicWorkPolicy.replace)` re-creates the schedule on every app launch and queues immediate catch-up executions on Android.

Fix shipped in 2026-04-27 APK:
- `existingWorkPolicy: ExistingPeriodicWorkPolicy.keep` preserves the schedule across launches.
- `callbackDispatcher` reads `wm_last_run_at_ms` from SharedPreferences and short-circuits with a `wm_task_skipped_too_soon` telemetry event if last run was < 4 hours ago.

If the symptom recurs on a current APK, check whether `wm_last_run_at_ms` is being written successfully (SharedPreferences encryption issue?) and whether the Workmanager dispatcher is actually being invoked — `[AUTH-LAYER-4]` debug logs should fire on each invocation.

### "Organizer reports they can't see the 3-dot delete menu on others' photos/videos" (added 2026-04-28)

The event organizer should see a 3-dot menu on every clique member's media in events they created (the menu reads "Remove" instead of "Delete"). If they don't:

1. **Confirm they're the actual event creator.** Run:
   ```sql
   SELECT id, name, created_by_user_id FROM events WHERE id = '<eventId>';
   ```
   The `created_by_user_id` must equal the organizer's `users.id`. If they joined the event via a clique invite but DIDN'T create it, they have NO moderation power — that's by design (scope is `events.created_by_user_id` only, not clique owner).
2. **Confirm the user's APK is post-2026-04-28.** Pre-2026-04-28 builds gate the menu strictly on `uploadedByUserId == currentUserId`. The new build threads `eventCreatedByUserId` from `EventDetailScreen` → `EventFeedScreen` → cards. Have them install the latest `app-release.apk`.
3. **Confirm the backend is on the deploy that includes `canDeleteMedia`.** Hit `https://api.clique-pix.com/api/health` — should return 200 with the new build. If a curl `DELETE` from the organizer's account returns `FORBIDDEN`, the backend hasn't been redeployed.
4. **Web client:** confirm `eventCreatedByUserId={event.createdByUserId}` is passed in `EventDetailScreen.tsx` → `<MediaFeed>`. If a user reports the bug ONLY on web, this prop wiring is the most likely regression.
5. **Edge case — original event creator deleted their account.** Migration 004 sets `events.created_by_user_id` to NULL on user account deletion (ON DELETE SET NULL). Once null, NO ONE qualifies as the organizer. The event is effectively unmoderated. The cleanup timer will still reap on expiry. Out of scope to reassign moderation.

### "An organizer is mass-deleting other members' content abusively" (added 2026-04-28)

The 5-min App Insights alert (Kusto query B in §7) is the early-warning. If you get paged:

1. **Open the row.** It contains `organizerId`, `eventId`, `uniqueUploadersAffected`, `deletions`. A high `uniqueUploadersAffected` against a single event is the strongest signal.
2. **Check the event.** Does it look spammy or genuinely conflicted? Sometimes "mass delete" is legitimate cleanup of test uploads or accidental duplicates.
3. **Decision tree:**
   - Legitimate cleanup → no action.
   - Genuinely abusive moderator → there is no in-app appeals workflow in v1. Out-of-band recovery: photos/videos are soft-deleted (`status='deleted'`); blobs are deleted but the DB row exists for ~7 days until the cleanup timer hard-deletes the event. Within that window you can manually reset `status='active'` (blobs are gone, so URLs will 404 — content is unrecoverable). Better path: reach out to the affected uploader to apologize and ask them to re-upload.
   - Pattern across multiple events by the same organizer → consider de-platforming via `DELETE /api/users/me` (admin variant TBD post-v1).
4. **Long-term:** if abuse becomes a pattern, design an appeals/notification workflow (currently out of scope — the choice in the design phase was deliberately silent removal to keep moderation friction-free).

---

## 3. Database Operations

### Backup & Restore

Azure Database for PostgreSQL Flexible Server provides automated backups:
- **Retention:** 7 days (default)
- **Frequency:** Daily full backup + continuous WAL archiving
- **RPO:** ~5 minutes (point-in-time restore)

**Verify backup is enabled:**
```bash
az postgres flexible-server show -n pg-cliquepixdb -g rg-cliquepix-prod --query "backup"
```

**Point-in-time restore:**
```bash
az postgres flexible-server restore \
  --resource-group rg-cliquepix-prod \
  --name pg-cliquepixdb-restored \
  --source-server pg-cliquepixdb \
  --restore-time "2026-04-10T12:00:00Z"
```
Then update the `PG_CONNECTION_STRING` in Key Vault to point to the restored server.

### Useful Queries

**Active user count (last 7 days):**
```sql
SELECT COUNT(DISTINCT uploaded_by_user_id) FROM photos
WHERE created_at > NOW() - INTERVAL '7 days';
```

**Storage usage by event:**
```sql
SELECT e.name, COUNT(p.id) as media_count,
  SUM(p.file_size_bytes) / 1048576 as total_mb
FROM photos p JOIN events e ON e.id = p.event_id
WHERE p.status = 'active'
GROUP BY e.name ORDER BY total_mb DESC;
```

**Video processing stats:**
```sql
SELECT processing_status, COUNT(*) FROM photos
WHERE media_type = 'video'
GROUP BY processing_status;
```

### Force-clean stale notifications (one-shot)

The 15-min `cleanupExpired` timer runs `sweepStaleNotifications()` on every tick. After deploying a fresh notification-cleanup change, you can clear the historical accumulation immediately instead of waiting up to 15 min for the first sweep. Idempotent and safe to re-run.

```sql
-- Drop notifications whose target event no longer exists
DELETE FROM notifications
WHERE payload_json ? 'event_id'
  AND NOT EXISTS (
    SELECT 1 FROM events e WHERE e.id::text = notifications.payload_json->>'event_id'
  );

-- Drop notifications whose target photo is gone or soft-deleted
DELETE FROM notifications
WHERE payload_json ? 'photo_id'
  AND NOT EXISTS (
    SELECT 1 FROM photos p
    WHERE p.id::text = notifications.payload_json->>'photo_id'
      AND p.status = 'active'
  );

-- Drop notifications whose target video is gone or soft-deleted
DELETE FROM notifications
WHERE payload_json ? 'video_id'
  AND NOT EXISTS (
    SELECT 1 FROM photos p
    WHERE p.id::text = notifications.payload_json->>'video_id'
      AND p.status = 'active'
  );

-- Drop notifications whose target clique no longer exists
DELETE FROM notifications
WHERE payload_json ? 'clique_id'
  AND NOT EXISTS (
    SELECT 1 FROM cliques c WHERE c.id::text = notifications.payload_json->>'clique_id'
  );
```

Telemetry: `stale_notifications_deleted` with `trigger ∈ {event_manual_delete, photo_deleted, video_deleted, periodic_sweep}`. See `docs/NOTIFICATION_SYSTEM.md` → "Notification cleanup on target deletion" for the full design.

---

## 4. Key Rotation

### FCM Credentials

1. Generate new service account key in Firebase Console
2. Update Key Vault:
   ```bash
   az keyvault secret set --vault-name kv-cliquepix-prod --name fcm-credentials --value '<new-json>'
   ```
3. Restart Function App:
   ```bash
   az functionapp restart -n func-cliquepix-fresh -g rg-cliquepix-prod
   ```

### Function Key (Internal Callback)

The Container Apps Job uses a function key to call `POST /api/internal/video-processing-complete`.

1. Rotate the function key:
   ```bash
   az functionapp function keys set -n func-cliquepix-fresh -g rg-cliquepix-prod \
     --function-name videoProcessingComplete --key-name default --key-value '<new-key>'
   ```

2. Update the Container Apps Job secret:
   ```bash
   az containerapp job secret set -n caj-cliquepix-transcoder -g rg-cliquepix-prod \
     --secrets function-callback-key=<new-key>
   ```

3. Verify by uploading a test video and checking the callback succeeds.

---

## 5. Cost Monitoring

### Current Budget

- **Budget:** $50/month
- **Alert:** 80% ($40) triggers email to bluebuildapps@gmail.com
- **Expected cost at beta scale (~100 videos/month):** $25-40/month

### Cost Breakdown

| Service | Estimated Monthly | Notes |
|---------|------------------|-------|
| PostgreSQL Flexible Server | ~$13 | Burstable B1ms |
| Storage Account (GZRS) | ~$5-10 | Depends on media volume |
| Function App (Consumption) | ~$0-2 | Pay-per-execution |
| Container Apps Job | ~$3-11 | Pay-per-execution, KEDA-triggered |
| Front Door (Standard) | ~$5 | Base fee |
| APIM (Consumption) | ~$0-3 | Pay-per-call |
| Web PubSub (Free/Standard) | ~$0-5 | Depends on connections |
| App Insights | ~$0-2 | Data ingestion |
| ACR (Standard) | ~$5 | Image storage |

### If costs spike

1. Check App Insights for unusual traffic patterns
2. Check storage account metrics for unexpected blob growth
3. Check Container Apps Job execution count — runaway transcoding jobs?
4. Check APIM `Requests` metric for unusual call volume per JWT subject (rate-limit-by-key was removed 2026-04-27; APIM no longer auto-throttles, so abuse appears as raw request volume not 429s)
5. If a single user is making excessive API calls, options are: (a) revoke their CIAM token, (b) add a temporary `is_blocked` column / check at the Function-App layer, (c) re-enable rate-limit-by-key on APIM Standard v2 tier (NOT Developer — see `apim_policy.xml` incident history)

---

## 6. Deployment Checklist

### Backend (Function App)

```bash
cd backend
npm run build
func azure functionapp publish func-cliquepix-fresh
```

### Transcoder (Container Apps Job)

```bash
cd backend/transcoder
npm run build
docker build -t cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.X .
az acr login --name cracliquepix
docker push cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.X
az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod \
  --image cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.X
```

### Flutter App

**Android APK:**
```bash
cd app
flutter clean
flutter build apk --release
# APK at build/app/outputs/flutter-apk/app-release.apk
```

**iOS (TestFlight):**
```bash
cd app
flutter clean
flutter build ipa --release
# Upload .ipa via Xcode Organizer or Transporter
```

---

## 7. App Insights Quick Queries

**Error rate last hour:**
```kql
requests
| where timestamp > ago(1h)
| summarize total = count(), failed = countif(success == false)
| extend error_rate = round(100.0 * failed / total, 2)
```

**Slow endpoints (>3s):**
```kql
requests
| where timestamp > ago(24h) and duration > 3000
| summarize count() by name
| order by count_ desc
```

**Video transcoding performance:**
```kql
customEvents
| where name == "video_transcoding_completed"
| extend dur = todouble(customDimensions.durationSeconds), mode = tostring(customDimensions.processingMode)
| summarize p50 = percentile(dur, 50), p95 = percentile(dur, 95), count() by mode
```

**Failed uploads:**
```kql
customEvents
| where name in ("photo_upload_failed", "video_upload_failed")
| where timestamp > ago(24h)
| project timestamp, name, customDimensions
```

**Cold-start render performance (added 2026-05-03 — Tier 1 stale-while-revalidate cache rollout):**
```kql
// `home_first_render_ms` fires the first time HomeScreen returns non-skeleton
// content (cached or fresh). `hadCache=true` indicates a returning user hit
// the optimistic-data path; this should be a SUB-SECOND p95 if Tier 1 is
// working correctly. `hadCache=false` is true first-launch and is bounded by
// backend cold-start (Tier 2 territory).
customEvents
| where name == "home_first_render_ms"
| where timestamp > ago(7d)
| extend ms = toint(customDimensions.ms),
         hadCache = tostring(customDimensions.hadCache)
| summarize p50 = percentile(ms, 50), p95 = percentile(ms, 95), n = count()
            by hadCache, bin(timestamp, 1d)
| render timechart
```

```kql
// `home_first_fresh_data_ms` fires when the silent refresh actually lands.
// This is the gate for considering Tier 2 (backend cold-start fixes —
// pg-pool warmup, Function App plan migration). Trigger Tier 2 if p95 stays
// > 5 s for ≥ 2 days after Tier 1 ships.
customEvents
| where name == "home_first_fresh_data_ms"
| where timestamp > ago(7d)
| extend ms = toint(customDimensions.ms)
| summarize p50 = percentile(ms, 50), p95 = percentile(ms, 95), n = count()
            by bin(timestamp, 1d)
| render timechart
```

**"Who reacted?" sheet usage (added 2026-05-02 — engagement signal):**
```kql
// Server-side fires on every successful GET /api/{photos|videos}/:id/reactions.
// Photos vs videos split + per-day volume.
customEvents
| where name == "reactor_list_fetched"
| where timestamp > ago(7d)
| extend mediaType = tostring(customDimensions.mediaType),
         total = toint(customDimensions.totalReactions)
| summarize opens = count(),
            avg_total_reactions = avg(total)
            by mediaType, bin(timestamp, 1d)
| render timechart
```

```kql
// Web-only: open count + filter usage. Useful for splitting "tap strip"
// (reactionFilter == 'all') vs no current path; reserved if a desktop
// long-press / right-click filter is ever added.
customEvents
| where name == "web_reactor_list_viewed"
| where timestamp > ago(7d)
| summarize count() by tostring(customDimensions.reactionFilter)
```

**Avatar upload health (added 2026-04-24):**
```kql
customEvents
| where name in ("avatar_uploaded", "avatar_removed", "avatar_frame_changed")
| where timestamp > ago(24h)
| summarize count() by name
```

**Avatar upload P95 latency** (expect < 2 s — includes sharp thumb gen):
```kql
requests
| where timestamp > ago(24h) and name == "POST /api/users/me/avatar"
| summarize p50 = percentile(duration, 50), p95 = percentile(duration, 95), count()
```

**Welcome-prompt funnel** (healthy onboarding: Yes + Later ≥ 70%, Dismissed ≤ 30%):
```kql
let shown = customEvents | where name == "avatar_prompt_shown" | where timestamp > ago(7d) | count;
let yes = customEvents
  | where name == "avatar_uploaded" and timestamp > ago(7d)
  | join kind=inner (customEvents | where name == "avatar_prompt_shown" | project userId = tostring(customDimensions.userId), promptTs = timestamp) on $left.customDimensions.userId == $right.userId
  | where datetime_diff('second', timestamp, promptTs) between (0 .. 60)
  | count;
let later = customEvents | where name == "avatar_prompt_snoozed" | where timestamp > ago(7d) | count;
let dismiss = customEvents | where name == "avatar_prompt_dismissed" | where timestamp > ago(7d) | count;
print shown = toscalar(shown), yes = toscalar(yes), later = toscalar(later), dismiss = toscalar(dismiss)
```

**Organizer media moderation — volume per day** (added 2026-04-28; sanity baseline):
```kql
customEvents
| where timestamp > ago(30d)
| where name in ("photo_deleted","video_deleted")
| where tostring(customDimensions.deleterRole) == "organizer"
| summarize count() by bin(timestamp, 1d)
| render timechart
```

**Organizer abuse signal** (alert candidate — 5+ deletes by one organizer in a 5-min window against media they didn't upload):
```kql
let WINDOW = 5m;
let THRESHOLD = 5;
customEvents
| where timestamp > ago(7d)
| where name in ("photo_deleted","video_deleted")
| where tostring(customDimensions.deleterRole) == "organizer"
| extend organizerId = tostring(customDimensions.userId),
         eventId     = tostring(customDimensions.eventId),
         uploaderId  = tostring(customDimensions.uploaderId)
| summarize deletions = count(),
            uniqueUploadersAffected = dcount(uploaderId),
            sampleEvent = any(eventId)
            by organizerId, bin(timestamp, WINDOW)
| where deletions >= THRESHOLD
```
Wire as an App Insights Logs alert (5-min cadence, email to bluebuildapps@gmail.com). Tune the threshold after the first week's data.

**Per-event cleanup ratio** (% of media in an event that was organizer-removed — high values flag conflict-heavy events):
```kql
customEvents
| where name in ("photo_deleted","video_deleted")
| where timestamp > ago(30d)
| extend eventId = tostring(customDimensions.eventId),
         role    = tostring(customDimensions.deleterRole)
| summarize organizerDeletes = countif(role == "organizer"),
            totalDeletes     = count()
            by eventId
| extend cleanupRatio = todouble(organizerDeletes) / todouble(totalDeletes)
| order by cleanupRatio desc
```

**New event real-time fan-out — server emit** (added 2026-04-30):
```kql
customEvents
| where name == "new_event_push_sent"
| where timestamp > ago(7d)
| extend recipientCount   = toint(customDimensions.recipientCount),
         webPubSubFailures = toint(customDimensions.webPubSubFailures),
         fcmFailures      = toint(customDimensions.fcmFailures)
| summarize total_pushes = count(),
            total_recipients = sum(recipientCount),
            total_wps_failures = sum(webPubSubFailures),
            total_fcm_failures = sum(fcmFailures)
| extend wps_failure_rate = round(100.0 * total_wps_failures / total_recipients, 2),
         fcm_failure_rate = round(100.0 * total_fcm_failures / total_recipients, 2)
```
Healthy: failure rates < 1%. Sustained > 5% indicates Web PubSub or FCM service degradation; cross-check Azure Service Health.

**New event real-time delivery rate** (foreground % — proxy: `new_event_received` / `new_event_push_sent` recipient count):
```kql
let scheduled_recipients =
  customEvents
  | where name == "new_event_push_sent"
  | where timestamp > ago(7d)
  | summarize total = sum(toint(customDimensions.recipientCount));
let received =
  customEvents
  | where name == "new_event_received"
  | where timestamp > ago(7d)
  | count;
print server_recipient_count = toscalar(scheduled_recipients),
      client_received        = toscalar(received),
      foreground_delivery_rate_pct = round(100.0 * toscalar(received) / toscalar(scheduled_recipients), 1)
```
Expectation: anywhere from 30-80% depending on how often the average user has the app foregrounded. Below 20% suggests a Web PubSub connection-lifecycle bug (e.g., `_connectRealtime` failing silently on auth start).

**Realtime connection health**:
```kql
customEvents
| where timestamp > ago(7d)
| where name in ("realtime_connected","realtime_connect_failed","realtime_reconnected_on_resume")
| summarize count() by name
```
`realtime_connect_failed` should be near zero. `realtime_reconnected_on_resume` count over 7d divided by daily active users tells you how often the WebSocket gets dropped (cell-signal blips, OS-killed, etc.) — high values are normal on iOS where backgrounded apps lose the connection.

**New event tap-through** (engagement):
```kql
let pushes = customEvents | where name == "new_event_push_sent" | where timestamp > ago(7d) | summarize total = sum(toint(customDimensions.recipientCount));
let taps   = customEvents | where name == "new_event_tapped_fcm" | where timestamp > ago(7d) | count;
print recipients = toscalar(pushes), taps = toscalar(taps),
      tap_rate_pct = round(100.0 * toscalar(taps) / toscalar(pushes), 1)
```
Reasonable: 5-15% (most users see the event in-app via Web PubSub and don't tap the FCM banner).

**Friday reminder coverage** (added 2026-04-30 — should approach 100% of recently-active signed-in users):
```kql
let scheduled =
  customEvents
  | where timestamp > ago(7d) and name == "friday_reminder_scheduled"
  | summarize dcount(user_Id);
let activeUsers =
  customEvents
  | where timestamp > ago(7d) and name == "auth_verify_success"
  | summarize dcount(user_Id);
print scheduled = toscalar(scheduled),
      active    = toscalar(activeUsers),
      coverage  = round(100.0 * toscalar(scheduled) / toscalar(activeUsers), 1)
```

**Friday reminder reason breakdown** (sanity — `cold_start` should dominate; `tz_changed` rare; `os_purged` should be ~0 unless something is wrong with the OS):
```kql
customEvents
| where name == "friday_reminder_scheduled"
| where timestamp > ago(30d)
| summarize count() by tostring(customDimensions.reason)
| order by count_ desc
```

**Friday reminder TZ-lookup failures** (should be ~0 — non-zero indicates `flutter_timezone` plugin issues on a real device):
```kql
customEvents
| where name == "friday_reminder_tz_lookup_failed"
| where timestamp > ago(30d)
| summarize count() by tostring(customDimensions.errorCode)
```

**Friday reminder tap-through** (engagement signal — what fraction of fires get tapped? Compare schedules in last week to taps in last week):
```kql
let taps =
  customEvents
  | where name == "friday_reminder_tapped"
  | where timestamp > ago(7d)
  | summarize tap_count = count();
// Approximate: each user with a schedule got ~1 fire per week. We can't observe
// the OS-level fire directly (no client telemetry on display), so this is a
// proxy that's accurate within ±10%.
let users_scheduled =
  customEvents
  | where name == "friday_reminder_scheduled"
  | where timestamp > ago(7d)
  | summarize dcount(user_Id);
print taps      = toscalar(taps),
      users     = toscalar(users_scheduled),
      tap_rate  = round(100.0 * toscalar(taps) / toscalar(users_scheduled), 1)
```

---

## 8. APIM Migration: Developer → Basic v2

> ✅ **EXECUTED 2026-05-05.** Migrated from `apim-cliquepix-002` (Developer, ~$50/month, no SLA) to **`apim-cliquepix-003`** (Basic v2, $150/month, 99.95% SLA, autoscale 1→10 units, v2 platform). Total wall-clock from Phase A start → Phase H decommission: **~46 minutes** (much faster than the 4-6h budget; v2 platform provisions in 5-10 min vs Developer's 30-45 min and the 24-48h soak was compressed to inline validation per user direction). See `docs/DEPLOYMENT_STATUS.md` top entry for the executed-state writeup including the Phase B retry that surfaced 5 v2-incompatible classes of bicep resources (`portalsettings`, `products/groups`, `products/groupLinks`, `groups/users` for system groups, `subscriptions` with bad scope) — bicep was hand-cleaned and the redeploy succeeded. The procedure below is preserved as a reference for any future Developer ↔ v2 migration in another environment, with executed-state deviations called out inline.

**One-time procedure.** Move APIM from `apim-cliquepix-002` (Developer tier — no SLA, single instance, classic platform) to a new Basic v2 instance before App Store / Play Store submission. Original budget: 4-6 hours of focused work plus 24-48 hours of soak. Actual: ~46 min including all cleanup + decommission.

### Why now

| Pre-migration risk | Mitigation |
|---|---|
| App Store / Play Store reviewer hits API during 24-48h review window | Need stable gateway — Developer tier has no SLA |
| First week of public users gets first APIM outage = bad reviews you can't undo | Basic v2 has 99.95% SLA |
| Microsoft maintenance event during launch week | v2 platform has rolling updates; Developer is single-instance |
| Outage unobserved | Basic v2 has Azure Status Page coverage; Developer doesn't |

### What stays the same

- The Function App (`func-cliquepix-fresh`), storage account (`stcliquepixprod`), PostgreSQL, Front Door, and Web PubSub are all untouched.
- Custom domain `api.clique-pix.com` stays on Front Door — APIM doesn't need its own custom domain because clients hit Front Door.
- `bicep/apim/main.bicep` is updated in place (new SKU, new APIM name) and re-deployed against the same resource group.
- All policies (the API-scope `<base/>` + CORS), products (`starter`, `unlimited`), and operation routes (`auth-verify`, `upload-url`, `catch-all-*`) are recreated by the bicep redeploy.
- The Developer-tier `apim-cliquepix-002` stays running during migration as a hot fallback. We don't decommission it until 24-48h after Front Door has been pointing at the new Basic v2 instance with zero issues.

### Pre-flight checklist (do these BEFORE starting the migration)

- [ ] **Commit current state to git.** `bicep/apim/main.bicep` + the 6 modified files from incident #6 must be committed first so there's a clean reference point if rollback is needed.
- [ ] **Verify no client code or tests reference the APIM hostname directly.** Should be zero hits — clients hit `api.clique-pix.com` (Front Door custom domain), not `apim-cliquepix-002.azure-api.net`. Quick check:
  ```bash
  grep -rn "apim-cliquepix" app/ webapp/ backend/ docs/ 2>/dev/null | grep -v "BETA_OPERATIONS_RUNBOOK\|DEPLOYMENT_STATUS\|ARCHITECTURE\|apim_policy"
  ```
  Expected: matches only in docs (which is fine — they describe the resource, not a runtime dependency). Any `app/`, `webapp/`, or `backend/` match means a hardcoded hostname that needs to be replaced before migration.
- [ ] **Backup current APIM state.** Re-run the Phase 0+A audit script (§2) to dump current policies; commit the backup folder reference into the migration commit message for rollback.
- [ ] **Note current Function App authentication state.** APIM forwards the `Authorization: Bearer …` header verbatim — JWT validation happens in `authMiddleware.ts`, not at APIM. Migration shouldn't affect this, but if anything's been adjusted, it'd surface here.
- [ ] **Identify a low-traffic 4-hour window.** Tonight or early tomorrow morning, when your beta cohort is least active. The migration itself is zero-downtime once Front Door cuts over, but you want to be able to fix problems without anyone watching.

### Phase 1 — Update bicep for Basic v2 (15-30 min)

Edit `bicep/apim/main.bicep`:

```bicep
// FIND the APIM service resource (likely first ~30 lines):
resource service_apim_cliquepix_002_name_resource 'Microsoft.ApiManagement/service@2025-03-01-preview' = {
  name: 'apim-cliquepix-002'    // ← rename to 'apim-cliquepix-v2'
  location: 'eastus'
  sku: {
    name: 'Developer'           // ← change to 'BasicV2'
    capacity: 1
  }
  properties: {
    publisherEmail: '...'
    publisherName: '...'
  }
}
```

Required changes:
1. **Resource name** in bicep: keep the bicep symbol name (`service_apim_cliquepix_002_name_resource`) for minimum diff, but change the `name:` property from `'apim-cliquepix-002'` to `'apim-cliquepix-v2'` (or whatever you want — pick a v2 suffix so the old/new can coexist during migration).
2. **SKU**: `'Developer'` → `'BasicV2'` (note the capital V).
3. **API version**: ensure it's `2024-05-01` or later — Basic v2 features require this. The current bicep uses `2025-03-01-preview` which is fine.
4. **Remove classic-tier-only properties** (none in Clique Pix's bicep that I can see — but if the bicep references `virtualNetworkType`, `publicIpAddressId`, `additionalLocations`, or `multiRegion`, remove them; v2 has different schemas).
5. **Reference to APIM in dependent resources**: every resource with `parent: service_apim_cliquepix_002_name_resource` keeps that — the bicep symbol name doesn't change, only the deployed `name:` property.

**Find/replace candidates** (do these carefully — review each match before replacing):
- The string `apim-cliquepix-002` in the bicep `name:` properties → `apim-cliquepix-v2`. Should appear ~1-2 times.
- The string `Developer` in `sku.name` → `BasicV2`. Should appear once.

### Phase 2 — Provision Basic v2 in parallel (30-45 min)

```bash
RG=rg-cliquepix-prod
az deployment group create \
  --resource-group "$RG" \
  --template-file bicep/apim/main.bicep \
  --name apim-migration-$(date +%Y%m%d-%H%M)
```

Watch for:
- **Provisioning time**: Basic v2 provisions in ~5-10 min (vs Developer's 30-45 min). Much faster.
- **Drift errors on existing resources**: bicep tries to update everything in the file, including resources that should be left alone. If it fails on something like the Echo API sample, comment that resource out for the migration deploy and add it back after.
- **API operations + policies recreate**: the bicep declares all 7 operations + the API-scope policy. They'll be created on the new instance. The 6 op-scope rate-limit policies are NOT in bicep anymore (incident #6 removed them), so the new instance starts clean by design.

After deployment succeeds:

```bash
# Direct probe of new APIM (NOT through Front Door)
curl -s --ssl-no-revoke -o /dev/null -w "HTTP %{http_code} (%{time_total}s)\n" \
  https://apim-cliquepix-v2.azure-api.net/api/health
# Expected: HTTP 200, similar latency to Developer tier
```

### Phase 3 — Re-grant managed identity RBAC (15 min)

The new APIM instance has a NEW system-assigned managed identity (different principal ID). If APIM is using managed identity for any Key Vault references in named values:

```bash
NEW_PRINCIPAL_ID=$(az apim show -g rg-cliquepix-prod -n apim-cliquepix-v2 --query 'identity.principalId' -o tsv)

az role assignment create \
  --assignee "$NEW_PRINCIPAL_ID" \
  --role "Key Vault Secrets User" \
  --scope "$(az keyvault show -g rg-cliquepix-prod -n kv-cliquepix-prod --query id -o tsv)"
```

**Verify** with `az role assignment list --assignee $NEW_PRINCIPAL_ID -o table`. Confirm the same roles the old APIM had (per `BETA_OPERATIONS_RUNBOOK.md §2`'s SAS error troubleshooting section, which lists APIM RBAC).

If APIM doesn't actually use Key Vault for any named values (likely true for Clique Pix as of 2026-05-05 — verify with `az apim nv list -g rg-cliquepix-prod --service-name apim-cliquepix-002 -o table`), this step is a no-op.

### Phase 4 — Add new APIM as second Front Door origin (15 min)

Front Door has an origin group pointing at the Developer-tier APIM. We add the Basic v2 APIM as a SECOND origin in the same group, with weight 0 (no traffic yet) so we can stage the cutover.

```bash
az afd origin create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> \
  --origin-name apim-v2 \
  --host-name apim-cliquepix-v2.azure-api.net \
  --origin-host-header apim-cliquepix-v2.azure-api.net \
  --priority 1 \
  --weight 0 \
  --enabled-state Enabled \
  --http-port 80 \
  --https-port 443
```

Find your origin group name with:
```bash
az afd origin-group list --resource-group rg-cliquepix-prod --profile-name fd-cliquepix-prod -o table
```

### Phase 5 — Cut over (15 min + 30 min observation)

Flip Front Door weight from old origin = 100, new origin = 0 → old = 0, new = 100. (Origin priorities are 1 — only weight matters for traffic distribution.)

```bash
# Set new origin weight to 100 (all traffic)
az afd origin update \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> \
  --origin-name apim-v2 \
  --weight 100

# Set old origin weight to 0 (no traffic)
az afd origin update \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> \
  --origin-name <OLD_ORIGIN_NAME> \
  --weight 0
```

Front Door propagation: ~5 minutes globally.

**Immediate post-cutover smoke test:**
```bash
# Through Front Door — should now hit Basic v2
for i in 1 2 3 4 5; do
  curl -s --ssl-no-revoke -o /dev/null -w "  attempt $i: HTTP %{http_code} (%{time_total}s)\n" \
    https://api.clique-pix.com/api/health
done
# Expected: 5× HTTP 200, sub-second latencies
```

### Phase 6 — Full validation (1-2 hours)

Run the full BETA_TEST_PLAN smoke tests against `api.clique-pix.com` (which now points at Basic v2):

- [ ] Sign-in completes end-to-end on Android. (`POST /api/auth/verify` returns 200; user lands on Events screen.)
- [ ] Sign-in completes end-to-end on iOS.
- [ ] List Events. (`GET /api/events` returns 200 with the user's events.)
- [ ] List Cliques. (`GET /api/cliques` returns 200.)
- [ ] Photo upload — upload-url + blob PUT + commit all succeed. (`POST /api/events/{id}/photos/upload-url`, then commit `POST /api/events/{id}/photos`.)
- [ ] Video upload — block uploads complete; transcoder triggers; `video_ready` push arrives.
- [ ] DM message — send + receive in real-time via Web PubSub.
- [ ] Push notification — receives `new_photo` push when other clique member uploads.
- [ ] CORS — `https://clique-pix.com` web client can hit the API (preflight + actual call). Inspect response headers for `Access-Control-Allow-Origin`.

**App Insights validation:**
```kql
// Confirm requests are flowing to App Insights from the new APIM
requests
| where timestamp > ago(15m)
| where cloud_RoleName contains "apim" or cloud_RoleInstance contains "apim-cliquepix-v2"
| summarize count() by bin(timestamp, 1m)
| render timechart
```

If telemetry isn't flowing, check that the new APIM has the `APPLICATIONINSIGHTS_CONNECTION_STRING` configured (it should, since bicep declares it — but worth verifying).

### Phase 7 — Soak (24-48 hours)

Leave the configuration alone. Monitor App Insights for:
- 4xx / 5xx rate vs. pre-migration baseline (should be similar).
- p50 / p95 / p99 latency on `/api/health`, `/api/auth/verify`, `/api/events/{id}/photos/upload-url`. Expect Basic v2 to be slightly slower than Developer (~10-30 ms higher p50) but more consistent (lower p99).
- Any spike in `requests` with `resultCode != 200` — investigate immediately.

The Developer-tier `apim-cliquepix-002` stays running but receives no traffic. If anything goes wrong, immediately revert (Phase R below).

### Phase 8 — Decommission Developer tier (only after 48h of clean soak)

```bash
# Remove old origin from Front Door first
az afd origin delete \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> \
  --origin-name <OLD_ORIGIN_NAME> \
  --yes

# Then delete the Developer-tier APIM
az apim delete -g rg-cliquepix-prod -n apim-cliquepix-002 --yes
```

Update `Quick Reference — Key Resources` table at the top of this runbook: change `APIM | apim-cliquepix-002` to `apim-cliquepix-v2`. Update the same in any other doc references.

### Phase R — Rollback (if anything goes wrong in Phases 5-8)

In <5 minutes:

```bash
# Flip Front Door weights BACK
az afd origin update --resource-group rg-cliquepix-prod --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> --origin-name <OLD_ORIGIN_NAME> --weight 100

az afd origin update --resource-group rg-cliquepix-prod --profile-name fd-cliquepix-prod \
  --origin-group-name <ORIGIN_GROUP_NAME> --origin-name apim-v2 --weight 0
```

5-minute Front Door propagation, you're back on Developer-tier APIM. Investigate, fix, retry.

The Basic v2 instance can stay provisioned (costs ~$525/month prorated) until you're ready to retry. Or delete it: `az apim delete -g rg-cliquepix-prod -n apim-cliquepix-v2 --yes`.

### Cost during migration window

Both APIM instances running in parallel for ~2-3 days:
- `apim-cliquepix-002` (Developer): ~$50/month → ~$5 prorated for 3 days
- `apim-cliquepix-v2` (Basic v2): ~$525/month → ~$50 prorated for 3 days
- **Total overlap cost: ~$55**

After Phase 8 cleanup, ongoing cost is ~$525/month for Basic v2 alone. The ~$475/month delta from Developer is the SLA + v2 platform.

### Known gotchas captured during this incident

- **Microsoft's `rate-limit` algorithm differs between classic and v2 tiers.** Classic = sliding window, v2 = token bucket. Clique Pix has no rate-limit policies as of 2026-05-05 (incident #6 cleanup), so this is moot for us. If we ever re-add rate-limit policies on Basic v2, expect modestly more burst-friendly behavior than Developer would have given.
- **Backup/restore APIs don't support cross-tier restore** (Developer → Basic v2). The migration approach is bicep redeploy against a new instance, NOT backup/restore.
- **The new APIM gets a different system-assigned managed identity principal ID.** Any RBAC role assignments on the OLD APIM's identity must be re-granted to the NEW one (Phase 3).
- **The Echo API sample bicep resources** are default APIM scaffolding. They redeploy fine but contribute nothing — consider removing them from `bicep/apim/main.bicep` as a separate cleanup PR.
- **`apim-cliquepix-002` is name-locked for ~30 days after deletion.** Don't try to reuse the name. Pick `apim-cliquepix-v2` or whatever new suffix.

---

## Web Client Troubleshooting

### "Web users report empty Cliques / Events / notifications even though mobile shows data"

This class of bug has struck twice during the web-client rollout and is the first thing to check when web and mobile diverge.

1. **Network-tab check**: have the user open DevTools → Network and filter by `api.clique-pix.com`. Look at the Request Headers of any `/api/*` call.
   - **No `Authorization: Bearer …` header present** → the MSAL-singleton wiring in `main.tsx` is broken. See `docs/WEB_CLIENT_ARCHITECTURE.md §4.1`. Check `webapp/src/main.tsx` — `setApiMsalInstance(msalInstance)` must be called after `await msalInstance.initialize()` and before `ReactDOM.createRoot(...).render(...)`. Regression fix was PR #4.
   - **Request returns 200 but response body looks wrong shape** (array where object expected, or vice versa) → the global camelize interceptor or an envelope-unwrap is the likely culprit. See `docs/WEB_CLIENT_ARCHITECTURE.md §6`. Confirm the endpoint module unwraps `{ notifications: [...] }` / `{ photos: [...] }` / `{ videos: [...] }` / `{ messages: [...] }` for the relevant list endpoint. Regression fix was PR #5.
   - **Request returns 401 in a normal session** (not mid-playback SAS expiry) → the MSAL session is bad. `useAuthVerify` should already force `logoutRedirect` on 401 at app mount; if the user is looping through Entra, check for clock skew on their device.

2. **Duplicate-user check** (only if claim-extraction is the cause, very rare): query Postgres for rows where the `email_or_phone` matches the user's login but `external_auth_id` differs from the mobile row. Backend upserts on `external_auth_id`, so a drift would create a second row. No duplicate path has ever been observed in practice since the JWT `sub` claim is stable across MSAL.js and msal_auth for the same Entra user.

### "Web client deploy failed with 'maximum number of staging environments'"

SWA Free tier caps PR preview environments at 3. Every PR creates one. Cleanup is currently manual.

List current staging envs:
```bash
az rest --method GET \
  --uri "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Web/staticSites/swa-cliquepix-prod/builds?api-version=2023-12-01" \
  | grep -oE '"name":\s*"[^"]+"'
```

Delete the staging env for a merged / closed PR by number:
```bash
az rest --method DELETE \
  --uri "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Web/staticSites/swa-cliquepix-prod/builds/<PR_NUMBER>?api-version=2023-12-01"
```

Then `gh run rerun <run-id>` on the failed workflow, or push an empty commit to re-trigger.

Long-term fix: add a cleanup step to `.github/workflows/webapp-deploy.yml` that runs on PR close and deletes the associated staging env. Tracked as a follow-up; not yet implemented.

### "Invite accept on web shows a 404 or 'invalid invite' message"

The web `joinCliqueByCode` URL must be `POST /api/cliques/_/join` (underscore placeholder), NOT `POST /api/cliques/join`. The backend route pattern is `cliques/{cliqueId}/join` — Azure Functions returns 404 if the segment is missing. The handler ignores the path param and resolves the clique from `invite_code` in the body. See `webapp/src/api/endpoints/cliques.ts`.

### "Invite dialog shows 'Generating…' forever, or the Print QR page renders 'undefined'"

Both screens read the backend response using `inviteUrl` / `inviteCode` (camelCase, post-interceptor). If a bad merge reverts to `invite_url` / `invite_code` (snake_case), the values resolve to `undefined`, the QR falls through to the placeholder, and the Print page shows `undefined`. Regression fix was PR #7.

### "Video playback hangs or shows 'Couldn't play this video' after 15+ minutes paused"

Expected behavior — the 15-minute SAS window on HLS segments and the MP4 fallback URL has expired. `<VideoPlayer>` catches the `video.error` event and triggers `recoverFromError()` which re-fetches `/api/videos/:id/playback` for fresh SAS tokens and re-initializes at the saved `currentTime`. Look for `web_playback_sas_recovered` events in App Insights.

If recovery is failing:
```kql
exceptions
| where timestamp > ago(24h)
| where customDimensions.stage == "video_playback_init"
| project outerMessage, customDimensions
```

Most common failure: the video transitioned from `active` back to a non-playable state server-side (deleted, flagged), which returns 404 on `/playback`. Confirm video status in Postgres.

### "Landing page doesn't appear — `clique-pix.com` jumps straight to sign-in"

Almost certainly means the latest deploy hasn't shipped yet. Check:
```bash
curl -s "https://clique-pix.com/" | grep -oE 'assets/index-[A-Za-z0-9_-]+\.js' | head -1
```
Compare to the most recent `webapp-deploy.yml` run's bundle hash on `main`. If they match but the page still redirects, verify `webapp/src/app/router.tsx` has `{ path: '/', element: <LandingPage /> }` as a public route (NOT under the AuthGuard parent).
