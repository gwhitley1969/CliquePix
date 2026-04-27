# Clique Pix — Beta Operations Runbook

**Last Updated:** April 10, 2026

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
| APIM | `apim-cliquepix-002` | Azure Portal → API Management |
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

**Should not happen in beta** — APIM `rate-limit-by-key` was removed on 2026-04-27 (see `apim_policy.xml` in-file comment for the four-incident history). If a 429 surfaces, the source is no longer APIM. Triage:

1. **Check APIM `Requests` metric filtered by `GatewayResponseCode=429`** — should be flat zero. If non-zero, someone re-added a rate-limit policy; revert via the deploy command in `apim_policy.xml`'s comment.
2. **Check Azure Storage `Throttling Errors`** on `stcliquepixprod` — extremely unlikely for beta volumes, but possible if a single blob path is hammered. Storage 429 → `BlobUploadFailure` on the client, surfaced with the Azure error code in the user-visible message.
3. **Check the user's APK version.** If they're on a pre-2026-04-27 APK, the `_friendlyError` for 429 may differ. Updated APKs show a live "Wait Ns" countdown with `Retry-After` parsing and a "Show details" panel covering Dio type / HTTP status / response body. Have them install the latest `app-release.apk`.
4. **Check Front Door** metrics for `PercentageOfClientErrors` → 429 — Standard tier has no built-in rate limit, but a misconfigured WAF rule could in principle return 429. Currently no WAF.

### WorkManager (Layer 4) firing too often

Symptom: `customEvents | where name == "wm_refresh_success"` shows the event >1× per minute when it should fire ~3× per day.

Root cause (fixed 2026-04-27 in `app/lib/features/auth/domain/background_token_service.dart`):
- `Workmanager().registerPeriodicTask(... existingWorkPolicy: ExistingPeriodicWorkPolicy.replace)` re-creates the schedule on every app launch and queues immediate catch-up executions on Android.

Fix shipped in 2026-04-27 APK:
- `existingWorkPolicy: ExistingPeriodicWorkPolicy.keep` preserves the schedule across launches.
- `callbackDispatcher` reads `wm_last_run_at_ms` from SharedPreferences and short-circuits with a `wm_task_skipped_too_soon` telemetry event if last run was < 4 hours ago.

If the symptom recurs on a current APK, check whether `wm_last_run_at_ms` is being written successfully (SharedPreferences encryption issue?) and whether the Workmanager dispatcher is actually being invoked — `[AUTH-LAYER-4]` debug logs should fire on each invocation.

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
