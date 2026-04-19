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
4. Check APIM for rate-limit violations (potential abuse)

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
