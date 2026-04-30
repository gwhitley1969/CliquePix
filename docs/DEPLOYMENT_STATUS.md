# DEPLOYMENT_STATUS.md — Clique Pix v1

Last updated: 2026-04-30 (Real-time event fan-out shipped — Web PubSub `new_event` + FCM fallback + always-on connection lifecycle)

## Real-time event fan-out — `new_event` (2026-04-30)

**Status:** ✅ Code complete on local branch, ✅ migration 011 written, ✅ backend tsc + jest 157/157 green, ✅ flutter analyze 54-issue baseline preserved, ✅ flutter test 68/68 green. **Pending:** migration 011 apply to prod DB → backend deploy → on-device verification → APK build → docs commit.

**What's the user-visible win:** when a clique member creates a new Event, every other clique member sees it appear on their screen with sub-second latency when foregrounded, gets a system notification when backgrounded, and finds the event waiting in their in-app notifications list. Closing-and-reopening the app to "see" the new event is no longer needed. Reported bug filed by @user 2026-04-30 — fix delivers the requested behavior.

**Free incidental win:** the same architectural shift fixes a latent `video_ready` Web PubSub delivery bug. Pre-fix, `video_ready` only reached users on `EventFeedScreen` because the connection was per-DM-screen-only. Post-fix, all signed-in users receive `video_ready` real-time regardless of which screen they're on. No additional code change required for this fix — it's a side-effect of the connection-lifecycle promotion.

**Architecture:** copies the existing `pushVideoReady` pattern (`backend/src/functions/videos.ts:274-339`) for the dual Web PubSub + FCM + in-app notification fan-out. The new piece is making the client Web PubSub connection always-on while signed in (was previously per-DM-screen, only opened when the user navigated to a DM thread).

| Phase | Status | Files |
|---|---|---|
| Migration 011 — widen `notifications.type` CHECK constraint to include `'new_event'` | ✅ Written | `backend/src/shared/db/migrations/011_new_event_notification_type.sql` (new) |
| Backend `pushNewEvent` helper + call site in `createEvent` | ✅ | `backend/src/functions/events.ts` |
| Backend tsc + jest (157/157) | ✅ | — |
| `DmRealtimeService` — added `Stream<NewEventEvent> onNewEvent` + dispatch branch for `type: 'new_event'` | ✅ | `app/lib/features/dm/domain/dm_realtime_service.dart` |
| `RealtimeProviderInvalidator` widget — subscribes to `onNewEvent`, invalidates `allEventsListProvider` + `eventsListProvider(cliqueId)` + `notificationsListProvider`, telemetry `new_event_received` | ✅ | `app/lib/widgets/realtime_provider_invalidator.dart` (new) |
| `ShellScreen` — wraps the navigationShell in `RealtimeProviderInvalidator` so the subscription lives across all 4 bottom-tab branches and out-of-shell screens | ✅ | `app/lib/app/shell_screen.dart` |
| `AuthNotifier` — constructor injection of `DmRealtimeService` + `DmRepository`; `_connectRealtime()` 3-step dance on `_startLifecycle`; `_realtime.disconnect()` on `_stopLifecycle`; `_reconnectRealtimeIfDropped()` runs in parallel with Friday reminder via `Future.wait` on every `AppLifecycleState.resumed` | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| `PushNotificationService` — foreground `onMessage` invalidates events providers when `type: 'new_event'`; `_navigateFromNotification` routes `new_event` taps to `/events/{eventId}` with `new_event_tapped_fcm` telemetry | ✅ | `app/lib/services/push_notification_service.dart` |
| `notifications_screen.dart` — `case 'new_event':` in `_handleNotificationTap` routing to `/events/{eventId}`; new "New Event" icon (event_rounded, electric-aqua → deep-blue gradient) and title in `_iconAndColors` / `_title` | ✅ | `app/lib/features/notifications/presentation/notifications_screen.dart` |
| `flutter analyze`: 54 issues (matches baseline; zero new errors/warnings) | ✅ | — |
| `flutter test`: 68/68 pass (no new tests — orchestration helpers don't get unit tests in this codebase, matches `pushVideoReady` convention) | ✅ | — |
| Docs updated: PRD §5.14, ARCHITECTURE §10 + §12, NOTIFICATION_SYSTEM trigger matrix + new "New Event Real-Time Fan-Out" subsection, CLAUDE.md Push Triggers + Real-Time Feed sections, BETA_TEST_PLAN §7.1, BETA_OPERATIONS_RUNBOOK §7 with 4 new Kusto queries, this entry | ✅ | as listed |
| Migration 011 apply to `pg-cliquepixdb` (prod) | ⏳ Pending | — |
| Backend deploy `func azure functionapp publish func-cliquepix-fresh` | ⏳ Pending | — |
| Backend smoke: `POST /api/cliques/{id}/events` from a test account → confirm `new_event_push_sent` in App Insights with expected `recipientCount` | ⏳ Pending | — |
| APK release build (`flutter clean && flutter pub get && flutter build apk --release`) | ⏳ Pending | — |
| On-device verification per BETA_TEST_PLAN.md §7.1 (Samsung + iPhone, two-account scenario) | ⏳ Pending | — |

**Telemetry events** (App Insights `customEvents`):
- Server: `new_event_push_sent { eventId, cliqueId, recipientCount, webPubSubFailures, fcmFailures }`.
- Client: `new_event_received { eventId, cliqueId }`, `new_event_tapped_fcm { eventId }`, `realtime_connected { reason: 'auth_start' | 'reconnect_on_resume' }`, `realtime_connect_failed { errorCode }`, `realtime_reconnected_on_resume`.

**Deploy order (must be sequential):** migration 011 → backend → APK. Backend deploy is safe before clients update because old clients harmlessly fall through the `type:` switch on `new_event` Web PubSub messages — they keep working as before. APK ship completes the user-visible change.

**Rollback plan:** revert client commit (legacy build still works for everything except real-time event arrival). Backend `pushNewEvent` is best-effort and can be flagged off via env var `DISABLE_NEW_EVENT_PUSH=true` if a problem emerges (one-line guard at the top of the helper — TODO: add this guard if a need arises).

**No new dependencies, no new RBAC, no infrastructure change.** Reuses existing Web PubSub `wps-cliquepix-prod`, FCM credentials, and the same notifications table.

---

## Weekly Friday 5 PM local reminder (2026-04-30)

**Status:** ✅ Code complete, all tests green, release APK built (62.7 MB). On-device verification pending.

**What's live:** every signed-in user gets a recurring weekly local notification at Friday 5:00 PM in their device's local timezone — *"Evening or weekend plans? Don't forget to create an Event and assign a Clique!"* Tap routes to the Home dashboard. Mute via OS Settings → Apps → Clique Pix → Notifications → Reminders channel. Multi-device-tolerant (N devices = N simultaneous fires; matches Duolingo/Strava convention).

**Architecture:** client-only via `flutter_local_notifications.zonedSchedule` with `dayOfWeekAndTime` DST-aware weekly recurrence. No backend, no migration, no FCM, no Web PubSub. The plugin auto-recurs forever after the first scheduled fire. TZ-change recovery (SFO→NYC traveler) handled by an `AppLifecycleService.onResumed` callback that re-arms the schedule when the cached IANA differs from the device's current IANA. State-machine reasons (`cold_start` / `tz_changed` / `os_purged`) drive telemetry. Full design: `docs/NOTIFICATION_SYSTEM.md` "Weekly Friday Reminder" subsection.

| Phase | Status | Files |
|---|---|---|
| New dep `flutter_timezone: ^4.0.0` (resolved 4.1.1) — required to seed `tz.local` from device IANA so DST-correct schedules fire at the right wall-clock | ✅ | `app/pubspec.yaml`, `app/pubspec.lock` |
| `FridayReminderService` — schedule/cancel/state-machine + IANA fallback + `pendingNotificationRequests()` cache check | ✅ | `app/lib/services/friday_reminder_service.dart` (new) |
| `main.dart` — seeds `tz.setLocalLocation` after `tz.initializeTimeZones`; creates second Android channel `cliquepix_reminders` (default importance) alongside `cliquepix_default` | ✅ | `app/lib/main.dart` |
| `PushNotificationService` — `friday_reminder` tap branch → `router.go('/events')` + `friday_reminder_tapped` telemetry; placed before existing event_id/clique_id fallbacks | ✅ | `app/lib/services/push_notification_service.dart` |
| `AuthNotifier._startLifecycle` — schedules the reminder fire-and-forget on `AuthAuthenticated`; `_stopLifecycle` cancels on sign-out / delete-account | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| `AppLifecycleService` — gains `onResumed` callback (auth-independent) so the reminder reschedules on every resume without coupling to the token-refresh path | ✅ | `app/lib/features/auth/domain/app_lifecycle_service.dart` |
| Unit tests — 16 new tests covering `computeNextFriday5pm` across all weekdays + DST spring-forward, `computeReason` state machine, `flutter_timezone` failure fallback, no-op skip path | ✅ | `app/test/friday_reminder_service_test.dart` (new) |
| `flutter analyze`: 54 issues (matches pre-change baseline; zero new errors/warnings) | ✅ | — |
| `flutter test`: 68/68 pass (incl. the 16 new) | ✅ | — |
| Release APK build (`flutter clean && flutter pub get && flutter build apk --release`) | ✅ | `app/build/app/outputs/flutter-apk/app-release.apk` (62.7 MB, +0.2 MB vs. 2026-04-29 baseline) |
| Docs: `PRD.md` §5.14, `ARCHITECTURE.md` §10 + §20 telemetry, `NOTIFICATION_SYSTEM.md` trigger matrix + new "Weekly Friday Reminder" subsection, `CLAUDE.md` Frontend deps + Notification Architecture, `BETA_TEST_PLAN.md`, `BETA_OPERATIONS_RUNBOOK.md` Kusto queries | ✅ | as listed |
| On-device verification (Samsung + iPhone — see `BETA_TEST_PLAN.md` §13 / Friday reminder rows) | ⏳ Pending | — |

**Telemetry events** (visible in App Insights `customEvents`): `friday_reminder_scheduled` { iana, next_fire_at, reason }, `friday_reminder_skipped_tz_unchanged`, `friday_reminder_tz_lookup_failed`, `friday_reminder_tapped`.

**Caught during implementation (DST bug):** `TZDateTime.add(Duration(days: 7))` adds 168 absolute hours, not 7 calendar days — across DST that silently shifts by ±1 hour. Fixed by switching to calendar-day arithmetic via the `TZDateTime` constructor's overflow-day handling (`tz.TZDateTime(loc, n.year, n.month, n.day + 7, 17)`). Caught by the `DST spring-forward` unit test before any device ever ran the code.

**No backend deploy required.** No DB migration. No APIM policy change. No Azure infra change. No web client change (CLAUDE.md: "no Web Push in v1"). Pure mobile feature.

**Operational note:** if a future developer wonders "can we use `zonedSchedule` for X?" — the rule is in `CLAUDE.md`'s Notification Architecture section: **`zonedSchedule` is permitted ONLY for displaying static recurring reminders, never for executing code.** The previous Layer-2 token-refresh `zonedSchedule` was deleted because that primitive does not run code at fire time. The Friday reminder is the only such notification in v1 and the architectural template for any future reminder type.

---

## Earlier history

(Last updated before reminder: 2026-04-29 — APIM Product-scope rate-limit + quota removed from "starter" — fifth and (finally) actual root cause of the recurring upload 429; client silent-retry safety net added)

## APIM Product-scope `rate-limit` + `quota` removal — incident #5 (2026-04-29)

**Status:** ✅ APIM "starter" product policy cleaned in production; ✅ 429 metric alert wired; ✅ client-side silent-retry shipped to repo (APK build pending).

**What changed and why.** A brand-new test user hit HTTP 429 on their FIRST upload attempt with the body `{statusCode: 429, message: "Rate limit is exceeded. Try again in 38 seconds."}`. The 2026-04-27 cleanup had only addressed the **API**-scope policy. APIM has FOUR policy scopes (Global → Product → API → Operation). A Phase 0+A audit found APIM's **default starter Product policy** — created automatically when the service was first provisioned and never touched — still contained `<rate-limit calls="5" renewal-period="60" />` AND `<quota calls="100" renewal-period="604800" />` (5/min + 100/week). New users auto-subscribed to the `starter` product hit the 5/min cap during their first auth-verify + list-events + list-cliques + get-upload-url chain.

| Change | Status | Files |
|---|---|---|
| APIM `starter` product policy: PUT clean `<base />`-only policy. Removed both `<rate-limit>` and `<quota>` | ✅ Deployed 2026-04-29 via `az rest PUT` | (live APIM service) |
| APIM `unlimited` product: confirmed already had no policy (404) | ✅ No-op | — |
| APIM Global scope: confirmed already empty | ✅ No-op | — |
| APIM Operation scope (all 7 operations): confirmed no policies (404) | ✅ No-op | — |
| `apim_policy.xml`: in-file comment now warns about ALL FOUR scopes (was API-scope-only); incident #5 added to history | ✅ | `apim_policy.xml` |
| Azure Monitor metric alert `apim-429-detected` (count Requests > 0 where GatewayResponseCode includes 429, 5-min window, 1-min eval) | ✅ Created 2026-04-29 | (Azure Monitor) |
| New utility `silentRetryOn429<T>` — wraps a Future-returning call with one-shot 429 silent retry, honors Retry-After header (capped 60s), per-device 5-min cooldown via SharedPreferences | ✅ | `app/lib/core/utils/upload_url_silent_retry.dart` |
| Photo upload: `camera_capture_screen` wraps `getUploadUrl` with silent retry. User sees no error banner on first 429 — just a slightly longer "Getting upload URL..." progress phase. Telemetry: `photo_upload_url_429_silenced` / `_silent_retry_succeeded` / `_silent_retry_failed` | ✅ | `app/lib/features/photos/presentation/camera_capture_screen.dart` |
| Video upload: `VideosRepository.uploadVideo` accepts an optional `wrapGetUploadUrl` callback so the screen can supply silent-retry without coupling the repo to telemetry/SharedPreferences. `video_upload_screen` passes `silentRetryOn429`. Same telemetry shape with `video_*` prefix | ✅ | `app/lib/features/videos/domain/videos_repository.dart`, `app/lib/features/videos/presentation/video_upload_screen.dart` |
| `flutter analyze`: 54 issues (matches pre-change baseline; zero new errors/warnings) | ✅ | — |
| Release APK build (`flutter clean && flutter pub get && flutter build apk --release`) | ⏳ Pending | `app/build/app/outputs/flutter-apk/app-release.apk` |
| On-device verification (affected test user retries upload) | ⏳ Pending | — |

**Backup of prior live policies:** `C:\Users\genew\AppData\Local\Temp\apim-bak-20260429-1432\` — contains `global.xml`, `api.xml`, `product-starter.xml` (with the 5/min + 100/week rules), `product-starter-after.xml` (the clean replacement), and `product-clean.json` (the body used in the PUT).

**Operational note for future maintainers:**
- When an APIM 429 alert fires, run the Phase 0+A audit script in `docs/BETA_OPERATIONS_RUNBOOK.md` §2 BEFORE anything else. It enumerates all four scopes; the clean state is "no flagged files."
- Do NOT re-add `<rate-limit>`, `<rate-limit-by-key>`, or `<quota>` at ANY scope until APIM is migrated to Standard v2 (distributed cache + SLA). The 5-incident history in `apim_policy.xml`'s in-file comment is canonical.
- The client-side `silentRetryOn429` is a safety net, not a substitute for the APIM cleanup. It silences ONE 429 per 5-min window per device; a sixth incident with sustained 429s would still surface to users.

---



## Organizer media moderation — `canDeleteMedia` (2026-04-28)

**Status:** ✅ backend deployed to prod; ✅ release APK built (62.5 MB). Web SWA deploy pending merge to `main`. On-device verification (Samsung + iPhone) pending.

**What changed and why.** Until now, only the uploader could delete a photo or video. If a clique member uploaded inappropriate content into an event and refused to remove it, the event organizer had no recourse short of deleting the entire event (which destroyed everyone else's content). The new authorization model accepts EITHER the uploader OR the event organizer (`events.created_by_user_id`) on `DELETE /api/photos/{id}` and `DELETE /api/videos/{id}`. Random clique members continue to receive HTTP 403. Uploader takes precedence when both apply, so an organizer deleting their own upload is logged as a self-delete.

| Phase | Files | Status |
|---|---|---|
| Backend: `canDeleteMedia` helper + 8 unit tests | `backend/src/shared/utils/permissions.ts`, `backend/src/__tests__/permissions.test.ts` | ✅ |
| Backend: `deletePhoto` enriched SELECT (JOIN events) + role-aware telemetry | `backend/src/functions/photos.ts:488-548` | ✅ |
| Backend: `deleteVideo` enriched SELECT + role-aware telemetry (no `status` filter preserved) | `backend/src/functions/videos.ts:758-810` | ✅ |
| Backend: tsc green | — | ✅ |
| Backend: jest 157/157 green (was 149 before; +8 new) | — | ✅ |
| Mobile: shared `deleteDialogCopy` helper for self-vs-organizer copy | `app/lib/widgets/confirm_destructive_dialog.dart` | ✅ |
| Mobile: `MediaOwnerMenu` rename `isOwner→canDelete`; `isOrganizerDeletingOthers` prop drives Remove vs Delete copy | `app/lib/widgets/media_owner_menu.dart` | ✅ |
| Mobile: `PhotoCardWidget` + `VideoCardWidget` accept `eventCreatedByUserId`; compute `canDelete = isUploader \|\| isOrganizerDeletingOthers` | `app/lib/features/photos/presentation/photo_card_widget.dart`, `app/lib/features/videos/presentation/video_card_widget.dart` | ✅ |
| Mobile: `EventFeedScreen` threads `eventCreatedByUserId` from `EventDetailScreen` | `app/lib/features/photos/presentation/event_feed_screen.dart`, `app/lib/features/events/presentation/event_detail_screen.dart` | ✅ |
| Mobile: `PhotoDetailScreen` + `VideoPlayerScreen` watch `eventDetailProvider`, gate Delete on `canDelete`, branch dialog body | `app/lib/features/photos/presentation/photo_detail_screen.dart`, `app/lib/features/videos/presentation/video_player_screen.dart` | ✅ |
| Mobile: `flutter analyze` 54 issues (was 55; same pre-existing baseline; zero new errors/warnings introduced) | — | ✅ |
| Web: `MediaCard` accepts `eventCreatedByUserId`; computes `canDelete`; branches `<ConfirmDestructive>` copy + success toast | `webapp/src/features/photos/MediaCard.tsx` | ✅ |
| Web: `MediaFeed` + `EventDetailScreen` thread the prop | `webapp/src/features/photos/MediaFeed.tsx`, `webapp/src/features/events/EventDetailScreen.tsx` | ✅ |
| Web: `vite build` green (2164 modules, bundle budget intact) | — | ✅ |
| Docs: PRD §5.2 + ARCHITECTURE §6 + CLAUDE.md Security Rules + BETA_TEST_PLAN §4/§5/§12.5 + this file | as listed | ✅ |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | — | ✅ Deployed 2026-04-28 — health endpoints 200 via direct (`func-cliquepix-fresh.azurewebsites.net`) AND Front Door (`api.clique-pix.com`) |
| Release APK built (`flutter clean && flutter pub get && flutter build apk --release`) | `app/build/app/outputs/flutter-apk/app-release.apk` (62.5 MB) | ✅ Built 2026-04-28 |
| Mobile on-device verification (Samsung + iPhone, 3-account scenario per `BETA_TEST_PLAN.md` §4 + §5) | — | ⏳ Pending |
| Web SWA deploy (auto via GH Actions on merge to `main`) | — | ⏳ Pending |
| App Insights: organizer-abuse alert wired (Kusto query B in plan) | — | ⏳ Pending |

**Telemetry shape change (additive — backward compatible):**
- `photo_deleted` / `video_deleted` gain three new dimensions: `deleterRole` ∈ `'uploader' | 'organizer'`, `uploaderId` (UUID or `''` if account deleted), `eventOrganizerId` (UUID or `''` if account deleted)
- `userId` (the deleter) remains unchanged
- Existing Kusto queries continue to function; new queries can filter on `tostring(customDimensions.deleterRole) == "organizer"` for moderation auditing

**Deploy order:** backend → mobile + web (parallel). Backend first is safe because pre-existing clients ignore the new capability (the menu just stays hidden for organizers). Once backend is live, organizers gain the ability via mobile/web ship.

**No DB migration.** `events.created_by_user_id` already exists. The handler enriches its SELECT with a JOIN against `events`. No schema change.

**Operational note:** Both `events.created_by_user_id` and `photos.uploaded_by_user_id` are nullable since migration 004 (ON DELETE SET NULL on user account deletion). The `canDeleteMedia` helper guards against nullable comparisons; if both IDs are null no one can delete the media (the cleanup timer reaps it on event expiry — correct behavior).

**Out of scope (future):** notifying the original uploader when an organizer removes their content; extending moderation to clique owners; bulk moderation tools; appeals workflow.

---

## APIM rate-limit removal + client traffic reduction (2026-04-27)

**Status:** APIM policy deployed (no rate-limit-by-key on any path); client APK built with WorkManager + polling + retry-interceptor fixes.

**What changed and why.** Four consecutive user-blocking 429 incidents from APIM `rate-limit-by-key` on the Developer-tier (single in-memory cache, no SLA) made the gateway-side rate limit a net negative for beta. Each fix attempt — bumping 120 → 300 → 600/min, adding bypass paths, versioning the counter cache key with `v2:` prefix — produced a *new* 429 within minutes. Removing the policy entirely is the only foolproof guarantee that uploads will never 429. Abuse protection now lives at the application layer (JWT auth, event-membership checks, User Delegation SAS expiry, orphan cleanup timer).

| Change | Status | Files |
|---|---|---|
| APIM policy: removed `<rate-limit-by-key>` (both global 600/min + avatar sub-limit). Kept `<base />` + `<cors>`. | ✅ Deployed 2026-04-27 via `az rest PUT` | `apim_policy.xml` (with full incident-history comment) |
| Flutter: `RetryInterceptor` never retries 429s; honors `Retry-After` header (capped 30s); `maxRetries: 3 → 1` to reduce amplification on connection errors | ✅ | `app/lib/services/retry_interceptor.dart` |
| Flutter: WorkManager `existingWorkPolicy: replace → keep` + 4-hour `wm_last_run_at_ms` SharedPreferences guard inside `callbackDispatcher` (telemetry confirmed it was firing 6×/min instead of 1×/8h) | ✅ | `app/lib/features/auth/domain/background_token_service.dart` |
| Flutter: new `LifecycleAwarePollerMixin` — pauses 30 s polling timers when app is paused/inactive/hidden, restarts (with one-shot refresh) on resume | ✅ | `app/lib/core/utils/lifecycle_aware_poller_mixin.dart` |
| Flutter: adopted by `event_feed_screen`, `cliques_list_screen`, `clique_detail_screen` | ✅ | as listed |
| Flutter: `camera_capture_screen` enriched 429 handler — parses `Retry-After`, shows live "Wait Ns" countdown on retry button + Upload button (disabled during cooldown), expandable "Show details" diagnostic panel covering Dio type / status / body / runtime type | ✅ | `app/lib/features/photos/presentation/camera_capture_screen.dart` |
| Avatar crop UX fix — dark `UCropTheme` + `hideBottomControls: true` + first-time `_showCropHint` AlertDialog (gated on `avatar_crop_hint_shown` SharedPreferences key) | ✅ | `app/android/app/src/main/res/values/styles.xml`, `AndroidManifest.xml`, `avatar_repository.dart`, `avatar_editor_screen.dart` |

**Deploy artifacts:** `app/build/app/outputs/flutter-apk/app-release.apk` (62.5 MB, debug-signed). Backend not redeployed — APIM is gateway-only.

**Operational note for future maintainers:** do **not** re-add `rate-limit-by-key` to `apim_policy.xml` until APIM is migrated off the Developer tier. The policy file's in-line comment lists the four-incident history reproducibly. Standard v2 has a distributed rate-limit cache and an SLA — the right place to revisit gateway-side rate limiting.

---

## Avatars v1 — Profile Pictures (2026-04-24)

**Status:** backend deployed to prod, web + mobile pending ship.

**What's live:**
- Migration 009 (silent-push activity tracking) + Migration 010 (avatars) applied to `pg-cliquepixdb`
- Backend deployed to `func-cliquepix-fresh` — health endpoint 200 via Function App URL AND `api.clique-pix.com` (Front Door → APIM path)
- All 5 avatar endpoints registered: `POST /api/users/me/avatar/upload-url`, `POST /api/users/me/avatar` (confirm), `DELETE /api/users/me/avatar`, `PATCH /api/users/me/avatar/frame`, `POST /api/users/me/avatar-prompt`
- Azure Blob CORS verified — `https://clique-pix.com` + `http://localhost:5173` allowed on `GET`, `PUT`, `HEAD`, `OPTIONS` with 1h preflight cache

**Verified before cutover:**
- Backend 149/149 tests green (134 existing + 15 new `avatarEnricher` tests)
- `npm run build` (tsc) green — 5 pre-deploy type errors caught and fixed (trackEvent number→string, PhotoWithUrls/VideoWithUrls avatar fields, events enricher index signature)
- Flutter analyze 55 issues (was 61, all remaining pre-existing info-level lints; no errors/warnings introduced by avatar work)
- Web `vite build` green — 2164 modules transformed, no TypeScript errors, bundle budget intact (initial JS ≤ 400 KB / 137 KB gzip)

**Pending:**

Adds user-uploadable headshots that replace the initials-in-a-gradient-ring fallback everywhere (Profile hero, photo/video feed cards, clique member lists, DM threads + chat headers). Brand-new users see a branded welcome prompt on first sign-in — three choices (Yes / Maybe Later / No Thanks) with server-persisted state so the decision survives reinstall and is honored across mobile + web.

| Phase | Status | Files |
|---|---|---|
| Migration 010 (`avatar_blob_path`, `avatar_thumb_blob_path`, `avatar_updated_at`, `avatar_frame_preset`, `avatar_prompt_dismissed`, `avatar_prompt_snoozed_until`) | ✅ Applied 2026-04-24 | `backend/src/shared/db/migrations/010_user_avatars.sql` |
| Backend: `avatarEnricher.ts` + `buildAuthUserResponse` + `shouldPromptForAvatar` | ✅ Code done + 15 unit tests | `backend/src/shared/services/avatarEnricher.ts`, `backend/src/__tests__/avatarEnricher.test.ts` |
| Backend: `avatars.ts` — 5 endpoints (upload-url / confirm / delete / frame / avatar-prompt) | ✅ | `backend/src/functions/avatars.ts` |
| Backend: `authMiddleware` SELECT adds avatar columns; `authVerify` + `getMe` emit enriched shape incl. `should_prompt_for_avatar`; `deleteMe` cleans avatar blobs | ✅ | `backend/src/shared/middleware/authMiddleware.ts`, `backend/src/functions/auth.ts` |
| Backend: 14 handler propagation (photos, videos, events, cliques, dm) with `enrichUserAvatar` helper | ✅ | `backend/src/functions/{photos,videos,events,cliques,dm}.ts` |
| ~~Backend: APIM per-IP 10/min sub-limit on avatar sub-paths~~ — superseded by 2026-04-27 rate-limit removal (above) | ✅ then ❌ removed | `apim_policy.xml` |
| Flutter: `AvatarWidget` extended (thumbUrl / framePreset / cacheKey, size-aware URL selection) | ✅ | `app/lib/widgets/avatar_widget.dart` |
| Flutter: `UserModel` + 5 response models carry avatar denorm fields | ✅ | `app/lib/models/*.dart` |
| Flutter: avatar feature (api, repo, picker sheet, editor, welcome prompt, animated empty-state, first-visit hint) | ✅ | `app/lib/features/profile/**` |
| Flutter: `image_cropper` + `confetti` added to pubspec; UCropActivity declared in AndroidManifest | ✅ | `app/pubspec.yaml`, `app/android/app/src/main/AndroidManifest.xml` |
| Flutter: `AuthNotifier.updateUserAvatar` (pure state swap, no token refresh) | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| Flutter: 5 AvatarWidget call sites threaded (photo_card, video_card, dm_thread_list, dm_chat, local_pending_video) | ✅ | as listed |
| Flutter: Profile screen tappable avatar + welcome prompt on Home initState | ✅ | `app/lib/features/profile/presentation/profile_screen.dart`, `app/lib/features/home/presentation/home_screen.dart` |
| Web: `Avatar.tsx` extended with imageUrl / thumbUrl / framePreset / cacheBuster | ✅ | `webapp/src/components/Avatar.tsx` |
| Web: `AvatarEditor` (react-easy-crop + filter/frame) + `AvatarWelcomePromptModal` + `AvatarWelcomePromptGate` + `useAvatarUpload` hook | ✅ | `webapp/src/features/profile/**` |
| Web: `ProfileScreen` tappable avatar with confetti on first upload | ✅ | `webapp/src/features/profile/ProfileScreen.tsx` |
| Web: `MediaCard` passes uploader avatar fields to Avatar | ✅ | `webapp/src/features/photos/MediaCard.tsx` |
| Web: `react-easy-crop` + `canvas-confetti` added to package.json | ✅ | `webapp/package.json` |
| Docs | ✅ | `docs/PRD.md` §5.13, `docs/ARCHITECTURE.md` users table + blob paths, `docs/CLAUDE.md` avatar pipeline, `docs/BETA_TEST_PLAN.md` §10, `docs/WEB_CLIENT_ARCHITECTURE.md` avatar section, this file |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | ✅ Shipped 2026-04-24 | 45 functions deployed (was 40 pre-avatar) |
| Azure Blob CORS verification (`GET`+`PUT` from `clique-pix.com`) | ✅ Verified 2026-04-24 | Already configured from event-media playback rollout; no change needed |
| Web client deploy (auto-deploys from `main` via GH Actions → SWA) | ⏳ Pending `main` merge | See `.github/workflows/swa-deploy.yml` |
| Mobile APK build + on-device verification (Samsung + iPhone) | ⏳ Not started | See BETA_TEST_PLAN.md §10 (13 new avatar test rows) |

Deploy order executed: migration 009 → migration 010 → backend → (CORS verified) → web + mobile pending ship. Legacy mobile clients ignore the new response fields and keep rendering initials — no version lockstep required.


## Entra Refresh-Token Defense — Silent Push Edition (2026-04-19)

**Status:** backend shipped 2026-04-24 alongside Avatars v1 (Migration 009 + the `avatarEnricher`/avatar endpoints deployed in the same `func publish`). Client-side silent-push plumbing is code-complete on `main` but hasn't been rolled out via a mobile build yet — on-device verification per `ENTRA_REFRESH_TOKEN_WORKAROUND.md` "Verifying in production" is still pending.

Re-architected the 5-layer Entra External ID 12-hour refresh-token defense after an audit revealed every service was dead code — `AuthRepository` took `alarmRefreshService` and `backgroundTokenService` as optional constructor params and `authRepositoryProvider` never supplied them, so every `?.` callsite was a silent no-op. `AppLifecycleService` and `BatteryOptimizationService` were never instantiated; `WelcomeBackDialog.show()` had no caller; `BackgroundTokenService.callbackDispatcher` was a `TODO` that always returned `true` without calling MSAL; `main.dart:85` filtered the `TOKEN_REFRESH_TRIGGER` notification payload but never triggered a refresh. The original Layer 2 (`flutter_local_notifications.zonedSchedule`) was architecturally flawed — it only displays a notification, it does not execute code; silent `Importance.min` notifications the user never tapped refreshed nothing.

Replaced Layer 2 with server-triggered silent FCM data pushes (Microsoft's own documented pattern in Azure Communication Services → "Solution 2: Remote Notification"):

| Layer | Mechanism | Change |
|---|---|---|
| 1 | Battery-optimization exemption | Wired — called from `HomeScreen.initState` |
| 2 | **Server silent push** (NEW) | `refreshTokenPushTimer` (backend) + `_firebaseMessagingBackgroundHandler` (client) |
| 3 | Foreground refresh on resume | Wired — `AppLifecycleService.start()` called on `AuthAuthenticated`, `stop()` on sign-out |
| 4 | WorkManager (Android) | Real MSAL refresh in isolate now implemented (no more `TODO`) |
| 5 | Welcome Back dialog | New `AuthReloginRequired` state; `LoginScreen` shows `WelcomeBackDialog` via `ref.listen`; `checkAuthStatus` routes cold-start after 12h to this path |

| Phase | Status | Files |
|---|---|---|
| Migration 009 (`last_activity_at` + `last_refresh_push_sent_at`) | ✅ Applied 2026-04-24 | `backend/src/shared/db/migrations/009_user_activity_tracking.sql` |
| Backend: `authMiddleware` last-activity write + `verifyJwtAllowExpired` | ✅ Code done | `backend/src/shared/middleware/authMiddleware.ts` |
| Backend: `fcmService` silent-push support (`FcmMessage.silent`, `sendSilentToMultipleTokens`) | ✅ Code done + 7 unit tests | `backend/src/shared/services/fcmService.ts`, `backend/src/__tests__/fcmService.test.ts` |
| Backend: `refreshTokenPushTimer` (CRON `0 7,22,37,52 * * * *`) | ✅ Code done | `backend/src/functions/timers.ts` |
| Backend: `POST /api/telemetry/auth` endpoint | ✅ Code done | `backend/src/functions/telemetry.ts` |
| Client: `MsalConstants` extracted (isolate-safe MSAL config) | ✅ | `app/lib/core/constants/msal_constants.dart` |
| Client: `AuthReloginRequired` state + `checkAuthStatus` cold-start recovery | ✅ | `app/lib/features/auth/domain/auth_state.dart`, `auth_providers.dart` |
| Client: `AuthRepository` rewired — `alarmRefreshService` deleted, `refreshTokenDetailed()` added | ✅ | `app/lib/features/auth/domain/auth_repository.dart` |
| Client: `BackgroundTokenService.callbackDispatcher` — real MSAL refresh in isolate | ✅ | `app/lib/features/auth/domain/background_token_service.dart` |
| Client: `AppLifecycleService` — `pending_refresh_on_next_resume` flag + telemetry | ✅ | `app/lib/features/auth/domain/app_lifecycle_service.dart` |
| Client: wiring in `auth_providers.dart` — every service now instantiated | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| Client: `_firebaseMessagingBackgroundHandler` silent-push handler | ✅ | `app/lib/main.dart` |
| Client: `PushNotificationService` foreground `type: 'token_refresh'` branch | ✅ | `app/lib/services/push_notification_service.dart` |
| Client: `TelemetryService` (Dio + SharedPreferences ring buffer + isolate drain) | ✅ | `app/lib/services/telemetry_service.dart` |
| Client: Battery-exempt dialog wired in `HomeScreen.initState` | ✅ | `app/lib/features/home/presentation/home_screen.dart` |
| Client: Token Diagnostics screen + tap-7-times unlock in Profile | ✅ | `app/lib/features/profile/presentation/token_diagnostics_screen.dart`, `profile_screen.dart` |
| Client: Dead file deleted | ✅ | `app/lib/features/auth/domain/alarm_refresh_service.dart` removed |
| Docs | ✅ | `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` rewritten, `CLAUDE.md` §"Entra External ID — Known Bug" updated, this file, `docs/BETA_OPERATIONS_RUNBOOK.md` troubleshooting section added |
| On-device verification (Samsung + iPhone) | ⏳ Not started | See test plan in ENTRA_REFRESH_TOKEN_WORKAROUND §Verifying in production |

Deploy order: migration 009 → backend → client. Backend silent-push path must be live before clients start enforcing the new flow.

## Video v1 Status

## Video v1 Status

**Branch:** `feature/video` — ready for on-device verification, pending merge to `main`

| Phase | Status | Commit |
|---|---|---|
| 1. Database migration (007 — media_type + video columns) | ✅ Applied to production | `fe3e69f` |
| 2. Infrastructure (Log Analytics, ACR Standard, Container Apps Environment+Job, Storage Queue, RBAC, Budget) | ✅ Provisioned in `rg-cliquepix-prod` | `8e569ab`, `343d893` |
| 3. Transcoder container (Dockerfile + Node.js runner + FFmpeg) | ✅ v0.1.2 deployed to `cracliquepix.azurecr.io` | `a6a9930`, `9db5bad` |
| 4. Backend Function endpoints (10 new routes) | ✅ Deployed to `func-cliquepix-fresh` | `552cb60`, `9db5bad` |
| 5. Backend integration test (E2E with real test video) | ✅ All 3 attempts passed after 2 bugs fixed | `9db5bad` |
| 6. Flutter frontend (11 new files, 11 modified) | ✅ Compiles, debug APK builds successfully | `45f5baf` |
| 7. Polish + on-device testing + merge to main | ⏳ In progress — manual testing required before merge | — |

**See also:**
- `docs/VIDEO_ARCHITECTURE_DECISIONS.md` — 8 architecture decisions + 7 product Q&A
- `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` — Azure resources runbook (as-built)
- `docs/CliquePix_Video_Feature_Spec.md` — original generic feature spec
- `docs/VIDEO_V1_TESTING_CHECKLIST.md` — manual on-device testing checklist (Phase 7)

---

## Pre-existing v1 Status (photos, cliques, events, DMs)

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Migration (002_member_joined_notification.sql) | Done | Added `member_joined` to notifications type CHECK constraint (run 2026-03-31) |
| Migration (003_event_deleted_notification.sql) | Done | Added `event_deleted` to notifications type CHECK constraint (run 2026-04-03) |
| Migration (004_user_delete_set_null.sql) | Done | Made `created_by_user_id` / `uploaded_by_user_id` nullable with ON DELETE SET NULL (run 2026-04-03) |
| Shared models (8 files) | Done | User, Clique, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | Code reviewed + 49 issues fixed |
| Auth middleware (JWT via JWKS) | Done | Uses typed errors (UnauthorizedError, NotFoundError) |
| Error handler middleware | Done | Correlation IDs via invocationId |
| Auth functions (verify, getMe, deleteMe) | Done | `deleteMe` cleans up blobs, sole-owner cliques, user record |
| Cliques functions (8 endpoints) | Done | joinClique sends FCM push; `removeMember` endpoint for owner to remove members |
| Events functions (4 endpoints) | Done | Includes `deleteEvent` for organizer-initiated deletion |
| Photos functions (5 endpoints) | Done | Validates via blob properties, async thumbnail gen |
| Reactions functions (2 endpoints) | Done | Static imports, consistent telemetry keys |
| Notifications functions (5 endpoints) | Done | Includes `deleteNotification` and `clearNotifications` |
| Timer functions (3 timers) | Done | Deduplication on expiring notifications |
| Health endpoint | Done | Standard response envelope |
| npm dependencies installed | Done | |

### Flutter Mobile App (Dart)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (pubspec.yaml, analysis_options) | Done | Flutter 3.35.5, Dart 3.9.2 |
| Native scaffolding (Android/iOS) | Done | `flutter create` with org `com.cliquepix`; Android package `com.cliquepix.clique_pix`, iOS bundle ID `com.cliquepix.app` (changed from flutter create default `com.cliquepix.cliquePix`) |
| Design system (colors, gradients, typography, theme) | Done | Dark theme throughout, uses `withValues(alpha:)` (Flutter 3.27+) |
| Constants (endpoints, app constants, environment) | Done | Domain: `clique-pix.com` |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Event-first flow, 4 tabs (Home/Cliques/Notifications/Profile), auth guard with redirect preservation for invite deep links |
| API client (Dio + 3 interceptors) | Done | Auth interceptor uses parent Dio for retry |
| Token storage service | Done | Refresh callback mechanism wired to MSAL |
| Storage service (save to gallery + share + batch download) | Done | Single photo/video save, unified batch download (photos + videos) with progress, share via temp file |
| Deep link service | Done | Host: clique-pix.com, initialized in app.dart via ConsumerStatefulWidget |
| Push notification service | Done | FCM token registration + refresh; foreground display via `flutter_local_notifications`; background/terminated tap navigation; static callback for local notification taps |
| Shared widgets (7 widgets) | Done | Gradient-ringed avatars, dark-themed bottom nav with gradient icons |
| Data models (5 models) | Done | PhotoModel with resilient num/string parsing, EventModel with cliqueName/memberCount |
| Auth feature (MSAL integration) | Done | `msal_auth` 3.3.0, custom API scope, auto-login on startup, MSAL error recovery, dismiss button |
| 5-layer token refresh defense | Done | All layers wired; loginHint threaded through Layer 5 |
| Cliques feature (API, repository, providers, 6 screens) | Done | Dark theme, gradient-bordered cards, gradient-ringed avatars, labeled "Create Clique" FAB, pull-to-refresh + 30s polling on list and detail screens, JoinCliqueScreen with dark theme |
| Events feature (API, repository, providers, 4 screens) | Done | Event-first flow, events home screen, dark-themed event detail with hero header, labeled "Create Event" FAB, `listAllEvents` backend endpoint, event cards show photo + video counts, `Wrap`-based layout handles large system font sizes without overflow |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | `pro_image_editor` for crop/draw/stickers/filters, prominent "Upload to Event" button, step-by-step progress overlay, `uploaded_by_name` in responses, multi-select photo download with progress, debug logging throughout pipeline |
| Notifications feature (API, repository, providers, 1 screen) | Done | Dark theme, colored icon badges, unread/read styling, `member_joined` type with clique navigation |
| Profile feature (1 screen) | Done | Dark theme, gradient profile card, grouped settings with gradient icons, Privacy Policy + Terms of Service open `clique-pix.com` in-app browser via `url_launcher` |
| App entry point (main.dart) | Done | Firebase, timezone, WorkManager, local notifications plugin (top-level), `cliquepix_default` channel creation, Android 13+ permission request, FCM `onMessage` foreground listener, background message handler |
| All API providers wired to ApiClient | Done | No UnimplementedError providers |
| App launcher icon | Done | Clique Pix camera logo at all Android densities |
| Login screen | Done | Dark gradient, animated glowing logo, slide-in animations |
| App-wide dark theme | Done | `AppTheme.dark` applied globally in app.dart; all screens use consistent dark (#0E1525) background with gradient accents |
| Home screen dashboard | Done | State-aware: brand new, has cliques, active events, expired events; How It Works card, clique quick-start chips, active event cards with countdown timers |
| Android manifest | Done | Permissions, App Links, FCM, MSAL BrowserTabActivity |
| iOS Info.plist | Done | Camera/photo permissions, background modes, MSAL URL schemes |
| Firebase config (Android) | Done | `google-services.json` placed in `android/app/` |
| Firebase config (iOS) | Done | `GoogleService-Info.plist` placed in `ios/Runner/` |

### Website (clique-pix.com)

| Component | Status | Notes |
|-----------|--------|-------|
| Landing page (index.html) | Done | Brand design, feature highlights, download CTAs |
| Privacy policy (privacy.html) | Done | Photo + video + DM coverage, 14 sections, Xtend-AI LLC, NC jurisdiction, effective April 13, 2026 |
| Terms of service (terms.html) | Done | Photo + video + DM coverage, 16 sections, effective April 13, 2026 |
| Invite landing page (invite.html) | Done | Dark-themed, platform detection, intent:// for Android, app store buttons, OG meta tags |
| Static Web App config | Done | MIME types for well-known files, security headers, `/invite/*` rewrite to invite.html |
| Well-known files | Done | apple-app-site-association (Team ID: `4ML27KY869`) + assetlinks.json (debug SHA256 fingerprint) |
| Azure Static Web App | Done | `swa-cliquepix-prod`, Free tier, redeployed 2026-03-31 |
| Custom domains | Done | `clique-pix.com` (apex) + `www.clique-pix.com`, managed SSL |

### Documentation

| Component | Status | Notes |
|-----------|--------|-------|
| .gitignore | Done | Firebase admin SDK key pattern added |
| ARCHITECTURE.md | Done | Domain corrected to clique-pix.com |
| PRD.md | Done | |
| CLAUDE.md | Done | Domain corrected, PostgreSQL updated to pg-cliquepixdb |
| ENTRA_REFRESH_TOKEN_WORKAROUND.md | Done | |

---

## Azure Infrastructure Status

### All Resources (in `rg-cliquepix-prod`)

| Resource | Name | Location | Status |
|----------|------|----------|--------|
| Resource Group | `rg-cliquepix-prod` | eastus | Ready |
| Log Analytics | `log-cliquepix-prod` | eastus | Ready |
| Application Insights | `appi-cliquepix-prod` | eastus | Ready (workspace-based) |
| Function App | `func-cliquepix-fresh` | eastus | Ready — 39 functions deployed (incl. 7 DM endpoints) |
| Storage Account | `stcliquepixprod` | eastus | Ready — `photos` container, blob public access disabled |
| PostgreSQL | `pg-cliquepixdb` | eastus2 | Ready — v18, `cliquepix` DB with 10 tables (incl. `event_dm_threads`, `event_dm_messages`) |
| Key Vault | `kv-cliquepix-prod` | eastus | Ready — `pg-connection-string` + `fcm-credentials` + `web-pubsub-connection-string` stored |
| API Management | `apim-cliquepix-002` | eastus | Ready — Developer SKU, API imported. **NO rate-limit-by-key** as of 2026-04-27 (see incident history in `apim_policy.xml`); CORS is the only inbound policy |
| Front Door | `fd-cliquepix-prod` | global | Ready — Standard SKU (no WAF) |
| Static Web App | `swa-cliquepix-prod` | eastus2 | Ready — clique-pix.com + www |
| DNS Zone | `clique-pix.com` | global | Ready — api CNAME, apex ALIAS, www CNAME, TXT validation |
| Web PubSub | `wps-cliquepix-prod` | eastus | Ready — Standard S1, hub: `cliquepix` |
| Entra External ID | `cliquepix.onmicrosoft.com` | — | Ready — app registered, 3 identity providers |

### Deleted Resources

| Resource | Name | Reason |
|----------|------|--------|
| PostgreSQL | `pg-cliquepix` | Replaced by `pg-cliquepixdb` (v18) |

### RBAC Role Assignments (Function App managed identity)

| Role | Scope | Status |
|------|-------|--------|
| Storage Blob Data Contributor | `stcliquepixprod` | Assigned |
| Storage Blob Delegator | `stcliquepixprod` | Assigned |
| Key Vault Secrets User | `kv-cliquepix-prod` | Assigned |

### Traffic Path (verified working)

```
Flutter App → Front Door (fd-cliquepix-prod) → APIM (apim-cliquepix-002) → Azure Functions (func-cliquepix-fresh) → PostgreSQL / Blob Storage
```

Health endpoint confirmed at:
- `https://func-cliquepix-fresh.azurewebsites.net/api/health`
- `https://apim-cliquepix-002.azure-api.net/api/health`
- `https://cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net/api/health`
- `https://api.clique-pix.com/api/health`

### APIM Rate Limiting Policies

| Scope | Limit | Operation |
|-------|-------|-----------|
| Global (all operations) | 60 requests/min per IP | API-level policy |
| Upload URL | 10 requests/min per IP | `POST /events/{eventId}/photos/upload-url` |
| Auth verify | 5 requests/min per IP | `POST /auth/verify` |

### Function App Settings

| Setting | Value | Source |
|---------|-------|--------|
| `PG_CONNECTION_STRING` | Key Vault reference | `kv-cliquepix-prod/pg-connection-string` |
| `FCM_CREDENTIALS` | Key Vault reference | `kv-cliquepix-prod/fcm-credentials` |
| `STORAGE_ACCOUNT_NAME` | `stcliquepixprod` | Direct |
| `ENTRA_TENANT_ID` | `27748e01-d49f-4f0b-b78f-b97c16be69dc` | Direct (CIAM tenant) |
| `ENTRA_CLIENT_ID` | `7db01206-135b-4a34-a4d5-2622d1a888bf` | Direct |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | Direct |
| `NODE_ENV` | `production` | Direct |

### Entra External ID Configuration

| Component | Status | Details |
|-----------|--------|---------|
| CIAM Tenant | `cliquepix.onmicrosoft.com` | Tenant ID: `27748e01-d49f-4f0b-b78f-b97c16be69dc` |
| App Registration | `Clique Pix` | Client ID: `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Redirect URI (Android debug) | Configured | `msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D` |
| Redirect URI (iOS) | Configured | `msauth.com.cliquepix.app://auth` (auto-generated from Bundle ID `com.cliquepix.app`) |
| Application ID URI | Configured | `api://7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Exposed API Scope | Configured | `access_as_user` — required for MSAL to return app-scoped access token |
| Email OTP | Enabled | Primary sign-in method |
| Google Identity Provider | Configured | OAuth client via Google Cloud Console |
| Apple Identity Provider | Configured | Service ID: `com.cliquepix.app.service`, Key ID: `4NYXZNV9VD` |
| User Flow | `SignUpSignIn` | Email OTP + Google + Apple, Clique Pix app associated |

### Firebase Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Firebase Project | `Clique Pix` | Project ID: `clique-pix-d7fde` |
| Cloud Messaging (FCM) | Enabled | V1 API |
| Android app | Registered | Package: `com.cliquepix.clique_pix` |
| iOS app | Registered | Bundle ID: `com.cliquepix.app` |
| Service account key | Stored | Key Vault: `kv-cliquepix-prod/fcm-credentials` |
| google-services.json | Placed | `app/android/app/google-services.json` (gitignored) |
| GoogleService-Info.plist | Placed | `app/ios/Runner/GoogleService-Info.plist` (gitignored) |

### Google OAuth Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Google Cloud Project | `Clique Pix` | |
| OAuth consent screen | Configured | External, Testing mode |
| Authorized domains | Set | `ciamlogin.com`, `microsoftonline.com`, `clique-pix.com` |
| OAuth client | Web application | For Entra federation (server-to-server) |
| App domain URLs | Set | Home: `https://clique-pix.com`, Privacy: `/privacy.html`, Terms: `/terms.html` |

### Apple Sign In Configuration

| Component | Status | Details |
|-----------|--------|---------|
| App ID | `com.cliquepix.app` | Team ID: `4ML27KY869` |
| Services ID | `com.cliquepix.app.service` | Sign In with Apple configured with CIAM domains |
| Key | `CliquePix Sign In` | Key ID: `4NYXZNV9VD` |
| Client secret (.p8) | Active | **Renewal required: September 2026** |

### Configuration Notes

| Setting | Value | Notes |
|---------|-------|-------|
| `allowSharedKeyAccess` | `true` | Required by Azure Functions runtime for AzureWebJobsStorage |
| `allowBlobPublicAccess` | `false` | No anonymous blob access |
| Storage SKU | `Standard_GZRS` | Changed from RAGZRS (not supported by Consumption plan) |
| Function App plan | Consumption (Linux) | EastUSLinuxDynamicPlan |
| Deployment method | Run-from-package (blob SAS) | Windows→Linux zip requires Python zipfile for forward slashes |
| Front Door endpoint | `cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net` | |
| Custom domain (API) | `api.clique-pix.com` | CNAME → Front Door, managed certificate |
| Custom domain (website) | `clique-pix.com` + `www.clique-pix.com` | ALIAS/CNAME → Static Web App |
| Android package name | `com.cliquepix.clique_pix` | Generated by `flutter create --org com.cliquepix` |
| iOS bundle ID | `com.cliquepix.app` | |
| MSAL package | `msal_auth: ^3.3.0` | Replaced `msal_flutter` (v1 embedding incompatible with Flutter 3.35) |
| MSAL scopes | `['api://7db01206.../access_as_user']` | Custom API scope only; OIDC scopes added implicitly by MSAL |
| CIAM issuer format | `https://{tenantId}.ciamlogin.com/{tenantId}/v2.0` | Tenant ID as subdomain (NOT tenant name) |
| CIAM JWKS URI | `https://cliquepix.ciamlogin.com/{tenantId}/discovery/v2.0/keys` | Tenant name as subdomain |
| API base URL (dev + prod) | `https://api.clique-pix.com` | Front Door custom domain; `fd-cliquepix-prod.azurefd.net` is NOT a valid hostname |

---

## Code Review Summary (2026-03-25)

49 issues found and fixed across 7 commits:

| Severity | Count | Examples |
|----------|-------|---------|
| Critical | 13 | Blob path prefix, SAS permissions, TLS validation, telemetry init, auth wiring |
| High | 18 | Missing telemetry events, image compression, blob upload streaming, reaction IDs |
| Medium | 12 | Feed polling, notification dedup, error interceptor, HEIC detection |
| Low | 5 | Health envelope, deprecated withOpacity, correlation IDs, barrel exports |

---

## Authentication Fix Summary (2026-03-26)

Four bugs were found and fixed in the MSAL → Backend authentication chain:

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. No custom API scope | MSAL returned a Microsoft Graph token (wrong signing keys) when only OIDC scopes were requested | Exposed `api://clientId/access_as_user` scope in Entra; MSAL now requests only this scope |
| 2. Backend issuer mismatch | Backend validated issuer as `cliquepix.ciamlogin.com/...` but CIAM tokens use `{tenantId}.ciamlogin.com/...` | Changed issuer to `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0` |
| 3. Wrong dev API base URL | `fd-cliquepix-prod.azurefd.net` returns 404 (Azure resource name, not actual endpoint) | Changed to `api.clique-pix.com` for both dev and prod |
| 4. `offline_access` declined | CIAM tenants decline `offline_access` without admin consent | Removed from scopes; MSAL handles refresh tokens internally |

**Key learning:** For Entra External ID (CIAM), a mobile app calling a custom backend API **must** expose an API scope (`Expose an API` → `Add a scope`). Without it, `result.accessToken` is a Microsoft Graph token signed by Graph keys — not the CIAM tenant's keys — causing `invalid signature` on backend verification. OIDC scopes (`openid`, `profile`, `email`) must NOT be requested explicitly; MSAL adds them implicitly. Mixing API scopes with OIDC scopes causes `MsalDeclinedScopeException`.

---

## Photo Upload Pipeline Fix Summary (2026-03-26)

The photo upload pipeline appeared completely broken — photos never appeared after capture. Root cause: a **double-pop navigation bug** in the ProImageEditor v5.1.4 integration.

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. ProImageEditor double-pop | v5.x's `doneEditing()` calls `onImageEditingComplete` then immediately calls `onCloseEditor`. Having `Navigator.pop()` in both callbacks double-popped: removed editor + CameraCaptureScreen. User never saw the preview/Upload button. | Moved `Navigator.pop()` to `onCloseEditor` only; `onImageEditingComplete` saves bytes to closure variable without popping |
| 2. BlobUploadService Dio config | `Content-Type` set in headers map instead of `Options.contentType`; manual `Content-Length` could conflict with Dio auto-calc; no `responseType: ResponseType.bytes` for Azure XML errors | Set `contentType: 'image/jpeg'` on Options, `responseType: ResponseType.bytes`, removed manual Content-Length |

**Key learning:** ProImageEditor v5.x's `doneEditing()` (main_editor.dart:1514-1566) always calls `onCloseEditor` after `onImageEditingComplete` completes. The correct pattern is: save data in `onImageEditingComplete` (no pop), then pop in `onCloseEditor`. This matches the official Firebase/Supabase example in the ProImageEditor package.

---

## QR Invite Flow Fix + Clique Join Notifications (2026-03-31)

### Problem 1: QR Code invite returns 404

Scanning a clique invite QR code navigated to `https://clique-pix.com/invite/{code}` which returned a 404 from Azure because the Static Web App had no route or page for `/invite/*` paths.

**Root causes and fixes:**

| Issue | Fix |
|-------|-----|
| No web page for `/invite/*` paths | Created `website/invite.html` — branded dark-themed landing page with platform detection, `intent://` URI for Android, app store buttons |
| No SWA rewrite rule | Added `/invite/*` → `invite.html` rewrite in `staticwebapp.config.json` (must come before `.well-known` routes) |
| `DeepLinkService` never initialized | Converted `app.dart` to `ConsumerStatefulWidget`, call `initialize(router)` in `initState` |
| Invite route bypassed auth check | Removed `isInviteRoute` exemption from GoRouter redirect; added `?redirect=` query param to preserve invite URL through login flow |
| `.well-known` placeholders | Replaced `TEAM_ID` → `4ML27KY869` in AASA; replaced SHA256 placeholder with debug keystore fingerprint in assetlinks.json |
| `JoinCliqueScreen` light theme | Restyled with dark background, gradient heading, aqua accents, dark TextField |

**Website redeployed** to `swa-cliquepix-prod` via SWA CLI. Invite URLs now return 200 with branded page.

### Problem 2: Owner not notified when someone joins clique

| Issue | Fix |
|-------|-----|
| No `member_joined` notification type | Created migration `002_member_joined_notification.sql` — ALTERed CHECK constraint on `notifications.type` |
| Backend didn't send push on join | Added FCM push + notification record creation to `joinClique()` in `cliques.ts`; replicates exact pattern from `photos.ts` |
| `NotificationType` model missing type | Added `'member_joined'` to union type in `notification.ts` |
| Client didn't render `member_joined` | Added icon/color case (person_add + aqua/violet), title case ("New Member"), and clique navigation in `_NotificationTile.onTap` |
| No FCM token registration | Created `PushNotificationService` — requests permission, gets FCM token, sends to `POST /api/push-tokens`, listens for token refresh |
| No auto-refresh on clique screens | Added `WidgetsBindingObserver` + `RefreshIndicator` + `Timer.periodic(30s)` polling to both `CliquesListScreen` and `CliqueDetailScreen` |

**Backend redeployed** to `func-cliquepix-fresh`. Migration run against `pg-cliquepixdb`.

**Known issue:** Push notifications not yet confirmed working end-to-end on device. FCM token registration and backend push logic are implemented but need further debugging.

### Problem 3: Global light theme overriding dark screens

`app.dart` used `AppTheme.light` — a Material 3 light theme that overrode per-widget dark styling on some screens (notably `CreateCliqueScreen`).

**Fix:** Created `AppTheme.dark` in `app_theme.dart` with dark defaults matching the app's visual design (dark scaffold, dark AppBar, dark InputDecoration, aqua accents). Switched `app.dart` to `theme: AppTheme.dark`.

---

## Remaining Tasks

### Completed

| Task | Status | Notes |
|------|--------|-------|
| MSAL authentication flow | Done | End-to-end working: MSAL → custom API scope → backend JWT verification → user upsert |
| Event-first UX flow | Done | 4 tabs (Events/Cliques/Notifications/Profile), event creation with inline clique picker |
| Dark theme across all screens | Done | Cliques detail, event detail, camera capture, notifications, profile — all consistent |
| Photo editor integration | Done | `pro_image_editor` ^5.1.4 — crop, draw, stickers, emoji, filters, text |
| Auth error recovery | Done | Auto-login on startup, MSAL cache reset on failure, error dismiss button |
| New app icon/logo | Done | Generated via `flutter_launcher_icons` from 1024x1024 source |
| Backend: `listAllEvents` endpoint | Done | `GET /api/events` — returns all events across user's cliques with clique name/member count |
| Backend: `uploaded_by_name` in photos | Done | `listPhotos` JOINs users table; `PhotoWithUrls` includes uploader display name |
| PhotoModel resilient parsing | Done | Handles PostgreSQL bigint-as-string (file_size_bytes) without type cast errors |
| ProImageEditor double-pop fix | Done | v5.x calls `onCloseEditor` after `onImageEditingComplete`; moved `Navigator.pop()` to `onCloseEditor` only to prevent double-pop that skipped preview/upload screen |
| BlobUploadService Dio fix | Done | Set `contentType` on Options (not in headers), `responseType: ResponseType.bytes`, removed manual Content-Length |
| Upload pipeline debug logging | Done | `[CliquePix]` prefixed `debugPrint` at every step for `adb logcat` diagnosis |

### Recently Completed (2026-03-31)

| Task | Status | Notes |
|------|--------|-------|
| Well-known files: real values | Done | Apple Team ID `4ML27KY869` in AASA, debug SHA256 in assetlinks.json |
| Invite landing page | Done | `website/invite.html` with SWA rewrite rule, deployed to `swa-cliquepix-prod` |
| Deep link service initialization | Done | `DeepLinkService.initialize(router)` called in `app.dart` |
| Auth gate for invite routes | Done | Unauthenticated invite URLs redirect to login with `?redirect=` preservation |
| Global dark theme | Done | Created `AppTheme.dark`, switched `app.dart` from `AppTheme.light` |
| Home screen dashboard | Done | 4-state contextual dashboard, How It Works card, clique chips, active event cards |
| Back buttons on full-screen routes | Done | Event detail, camera capture, photo detail all have explicit back navigation |
| Clique join push notification (backend) | Done | `joinClique()` sends FCM to existing members, creates `member_joined` notification records |
| DB migration: member_joined type | Done | `002_member_joined_notification.sql` run against `pg-cliquepixdb` |
| FCM token registration (client) | Done | `PushNotificationService` gets token, registers with backend, listens for refresh |
| Clique screens refresh | Done | Pull-to-refresh + app-resume + 30s polling on CliquesListScreen and CliqueDetailScreen |
| JoinCliqueScreen dark theme | Done | Gradient heading, aqua accents, dark TextField |
| Dark theme consistency | Done | EventsListScreen, CreateCliqueScreen, InviteScreen all restyled |

### Recently Completed (2026-04-01)

| Task | Status | Notes |
|------|--------|-------|
| Clique member management: owner remove | Done | `DELETE /api/cliques/{cliqueId}/members/{userId}` — owner-only, validates role, prevents self-removal |
| Clique member management: leave/delete UI | Done | "Leave Clique" button (members), "Delete Clique" button (sole owner), confirmation dialogs |
| Clique member management: tappable removal | Done | Owner sees remove icon on non-owner members; tap shows confirmation dialog |
| Graceful 404 on member removal | Done | When removed user's screen refreshes, detects 404 DioException and navigates to `/cliques` with SnackBar instead of showing error |
| State invalidation: member count | Done | Uses `membersAsync.valueOrNull?.length` for live count; avoids full-screen loading flash |
| Frontend API: `removeMember` | Done | Endpoint constant, CliquesApi method, CliquesRepository method |
| Push notification: foreground display | Done | `onMessage` listener in `main.dart` shows heads-up banner via `flutter_local_notifications.show()` |
| Push notification: channel creation | Done | `cliquepix_default` channel with `Importance.high` created in `main.dart` at startup |
| Push notification: Android 13+ permission | Done | `requestNotificationsPermission()` via Android-specific plugin API |
| Push notification: background tap | Done | `onMessageOpenedApp` → navigates to clique/event via GoRouter |
| Push notification: terminated tap | Done | `getInitialMessage()` → delayed navigation after router init |
| Push notification: local tap routing | Done | Static callback bridges `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter |
| Push notification: in-app list refresh | Done | `onMessage` invalidates `notificationsListProvider` for immediate update |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 27 functions |

### Recently Completed (2026-04-04)

| Task | Status | Notes |
|------|--------|-------|
| Post-creation invite flow | Done | When creating event with NEW clique, modal bottom sheet prompts "Invite Friends" or "Skip for Now" on Event Detail screen. Uses `GoRouter.extra` to pass cliqueId/cliqueName (one-time, not restorable from URL) |
| Top-level routes for cross-shell navigation | Done | Added `/view-clique/:cliqueId` and `/invite-to-clique/:cliqueId` outside `StatefulShellRoute` — fixes back-navigation when pushing to shell-internal routes from Event Detail |
| Clique navigation from event detail | Done | AppBar group icon (always visible) + tappable clique name with chevron in hero section — both use top-level `/view-clique/` route for clean back-navigation |

### Recently Completed (2026-04-03)

| Task | Status | Notes |
|------|--------|-------|
| Event deletion: backend endpoint | Done | `DELETE /api/events/{eventId}` — creator-only auth, blob cleanup before cascade DB delete, push + in-app notification to clique members |
| Event deletion: frontend UI | Done | Delete icon in AppBar (organizer only), dark-themed confirmation dialog, post-delete navigation to events list with SnackBar |
| Event deletion: API/repository layer | Done | `deleteEvent()` method in EventsApi and EventsRepository |
| Photo card name readability fix | Done | Uploader name and timestamp text overridden to white for dark card background (#162033) — was invisible dark navy (#0F172A) |
| Multi-select media download: selection state | Done | `MediaSelectionNotifier` + `mediaSelectionProvider` (family by eventId) in photos_providers.dart — unified for photos + videos |
| Multi-select media download: card UI | Done | Circular checkbox overlay on photo and video cards (aqua when selected), tap toggles selection; processing/failed videos excluded from selection |
| Multi-select media download: feed UI | Done | Selection toolbar with Select All / Deselect All + Cancel; download action bar with dynamic label ("Download 3 Photos" / "Download 2 Videos" / "Download 5 Items") |
| Multi-select media download: batch save | Done | Photos via `savePhotoToGallery()`, videos via `saveVideoToGallery()` (MP4 fallback URL) — sequential with combined progress, continues past individual failures |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Clique screens: refresh button | Done | Refresh icon in AppBar on both CliqueDetailScreen and CliquesListScreen — calls existing `_refresh()` / `cliquesListProvider.notifier.refresh()` |
| DB migration: `event_deleted` notification type | Done | Migration `003_event_deleted_notification.sql` — added `event_deleted` to notifications CHECK constraint |
| Event creator name: backend queries | Done | `getEvent`, `listEvents`, `listAllEvents` now JOIN `users` table, return `created_by_name` |
| Event creator name: frontend model | Done | Added `createdByName` optional field to `EventModel`, parsed from `created_by_name` |
| Event creator name: UI display | Done | "Created by {name}" row with person icon in event detail hero header |
| Backend redeployed (2nd) | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Notification clear/delete: backend endpoints | Done | `DELETE /api/notifications/{id}` (single) + `DELETE /api/notifications` (clear all) with ownership verification |
| Notification clear/delete: API/repository | Done | `deleteNotification()` + `clearAll()` in notifications_api.dart and notifications_repository.dart |
| Notification clear/delete: UI | Done | Clear All icon in AppBar with confirmation dialog; swipe-to-dismiss (Dismissible) on each notification tile |
| Backend redeployed (3rd) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 31 functions |
| Copy user ID button | Done | User ID displayed on profile card with copy icon, copies to clipboard with SnackBar |
| Delete account: backend endpoint | Done | `DELETE /api/users/me` — cleans up sole-owner cliques + blobs, deletes user photos + blobs, deletes user record |
| Delete account: DB migration 004 | Done | `created_by_user_id` and `uploaded_by_user_id` made nullable with ON DELETE SET NULL on cliques, events, photos |
| Delete account: auth layer | Done | `deleteAccount()` threaded through AuthApi → AuthRepository → AuthNotifier with local cleanup |
| Delete account: profile UI | Done | Red "Delete Account" tile with confirmation dialog; GoRouter auto-redirects to login on success |
| Backend redeployed (4th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 32 functions |
| DM: Azure Web PubSub provisioned | Done | `wps-cliquepix-prod` Standard S1, connection string in Key Vault, Function App setting configured |
| DM: database migration 005 | Done | `event_dm_threads` + `event_dm_messages` tables with indexes, CHECK constraints, CASCADE from events |
| DM: Web PubSub service | Done | `webPubSubService.ts` — token negotiation, `sendToUser` for direct user-targeted delivery (switched from thread-scoped groups) |
| DM: backend endpoints (7) | Done | createOrGetThread, listThreads, getThread, listMessages, sendMessage (rate limited), markRead, negotiate |
| DM: backend models | Done | `dmThread.ts` — DmThread + DmMessage TypeScript interfaces |
| DM: timer integration | Done | DM threads marked read-only in `cleanupExpired` timer, then hard-deleted with event via CASCADE |
| DM: clique removal integration | Done | `removeMember` + `leaveClique` mark affected DM threads as read-only |
| DM: Flutter models | Done | `DmThreadModel` + `DmMessageModel` with fromJson factories |
| DM: Flutter API + repository | Done | `dm_api.dart` + `dm_repository.dart` — 7 methods matching backend |
| DM: Flutter realtime service | Done | `dm_realtime_service.dart` — WebSocket connection with auto-reconnect (exponential backoff), re-negotiates fresh URL on reconnect |
| DM: Flutter providers + routing | Done | Riverpod providers, 3 routes under `/events/:eventId/` (dm-threads, dm/new, dm/:threadId) |
| DM: thread list screen | Done | Dark-themed list with unread indicators, "New Message" FAB, empty state |
| DM: chat screen | Done | Message bubbles (gradient for sent, dark for received), composer, read-only banner |
| DM: member picker screen | Done | Lists clique members for starting new DMs |
| DM: event detail entry points | Done | Messages icon in AppBar + prominent "Messages" button below "Add Photo" |
| DM: FCM push tap routing | Done | `dm_message` type navigates to `/events/{eventId}/dm/{threadId}` |
| DM: debug logging | Done | `[CliquePix DM]` logs for eventId, API response, thread count |
| Backend redeployed (5th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 39 functions |
| Fix: Sign out not working | Done | Missing `await`, unprotected cleanup, stale PCA instance — all three fixed with defense-in-depth (try/catch + try/finally + `_pca = null`) |
| Fix: Welcome screen UI | Done | Hide redundant FAB in brand-new state, brighten helper text (0.3→0.55), "Add Your Crew"→"Add Your Clique" |
| Fix: DM real-time delivery | Done | Switched from group-based (`sendToAll`) to user-targeted (`sendToUser`) delivery; fixed WebSocket reconnection to re-negotiate fresh URL |
| Backend redeployed (6th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — DM sendToUser fix |
| Fix: Sign-out browser session | Done | Added `browser_sign_out_enabled: true` to `msal_config.json` + `Prompt.login` on `acquireToken` — clears Google session cookies on sign-out, forces re-authentication on sign-in |

### Recently Completed (2026-04-13)

| Task | Status | Notes |
|------|--------|-------|
| Fix: iOS MSAL auth loop | Done | Three root causes: (1) no iOS platform registered in Azure Entra, (2) Info.plist URL scheme `msauth.com.cliquepix.app` didn't match bundle ID, (3) missing keychain entitlements (`com.microsoft.adalcache`). Errors were silently swallowed by `auth_providers.dart` catch block. |
| iOS bundle ID reconciliation | Done | Changed Xcode bundle ID from `com.cliquepix.cliquePix` (flutter create default) to `com.cliquepix.app` to match Apple App ID, Firebase iOS, and Apple Sign In config. Updated Azure Entra iOS platform accordingly. |
| Info.plist URL scheme fix | Done | Changed from hardcoded `msauth.com.cliquepix.app` to `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` — auto-resolves at build time |
| Runner.entitlements created | Done | Keychain group `$(AppIdentifierPrefix)com.microsoft.adalcache` for MSAL token caching |
| iOS deployment target bump | Done | 13.0 → 15.0 (required by `firebase_core` v4 and `workmanager_apple`) |
| Firebase packages upgraded | Done | `firebase_core` 2.x → 4.7.0, `firebase_messaging` 14.x → 16.2.0 (old versions incompatible with Xcode 26.2), `share_plus` 9.x → 12.x (dependency conflict with new firebase_core) |
| iOS code signing configured | Done | `DEVELOPMENT_TEAM = 4ML27KY869`, `CODE_SIGN_STYLE = Automatic` on all Runner build configs |
| iOS on-device verification | Done | App builds, installs, and authenticates successfully on physical iPhone (iOS 26.3.1) |

### Recently Completed (2026-04-15)

| Task | Status | Notes |
|------|--------|-------|
| Profile: remove "View Licenses" from About dialog | Done | Replaced Flutter's built-in `showAboutDialog()` (which always injects a VIEW LICENSES button) with a custom `showDialog` + `AlertDialog` containing only a Close action. Title, version, and legalese text preserved. `profile_screen.dart:145-166` |
| Cliques list: remove "+ Create Clique" FAB | Done | Deleted the always-visible gradient FAB from `CliquesListScreen` to eliminate duplication with the empty-state card's "Create Clique" button. Reduced list bottom padding from 100 → 24 now that the FAB no longer needs clearance. Users with existing cliques still reach Create Clique via the Home tab's "+ New Clique" quick-start chip. `cliques_list_screen.dart:135` |
| Event Detail: add 4-tab bottom nav | Done | Event Detail (`/events/:eventId`) previously had no way to jump directly to Home / Cliques / Notifications / Profile — only a back arrow. Extracted the shell's nav bar into a shared `AppBottomNav` widget (`app/lib/widgets/app_bottom_nav.dart`), refactored `ShellScreen` to use it (pixel-identical), and added `bottomNavigationBar: AppBottomNav(...)` to `EventDetailScreen`'s Scaffold. Taps use `context.go('/events' \| '/cliques' \| '/notifications' \| '/profile')` — go_router's `StatefulShellRoute` activates the correct branch cleanly. `selectedIndex: 0` (Home highlighted) since events live under `/events`. Zero routing changes, zero cross-branch push concerns. Full-screen children (camera, photo detail, video capture/upload/player, DM list/chat) remain without the nav. Rejected alternative of moving `/events/:eventId` into the Home shell branch due to go_router 14 cross-branch `push` ambiguity from `events_list_screen.dart:137` and notification tap handlers. `event_detail_screen.dart:29-62`, `shell_screen.dart`, `app_bottom_nav.dart` (new) |
| Profile: reorder legal tiles, add Contact Us | Done | First settings group reordered to `About Clique Pix → Terms of Service → Privacy Policy → Contact Us`. Gradient pairs reassigned so the brand rainbow cascade still flows top-to-bottom (aqua→deep, deep→violet, violet→pink, pink→aqua). New Contact Us tile opens a dark-themed dialog (matching Sign Out / Delete Account styling) showing `support@xtend-ai.com` in a `SelectableText` with two actions: **Copy Email** (Clipboard + "Email copied!" floating snackbar, mirroring the existing user-ID copy pattern) and **Send Email** (launches `mailto:support@xtend-ai.com?subject=Clique%20Pix%20Support` via `LaunchMode.externalApplication`). File-level `_supportEmail` const prevents typo drift across the three use sites. Android manifest `<queries>` block extended with `SENDTO` + `mailto` intent — **required** for Android 11+ package visibility, else `launchUrl` silently no-ops. iOS `LSApplicationQueriesSchemes` left unchanged (non-blocking since `canLaunchUrl` is not used). `profile_screen.dart:8,141-237`, `AndroidManifest.xml:98-111`. |
| Photo upload: fix 403 AuthorizationFailure + add client error mapper | Done (pending deploy) | **Regression fix:** commit `8d8decf` (2026-03-24, "backend critical fixes C1-C7") removed `permissions.create = true` from `generateUploadSas`, leaving only `write`. Azure Blob Storage's User Delegation SAS requires `create` for Put Blob against a brand-new path (per Microsoft's own docs: "Write a new blob" is listed under the Create permission). Videos were unaffected because Put Block only needs `write`. Restored both `write` and `create` on upload SAS to match pre-regression baseline and Microsoft's canonical `acdrw` CLI upload template. **Client diagnostic improvements:** new `BlobUploadFailure` typed exception in `blob_upload_service.dart` parses Azure's XML error envelope (`<Code>`, `<Message>`) via regex. `CameraCaptureScreen._friendlyError` maps Azure codes (`AuthorizationFailure`, `AuthenticationFailed`, `InvalidHeaderValue`, `RequestBodyTooLarge`), Dio timeouts, and backend HTTP statuses (401/403/404/5xx) to user-facing text; raw exceptions only surface in `kDebugMode`. Backend: `sasService.ts:43-48`. Client: `blob_upload_service.dart`, `camera_capture_screen.dart:117-171`. Deploy sequence: backend first (resolves existing clients immediately), client changes ship in next app build. |
| Home screen: remove "+ Create Event" FAB | Done | Parallel to the earlier Cliques list FAB removal (c11f208). Deleted `_buildFab()` and the Scaffold `floatingActionButton:` wiring from `home_screen.dart`; also removed the now-orphaned `homeState` build-scope computation. The `hasActiveEvents` state previously had **no** centered Create Event CTA and relied solely on the FAB, so added a new `_buildCreateEventCTA('Start Another Event')` below the active event cards to preserve the Home-tab Create Event path for users with existing events. Reduced three `SliverPadding` bottoms from `100` → `24` (FAB clearance no longer needed), matching the `c11f208` pattern. Label choice "Start Another Event" distinguishes from "Create Event" (zero-state), "Create Your First Event" (first-timer), and "Start a New Event" (re-engagement). `home_screen.dart:85-95, 357-375, 428-432`. |

### Recently Completed (2026-04-22)

| Task | Status | Notes |
|------|--------|-------|
| Branded "Clique Pix" header on all four tab screens | Done | App name was not visible anywhere inside the running app — only the per-screen title ("Home" / "My Cliques" / "Notifications" / "Profile") appeared. Added a persistent brand ribbon (rounded 56 × 56 logo from `assets/logo.png` with a soft aqua glow + "Clique Pix" wordmark in `AppGradients.primary` via `ShaderMask`, 40 px w700) above each screen title. **New widget:** `app/lib/widgets/branded_sliver_app_bar.dart` — reusable `BrandedSliverAppBar` owns the `SliverAppBar` shell (`pinned: true`, `expandedHeight: 260`), per-tab accent wash (electric aqua / deep blue / violet / pink), wordmark positioned via `SafeArea` + `Padding(top: 80)` + `Align.topCenter` inside `flexibleSpace` so it sits as a hero element, and the existing screen title anchored 16 px from the bottom of the expanded area. Accepts `screenTitle`, `screenTitleGradient`, `accentColor`, `accentOpacity`, `actions`. **Trade-off:** wordmark scrolls away with the header hero on content scroll — collapsed state is just a 56 px dark bar with actions (Refresh on Cliques, Clear All on Notifications when non-empty). The brand wordmark is intentionally the same across all four tabs for identity consistency; the existing per-screen title gradients (Notifications deepBlue→violet, Profile violet→pink) are preserved. **Applied to:** `home_screen.dart:119-151`, `cliques_list_screen.dart:65-104`, `notifications_screen.dart:61-103`, `profile_screen.dart:25-59` — each ~35 lines of inline `SliverAppBar` code collapsed into a single `BrandedSliverAppBar(...)` call. Iterated on sizing (28 → 56 px logo, 20 → 40 px text) and vertical position (`toolbarHeight` approach → `flexibleSpace`-positioned hero) across three user feedback rounds. `flutter analyze` on the new widget is green; overall baseline unchanged. |

### Recently Completed (2026-04-17)

| Task | Status | Notes |
|------|--------|-------|
| Video card emoji reactions + `ReactionBarWidget` refactor | Done | Video cards were the only remaining v1 feature area missing the ❤️ 😂 🔥 😮 reaction row — all backend plumbing (routes, shared handler branching on `media_type`, `enrichVideoWithUrls` returning `reaction_counts` + `user_reactions`, `VideosRepository.addReaction/removeReaction`, `VideoModel.reactionCounts/userReactions`) already existed; only the Flutter UI was missing. Decoupled `ReactionBarWidget` from `photosRepositoryProvider` (was hardcoded at line 41) by parameterizing with `onAdd` + `onRemove` async callbacks — widget is now media-agnostic (`mediaId` param, no Riverpod coupling, converted `ConsumerStatefulWidget` → `StatefulWidget`). This was needed because `videosRepositoryProvider` is a `FutureProvider<VideosRepository>` (async; depends on `SharedPreferences.getInstance()`) while `photosRepositoryProvider` is a sync `Provider` — a direct provider swap didn't work. Unified `PhotosRepository.addReaction` return type from `Future<void>` → `Future<({String id, String type})>` to match `VideosRepository.addReaction`. This also **fixed a pre-existing bug**: the widget previously discarded the API response on add, so `_userReactionIds[type]` stayed empty; a subsequent unlike in the same session hit the `reactionId.isNotEmpty` guard, never fired DELETE, and the reaction re-appeared on the next 30s poll. The refactor captures the id (with `mounted` guard) so same-session add+remove works end-to-end. Callsite updates: `photo_card_widget.dart:128-140` (converted `StatelessWidget` → `ConsumerWidget`), `photo_detail_screen.dart:163-173` (already `ConsumerWidget`), `video_card_widget.dart:82-100` (converted `StatelessWidget` → `ConsumerWidget`, reaction row gated on `video.isReady` because backend rejects reactions on non-active media — processing/failed/local-pending cards intentionally unchanged). `flutter analyze` green — zero new issues. Video player screen reactions explicitly out of scope (parity with photo detail is a separate follow-up). |
| Uploader-only delete on feed cards + dialog consolidation | Done | Users needed a one-tap recovery path for accidental uploads. Prior state: `photo_detail_screen.dart:45-119` had Delete but was visible to all viewers and didn't invalidate the feed (photo lingered 30s); `video_player_screen.dart:357-405` had Delete + feed invalidation but also visible to all; neither feed card had any delete affordance. Backend (`photos.ts:424-466`, `videos.ts:725-763`) already enforces uploader-only (403 for others) with CASCADE on reactions and Decision Q5 discard-on-callback for delete-during-transcode — zero server changes needed. **New:** `app/lib/widgets/confirm_destructive_dialog.dart` — shared `confirmDestructive(context, title, body, confirmLabel)` helper lifting the canonical dark-theme `AlertDialog` styling (`0xFF1A2035` bg, `0xFFEF4444` destructive button, 16px radius, 70% alpha content) out of 5 duplicated sites. `app/lib/widgets/media_owner_menu.dart` — shared `MediaOwnerMenu` widget renders a 3-dot `PopupMenuButton` in the card header when `isOwner && !isSelecting`; handles confirm + SnackBar + `_deleteErrorMessage` mapping (`FORBIDDEN` / `PHOTO_NOT_FOUND` / `VIDEO_NOT_FOUND` / timeout → friendly strings, 404 treated as "already removed" since feed was invalidated pre-throw). **Applied to:** `photo_card_widget.dart` + `video_card_widget.dart` (new 3-dot via `MediaOwnerMenu`); `photo_detail_screen.dart` (delete item now gated on `isOwner`, invalidates `eventPhotosProvider(photo.eventId)` before pop); `video_player_screen.dart` (delete item gated via `videoDetailProvider` watch, watches `authStateProvider`). **Video-specific:** delete flow in card + player retires any `LocalPendingVideo` whose `serverVideoId` matches the deleted server video — fixes a ghost-card regression (would otherwise re-render "Polishing your video" after server delete because the feed merge would see only the local pending item). **Existing-dialog consolidation:** the 5 pre-existing `AlertDialog`-based destructive confirmations (`event_detail_screen._showDeleteEventDialog`, `clique_detail_screen._showRemoveMemberDialog` / `_showLeaveCliqueDialog` / `_showDeleteCliqueDialog`, `profile_screen` delete-account) now all call `confirmDestructive` — single source of truth for destructive-confirm styling. Username `Text` in both card widgets gained `overflow: TextOverflow.ellipsis` so long display names don't push the 3-dot off-screen. `flutter analyze` green — 61 issues, same pre-existing baseline, zero new. Out of scope: mid-upload cancel for local pending videos (deferred to v1.5); multi-select delete on feed. |
| 13+ age gate at sign-up — claim-based, backend-enforced | Done (2026-04-18) | **Pivoted from the Entra Custom Authentication Extension approach** after multi-day debugging revealed it's not a supported pattern in External ID (Microsoft's own migration docs: *"Age gating isn't currently supported in Microsoft Entra External ID"*). Instead: Entra's `SignUpSignIn` user flow still collects `dateOfBirth` as a custom attribute once; the attribute is emitted on every access token via the documented Directory schema extension claim path; backend `authVerify` (`backend/src/functions/auth.ts`) reads the claim on first login, computes age via existing `ageUtils.calculateAge`, and branches: ≥13 → upsert user with `age_verified_at = NOW()` + `age_gate_passed` telemetry; <13 → HTTP 403 `AGE_VERIFICATION_FAILED` + best-effort Microsoft Graph `DELETE /users/{oid}` via `entraGraphClient.ts` + `age_gate_denied_under_13` telemetry. Grandfathered users (no DOB claim) pass silently with `age_verified_at` null. **New code:** `auth.ts` additions (`decideAgeGate`, `extractDobFromClaims`, `parseAnyDob`), `entraGraphClient.ts`, migration `008_user_age_verification.sql` adding `users.age_verified_at`. **Removed code:** `validateAge.ts` (CAE function — deleted), `entraCaeTokenVerifier.ts` + tests (were needed when EasyAuth proved opaque; no longer used). **Portal state:** EasyAuth removed from `func-cliquepix-fresh`; CAE detached from the `SignUpSignIn` user flow; `dateOfBirth` added as a token claim on the Clique Pix app via Enterprise App → SSO → Attributes & Claims (Directory schema extension from b2c-extensions-app); Function App managed identity granted `User.ReadWrite.All` on Microsoft Graph for the under-13 cleanup. **Tests:** 16 new unit tests covering the age-gate decision logic + 20 existing ageUtils tests, all green. **Client UX (commit `1a37af1`):** `AuthNotifier.signIn` in `auth_providers.dart` detects the structured 403 `AGE_VERIFICATION_FAILED` response, resets the MSAL session to avoid retry loops, and passes the backend's message through to `AuthError` — the login screen shows the red banner *"You must be at least 13 years old to use Clique Pix."* instead of the previous generic "Sign in failed. Please try again." See `docs/AGE_VERIFICATION_RUNBOOK.md` for the full architecture + troubleshooting. |

| Task | Status | Notes |
|------|--------|-------|
| APIM: X-Azure-FDID header validation | Not done | Restrict APIM to Front Door traffic only |
| Google OAuth: add second redirect URI | Not done | May need tenant-ID-format URI |
| Release signing key | Not done | Needed for production APK and Play Store; assetlinks.json must be updated with release SHA256 |
| App Store / Play Store submission | Not done | |
| iOS Associated Domains entitlement | Not done | Requires Xcode on Mac: Signing & Capabilities → `applinks:clique-pix.com` |
| Push notification end-to-end verification | In progress | Full pipeline implemented (backend FCM send confirmed via App Insights, client foreground/background/terminated handlers, channel creation, Android 13+ permission). Needs on-device verification. |

### End-to-End Validation

| Step | Status |
|------|--------|
| 1. Sign up / sign in | Done (2026-03-26) |
| 2. Create a Clique | Done (2026-03-26) |
| 3. Generate invite link/QR | Done (2026-03-31) — QR code encodes `https://clique-pix.com/invite/{code}` |
| 4. Join Clique via invite (QR scan) | Done (2026-03-31) — invite landing page loads (no more 404), join succeeds, joiner appears in clique |
| 5. Create Event (24h/3d/7d) | Done (2026-03-26) |
| 6. Capture photo in-app | Done (2026-03-26) — photo confirmed in database |
| 7. Upload photo (compress → SAS → blob → confirm) | In progress — double-pop bug fixed (user never saw Upload button); Dio config fixed; needs retest |
| 8. See photo in feed | In progress — type cast bug fixed, needs retest after upload pipeline fix |
| 9. React to photo | Not tested |
| 10. Save photo to device | Not tested |
| 11. Share photo externally | Not tested |
| 12. Receive push notification (clique join) | In progress — backend sends FCM successfully (confirmed via App Insights telemetry), client has foreground/background/terminated handlers + notification channel + Android 13+ permission. Needs on-device verification. |
| 13. Auto-deletion after expiry | Not tested |
| 14. Graceful re-login (Layer 5) | Not tested |
| 15. Owner sees new member (auto-refresh) | Partial — pull-to-refresh works, 30s polling implemented, but auto-refresh not confirmed working on device |
| 16. Owner removes member from clique | Done (2026-04-01) — owner taps member → confirm dialog → member removed → list refreshes |
| 17. Member leaves clique | Done (2026-04-01) — member taps "Leave Clique" → confirm → navigates to cliques list |
| 18. Removed member graceful redirect | Done (2026-04-01) — 404 detection auto-navigates removed user back to cliques list with SnackBar |
| 19. Event organizer deletes event | Not tested — delete icon visible to creator, confirmation dialog, blob cleanup + cascade delete |
| 20. Non-organizer cannot delete event | Not tested — delete icon should not appear for non-creators |
| 21. Multi-select media download | Not tested — enter selection mode, select photos + videos, download with progress bar, dynamic label |
| 22. Photo card uploader name readable | Not tested — white text on dark card background |
| 23. Event creator name displayed | Not tested — "Created by {name}" visible on event detail screen |
| 24. Clear all notifications | Not tested — tap trash sweep icon in AppBar → confirm → all notifications cleared |
| 25. Swipe to dismiss notification | Not tested — swipe left on individual notification → red background → deleted |
| 26. Copy user ID from profile | Not tested — tap copy icon next to UUID → clipboard |
| 27. Delete account | Not tested — tap Delete Account → confirm → account removed → redirected to login |
