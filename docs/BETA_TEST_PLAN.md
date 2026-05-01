# Clique Pix — Open Beta Smoke Test Plan

**Last Updated:** April 17, 2026

This is a manual smoke test checklist to run before each beta release. Every item must pass on **both iOS and Android** unless noted otherwise.

---

## Prerequisites

- Two physical devices (or one device + one emulator) with separate accounts
- Device A = "Uploader" (primary tester)
- Device B = "Member" (secondary tester)
- Good WiFi connection for initial testing; repeat video upload on LTE to verify resumability
- Fresh app install (clear data or reinstall)

---

## 1. Authentication

- [ ] **Sign in** — email OTP flow completes, lands on home screen
- [ ] **iOS post-auth no-crash regression (added 2026-05-01)** — on iOS only: from Profile → Sign Out → force-close the app from the app switcher → relaunch from the home screen → tap Get Started → complete MSAL/Safari auth. App MUST stay foregrounded after Safari dismisses and land on Events. **Failure mode to watch for:** app vanishes back to the iOS home screen the instant Safari closes. Caused historically by `BGTaskSchedulerPermittedIdentifiers` in `app/ios/Runner/Info.plist` declared without a registered launch handler (SIGABRT on the FlutterViewController re-attach). See `BETA_OPERATIONS_RUNBOOK.md` "iOS user reports 'app vanishes the second I sign in'" for diagnostic and `DEPLOYMENT_STATUS.md` "BGTask SIGABRT iOS post-auth crash" for the fix history.
- [ ] **Cold start — returning user, no splash** — after a successful sign-in, kill the app and reopen. The first frame drawn must be the Events screen. There should be no splash screen, no "Get Started" button flash, and no button-spinner. `cold_start_optimistic_auth` + `background_verification_success` events appear in Token Diagnostics.
- [ ] **Cold start — first-time user, enabled button** — uninstall and reinstall. Open the app. The first frame drawn must be LoginScreen with the "Get Started" button fully enabled and labeled (no spinner). `cold_start_unauthenticated` event appears.
- [ ] **Cold start — expired session routes to Welcome Back** — sign in, then force-expire the session (Token Diagnostics → rewrite `lastRefreshTime` to 13h ago and reset MSAL cache manually if available, or just wait 13+ hours). Kill and reopen the app. Within ~2 seconds the Events shell should appear briefly and then be replaced by the Welcome Back dialog. `background_verification_timeout` or `cold_start_relogin_required` event appears.
- [ ] **Escape hatch on stuck sign-in** — on LoginScreen, tap "Get Started" and (for test purposes) leave the browser open without completing. At 15 seconds, a "Having trouble? Sign in with a different account" link appears below the button. Tapping it resets MSAL cache and restarts interactive sign-in. `login_screen_escape_hatch_shown` + `login_screen_escape_hatch_tapped` events appear.
- [ ] **Token persists** — kill app, reopen, still signed in
- [ ] **Token refresh (Layer 3 — foreground resume)** — leave app closed for 6+ hours, reopen. Still signed in. Unlock Token Diagnostics (Profile → tap version 7×) and confirm an entry: `foreground_refresh_success` with timestamp matching the reopen.
- [ ] **Sign out** — tap sign out, returns to login screen, reopening app shows login
- [ ] **Re-login after 12h (Layer 5 — Welcome Back)** — wait 13h without opening the app → reopen → "Welcome back, [Name]" dialog appears with email pre-filled. Tap Sign In → one-tap re-auth succeeds, no email re-entry.
- [ ] **Battery-exempt prompt (Layer 1, Android)** — on first launch after login on Android, the "Stay Signed In" dialog appears. Grant it. Token Diagnostics → `battery_exempt_granted` event appears.
- [ ] **Silent push refresh (Layer 2) — Android happy path** — in Token Diagnostics, note current `lastRefreshTime`. Background the app for at least the timer cycle (~20 min), or use the backend `refreshTokenPushTimer` to target the user manually by backdating `last_activity_at` to 10h ago. Return to Token Diagnostics → `silent_push_received` + `silent_push_refresh_success` events. `lastRefreshTime` advanced without any UI interaction.
- [ ] **Silent push refresh (Layer 2) — iOS fallback flag** — same setup on iOS. Acceptable outcomes: either `silent_push_refresh_success` directly, OR `silent_push_fallback_flag_set` followed by `foreground_refresh_success` on next foreground. Both paths keep the user signed in.
- [ ] **Silent push does not wake — force-kill case (iOS)** — force-kill app, wait 13h, reopen → `cold_start_relogin_required` + Welcome Back dialog. Expected (iOS policy).
- [ ] **Token Diagnostics unlock** — Profile → tap version 7× → "Token Diagnostics unlocked" snackbar; new "Token Diagnostics" text link appears below the version.
> **Age gate enforced server-side** in `authVerify` via the `dateOfBirth` token claim. Entra collects DOB once at signup; backend reads the claim on first login; under-13 returns HTTP 403 and the Entra account is best-effort deleted via Microsoft Graph. See `docs/AGE_VERIFICATION_RUNBOOK.md`.

- [ ] **Age gate — new sign-up over 13** — tap Get Started → Entra sign-up form asks for DOB once → **DOB ≥ 13** (e.g. 1990-05-15) → signup completes → app lands on home screen. App Insights: `age_gate_passed` event with coarse `ageBucket` (never raw DOB). SQL: `SELECT age_verified_at FROM users WHERE email_or_phone = '<test>'` returns a recent timestamp.
- [ ] **Age gate — new sign-up under 13** — tap Get Started → Entra sign-up form → **DOB < 13** (e.g. 2020-01-01) → Entra signup completes, but the app returns to the login screen with a red error banner reading *"You must be at least 13 years old to use Clique Pix."* (surfaced from backend `AGE_VERIFICATION_FAILED` response, mapped in `auth_providers.dart:AuthNotifier.signIn`). Tapping **Dismiss** clears the banner. App Insights: `age_gate_denied_under_13`. Within ~60s verify the Entra account is deleted: `az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?\$filter=mail eq '<test-email>'"` returns empty `value: []`.
- [ ] **Age gate — returning user — no re-prompt** — sign out of a valid over-13 account, tap Get Started → Entra sign-in only (no DOB field) → lands on home screen. `age_verified_at` unchanged (COALESCE preserves it).
- [ ] **Age gate — different account on same device** — sign out, register a NEW account with a different email → Entra sign-up form asks for DOB (new account). Independent of prior account's verification.
- [ ] **Age gate — JWT claim check** — decode a post-login access token at `https://jwt.ms`. Verify `extension_<GUID>_dateOfBirth` is present in claims.
- [ ] **Age gate — endpoint check** — unauth `curl -X POST https://func-cliquepix-fresh.azurewebsites.net/api/auth/verify` returns 401 with `UNAUTHORIZED`. `validate-age` endpoint returns 404 (deleted — expected).
- [ ] **App shell — branded header on all 4 tabs** — after sign-in, tap through Home → Cliques → Notifications → Profile. Every tab shows the same branded hero: rounded app-icon logo (with a soft aqua glow) next to the "Clique Pix" wordmark in the aqua → blue → violet gradient, with the per-screen title ("Home" / "My Cliques" / "Notifications" / "Profile") in its own gradient below it. Each tab has a distinct background wash (aqua on Home, deep blue on Cliques, violet on Notifications, pink on Profile). Scroll the Home feed up — the branded hero collapses away, leaving a thin dark toolbar (with any per-screen actions like Refresh on Cliques / Clear All on Notifications). Scroll back to top — header reappears.

## 2. Cliques

- [ ] **Create clique** — enter name, clique appears in list
- [ ] **Generate invite link** — share sheet opens with invite URL
- [ ] **Join via invite link** — Device B taps link, app opens to join screen, joins successfully
- [ ] **View members** — both devices see each other in member list
- [ ] **Leave clique** — Device B leaves, member list updates on Device A
- [ ] **QR code** — QR generated on Device A, scannable by Device B

## 3. Events

- [ ] **Create event** — pick clique, enter name, select duration (24h / 3 days / 7 days), event appears in list
- [ ] **Event visible to member** — Device B sees the event in their list
- [ ] **Event card shows photo count** — event card displays correct photo count with proper singular/plural ("1 photo" / "3 photos")
- [ ] **Event card shows video count** — after uploading a video, event card shows video count with videocam icon (e.g., "1 photo 🎥 1 video")
- [ ] **Delete event** — organizer deletes, event disappears from both devices
- [ ] **Delete push notification** — Device B receives "Event Deleted" push when Device A deletes
- [ ] **Event Detail bottom nav** — open an event → 4-tab bottom nav (Home, Cliques, Notifications, Profile) is visible with Home highlighted. Tap each tab in turn: each transitions directly to the corresponding tab's root screen. Reopen the event and confirm the AppBar back arrow still returns to the previous screen (Home dashboard, events list, or notifications).
- [ ] **Full-screen children stay immersive** — from Event Detail: tap Photo (camera), Video → upload → player, and Messages → DM chat. Confirm NONE of these screens show the bottom nav.
- [ ] **Home Create Event buttons — single entry point per state** — open Home tab: no bottom-right `+ Create Event` FAB visible in any state. Confirm each state has exactly ONE Create Event CTA: brand-new account shows "Create Your First Event"; account with cliques but no active events shows "Create Event"; account with ≥1 active event shows "Start Another Event" below the active event cards; account with only expired events shows "Start a New Event". Tapping any of them opens `/events/create`.

## 4. Photos

- [ ] **Capture photo** — in-app camera captures, editor opens
- [ ] **Edit photo** — crop, draw, add sticker, apply filter, save
- [ ] **Upload from camera roll** — pick existing photo, editor opens, upload succeeds
- [ ] **Photo appears in feed** — photo visible within 5 seconds on Device A
- [ ] **Push notification** — Device B receives "New Photo!" push
- [ ] **Photo visible to member** — Device B sees photo in event feed
- [ ] **Thumbnail loads** — feed shows thumbnail, not full-size
- [ ] **Full-size on tap** — tapping photo loads full resolution
- [ ] **Save to device** — long press or menu → "Save to Device" → photo in gallery
- [ ] **Batch download (photos)** — select multiple photos → download all → verify in gallery
- [ ] **Batch download (mixed)** — select photos + videos → download all → verify both types in gallery
- [ ] **Batch download label** — photos only → "Download N Photos"; videos only → "Download N Videos"; mixed → "Download N Items"
- [ ] **Share externally** — share sheet opens, can send via Messages/WhatsApp/etc.
- [ ] **React** — tap heart/laugh/fire/wow, reaction appears, other device sees it
- [ ] **Delete own photo** — uploader deletes, photo disappears from both feeds
- [ ] **Upload error — friendly message + diagnostic panel** — if the upload fails, the Share Photo screen shows a user-facing message that includes the failed stage (e.g., "Upload failed at 'Getting upload URL...'", "Network timed out at 'Confirming...'") with a **Show details** link. Tapping it expands a `SelectableText` panel with stage / Dio type / HTTP status / response body for copy-paste diagnosis. NOT a raw stack-trace dump. The retry button re-runs the full flow from a fresh SAS.
- [ ] **Upload 429 cooldown UX (regression — should not normally fire post-2026-04-27)** — if APIM ever returns 429, the error message reads "Too many requests. Please wait Ns and retry." with seconds parsed from `Retry-After`. Both the inline "Tap to Retry" link AND the big "Upload to Event" button become disabled with a live `Wait Ns` countdown that ticks down each second. Re-enables automatically when the window expires. Per DEPLOYMENT_STATUS.md / `apim_policy.xml` this should never fire from APIM; if it does, root-cause via BETA_OPERATIONS_RUNBOOK §2.
- [ ] **Delete own photo from feed 3-dot** — your own photo card shows a 3-dot icon in the header; tap → "Delete" (red) → dark "Delete Photo?" dialog → Confirm → card disappears immediately (no 30s flicker). SnackBar "Photo deleted".
- [ ] **Non-uploader sees no 3-dot on others' photos** — another user's photo card in the same feed has no 3-dot icon. Tapping into detail → PopupMenu shows Save + Share but no Delete.
- [ ] **Photo detail delete — feed invalidation** — delete a photo from the AppBar PopupMenu in detail view → pop back → feed is already missing the photo (no 30s wait).
- [ ] **Organizer can remove others' photo from feed** — sign in as event organizer (a user who created the event but did NOT upload the target photo). Open the feed → 3-dot icon IS visible on the other user's photo card. Tap → menu reads "Remove" (not "Delete"). Tap → dark "Remove Photo?" dialog with body "You're removing this photo. It will be permanently deleted for everyone in this event." Confirm → card disappears immediately. SnackBar "Photo removed". On Device B (the original uploader), the photo disappears on the next 30s poll.
- [ ] **Organizer can remove others' photo from detail** — open someone else's photo in detail view as the event organizer → AppBar PopupMenu shows "Remove" (red). Confirm → returns to feed with item already gone.
- [ ] **Uploader self-delete copy unchanged** — when the uploader deletes their own photo (even if they're also the organizer), dialog still reads "Delete Photo?" / "This photo will be permanently deleted." (uploader precedence over organizer).
- [ ] **Non-organizer non-uploader sees no 3-dot on photos** — a third clique member who is neither uploader nor event organizer opens the feed → no 3-dot on others' photo cards. Photo detail PopupMenu shows Save + Share but no Delete.

## 5. Videos

### Upload

- [ ] **Record video** — in-app camera records video (≤5 min)
- [ ] **Upload from camera roll** — pick existing video, validation passes
- [ ] **Reject >5 min video** — client shows duration error
- [ ] **Reject non-MP4/MOV** — client shows format error (if testable)
- [ ] **Upload progress** — progress screen shows percentage, blocks back button during upload
- [ ] **Local pending card** — after upload starts, event feed shows local pending video card immediately
- [ ] **Play from local file** — tap local pending card → video plays instantly from device (zero network wait)
- [ ] **"Playing from your device"** subtitle visible during local playback

### Processing

- [ ] **Processing state** — card shows "Processing for sharing..." while transcoding
- [ ] **Video ready transition** — card transitions from processing → poster + play icon (within ~15-60s depending on source)
- [ ] **No duplicate cards** — only one card for the video at all times (local → processing → active)
- [ ] **Push notification** — Device B receives "New video ready" push (Device A does NOT get FCM push for own video)
- [ ] **Web PubSub update** — Device A's card upgrades automatically without manual refresh

### Playback

- [ ] **HLS playback** — Device B taps video, player opens, video plays via HLS
- [ ] **MP4 fallback** — if HLS fails (check logs), MP4 fallback plays
- [ ] **Poster image** — feed card shows poster frame before tap

### Actions

- [ ] **Save video to device** — player menu → "Save to Device" → video in gallery
- [ ] **Multi-select video download** — enter selection mode → video cards show checkboxes → select videos → download
- [ ] **Processing video excluded from selection** — video still processing → no checkbox shown
- [ ] **Share video** — player menu → "Share" → OS share sheet opens
- [ ] **Delete video** — player menu → "Delete" → confirmation → video removed from feed
- [ ] **Delete during processing** — delete a video that's still processing, card disappears cleanly
- [ ] **React to video** — on a ready video card in the feed, tap each of ❤️ 😂 🔥 😮 below the poster; pill highlights immediately and count increments. Tap again to unlike — count decrements and pill de-highlights. Pull-to-refresh: counts match server state. Bar should NOT appear on processing / failed / local-pending video cards.
- [ ] **Same-session add+remove on a fresh reaction** — like a photo OR video that you haven't reacted to before, then immediately unlike it without refreshing the feed. 30s later (after the feed polls), the reaction must stay removed — regression check for the pre-2026-04-17 bug where the DELETE silently no-op'd and the reaction re-appeared.

### Error handling

- [ ] **Video limit reached** — upload 10 videos, attempt 11th → error message shows correct limit ("10-video limit")
- [ ] **Network error** — start upload, disable WiFi mid-upload → error message, retry possible
- [ ] **Failed upload card** — if upload fails, card shows error state with Play + Retry buttons
- [ ] **Delete own video from feed 3-dot** — your own video card (any state: processing / failed / ready) shows a 3-dot icon in the header; tap → "Delete" → confirm → card disappears. SnackBar "Video deleted".
- [ ] **Non-uploader sees no 3-dot on others' videos** — another user's video card has no 3-dot icon. Player screen PopupMenu shows Save + Share but no Delete.
- [ ] **Delete own processing video — no ghost card** — tap Delete while the video is still transcoding → card disappears → does NOT re-appear as a "Polishing your video" ghost card after 30s (local-pending retire loop must have cleared it).
- [ ] **Organizer can remove others' video from feed** — sign in as event organizer (not the uploader). Feed shows 3-dot on the other user's video card. Tap → menu reads "Remove". Confirm → "Remove Video?" dialog with body "You're removing this video. It will be permanently deleted for everyone in this event." Confirm → card disappears. SnackBar "Video removed".
- [ ] **Organizer can remove others' video from player** — open someone else's video player as organizer → AppBar PopupMenu shows "Remove" (not "Delete"). Confirm → returns to feed with item gone.
- [ ] **Organizer can remove others' processing video** — uploader's video is still transcoding, organizer taps 3-dot → "Remove" → card disappears, no ghost re-render. Backend telemetry: `video_deleted` with `deleterRole='organizer'`.
- [ ] **Uploader self-delete copy unchanged (video)** — uploader deletes their own video → dialog still reads "Delete Video?" / "This video will be permanently deleted."
- [ ] **Non-organizer non-uploader sees no 3-dot on videos** — third clique member who is neither uploader nor organizer sees no 3-dot on others' video cards.
- [ ] **Dialog consistency** — open each destructive dialog (event delete, leave clique, delete clique, remove member, delete account, delete photo, delete video). All 7 dialogs are pixel-identical (dark `#1A2035` bg, 16px corners, red `#EF4444` destructive button, 70% alpha body text).

## 6. Direct Messages

- [ ] **Start DM thread** — Device A taps member in event → DM screen opens
- [ ] **Send message** — type and send, message appears instantly
- [ ] **Real-time delivery** — Device B receives message in real-time (Web PubSub)
- [ ] **Push notification** — if Device B is backgrounded, receives "Message from..." push
- [ ] **Tap notification** — tapping DM push opens the correct thread
- [ ] ~~**Rate limiting** — send >10 messages in 1 minute → 429 error shown~~ — **N/A as of 2026-04-27**: APIM rate-limit-by-key was removed (see DEPLOYMENT_STATUS.md). DM endpoints no longer return 429 from the gateway. If abuse becomes a real concern post-beta, add per-user / per-thread caps at the Functions layer
- [ ] **Read-only after expiry** — after event expires, DM thread is read-only

## 7. Notifications

- [ ] **In-app list** — notification bell shows list of all received notifications
- [ ] **Unread badge** — unread notifications show visual indicator
- [ ] **Mark as read** — tapping notification marks it read
- [ ] **Swipe to dismiss** — swipe right deletes individual notification
- [ ] **Clear all** — "Clear All" button with confirmation deletes all
- [ ] **Tap navigation** — tapping a notification navigates to the correct event/clique

### 7.1 New Event Real-Time Fan-Out (added 2026-04-30)

Cross-user real-time delivery — User B creates an event, User A (clique member, NOT the creator) sees it appear without restarting the app.

- [ ] **Foreground real-time (Android)**: User A on Home screen of clique-mate's clique. User B creates a new event in that clique. User A sees the new event card appear on Home within ~1 second. App Insights shows `new_event_push_sent` (server) and `new_event_received` (User A's device) correlated by `eventId`
- [ ] **Foreground real-time (iOS)**: same scenario on iPhone for User A
- [ ] **Backgrounded → tap FCM**: User A backgrounds the app. User B creates event. User A's device shows a heads-up FCM notification *"New Event!"* / *"{B} started '{eventName}' in {cliqueName}"* within ~3 sec. Tap → app opens to `/events/{eventId}` (Event Detail). `new_event_tapped_fcm` telemetry fires
- [ ] **Backgrounded → foreground via app icon**: User A backgrounds. User B creates event. User A foregrounds via app icon (NOT the notification). On resume, Web PubSub reconnects (`realtime_reconnected_on_resume` telemetry) and HomeScreen shows the new event card
- [ ] **In-app notifications list**: User A taps Notifications tab → sees a "New Event" row with event_rounded icon and gradient (electric-aqua → deep-blue). Body says *"{B} started '{eventName}' in {cliqueName}"*. Tap → routes to `/events/{eventId}`
- [ ] **Creator excluded**: User B (the creator) does NOT receive the FCM push, does NOT see a new notification row in their own list, and stays on Event Detail (where they navigated post-create) without disruption
- [ ] **Multi-device**: User A signed in on phone + tablet → both update simultaneously. Tap on either → both navigate independently
- [ ] **Sign-out cleanup**: User A signs out → Web PubSub disconnects (`disconnect()` log line in debug build) → User B creates event → User A's old device receives nothing
- [ ] **Re-sign-in re-connects**: User A signs back in → Web PubSub reconnects (`realtime_connected { reason: 'auth_start' }`) → next event from User B arrives real-time
- [ ] **Latent video_ready bug fix verification**: User A on Home (NOT on EventFeedScreen) → User B uploads a video to a shared event and waits for transcode → User A's `notificationsListProvider` invalidates within ~1 sec of `video_ready` delivery (verify by tapping Notifications tab and seeing the new row without pull-to-refresh). Pre-fix this would have required A to be on EventFeedScreen
- [ ] **No regression to Friday reminder** — verify §7.2 still passes

### 7.2 Weekly Friday Reminder (added 2026-04-30)

Client-only, scheduled via `flutter_local_notifications.zonedSchedule`. No FCM, no backend involvement. See `docs/NOTIFICATION_SYSTEM.md` "Weekly Friday Reminder."

- [ ] **Channel exists** — Settings → Apps → Clique Pix → Notifications shows "Reminders" channel alongside "Clique Pix"
- [ ] **Channel description** — tapping the "Reminders" channel shows description *"Weekly Friday-evening nudge to create an Event"*
- [ ] **Initial schedule on sign-in (Android)** — sign in fresh; App Insights shows `friday_reminder_scheduled` with `reason: 'cold_start'`, the device's IANA TZ, and a `next_fire_at` matching next Friday 17:00 in that TZ
- [ ] **Initial schedule on sign-in (iOS)** — same, on iPhone
- [ ] **Pending registration check (Android)** — `adb shell dumpsys notification | grep cliquepix_reminders` shows ID 9001 registered (or temporarily add a debug `pendingNotificationRequests()` print)
- [ ] **Friday 5 PM fire (Android — manual clock)** — disable auto-time, set device clock to Friday 16:59:50 local, wait. Notification displays with title *"Evening or weekend plans?"* + body *"Don't forget to create an Event and assign a Clique!"* within 15 minutes (`inexactAllowWhileIdle` window)
- [ ] **Tap routing** — tap the notification → app lands on `/events` (Home dashboard). App Insights shows `friday_reminder_tapped`
- [ ] **Mute via OS** — turn off the "Reminders" channel in OS Settings; manually fire again → notification suppressed; "Clique Pix" channel still delivers a regular FCM photo notification (proves channel separation)
- [ ] **Sign out cancels** — sign out, roll device clock to next Friday 17:00 → no notification fires. App Insights shows no new `friday_reminder_scheduled` for this device
- [ ] **Re-sign-in re-schedules** — sign back in → `friday_reminder_scheduled { reason: 'cold_start' }` (cache cleared on sign-out, treated as fresh)
- [ ] **TZ change recovery (Android)** — change device timezone (Settings → Date & Time → Time zone → e.g. America/Los_Angeles → America/New_York). Background app, resume. App Insights shows `friday_reminder_scheduled { reason: 'tz_changed', iana: 'America/New_York' }` and `next_fire_at` reflects the new TZ
- [ ] **No-op on resume when nothing changed** — bring app to background, resume immediately. App Insights shows `friday_reminder_skipped_tz_unchanged`, NOT a re-schedule
- [ ] **iOS UNUserNotificationCenter** — iOS Settings → Notifications → Clique Pix shows the app listed and notifications enabled. (iOS does not expose channels — "Reminders" is Android-only naming)
- [ ] **Multi-device** — sign in on phone + tablet, both at same TZ. Friday 5 PM fires on BOTH (accepted, documented behavior)
- [ ] **App reinstall** — uninstall app, reinstall, sign in → fresh `cold_start` schedule fires; previous schedule was wiped with the app
- [ ] **iOS time-jump caveat** — note that manual clock changes on iOS do NOT always cleanly re-evaluate `UNCalendarNotificationTrigger` schedules. If iOS manual-fire test fails, do NOT assume implementation is broken — wait for an actual Friday or test on Android

## 8. Auto-Deletion / Expiration

- [ ] **24h warning** — event created with 24h duration → "Event Expiring Soon" push arrives ~24h before expiry
- [ ] **Photos deleted** — after event expires, photos no longer load (SAS URLs invalid)
- [ ] **Videos deleted** — after event expires, video playback fails gracefully
- [ ] **Event removed** — expired event disappears from event list
- [ ] **Device copies preserved** — photos/videos saved to device still accessible after cloud expiry

## 9. Edge Cases

- [ ] **App kill during upload** — kill app during video upload, reopen → upload can be retried
- [ ] **Offline mode** — open app with no connection → cached content visible, error states for network actions
- [ ] **Background → foreground** — background app for 5 minutes, bring to foreground → feed refreshes
- [ ] **Pull to refresh** — pull down on event feed → content refreshes
- [ ] **Empty states** — new user with no cliques/events → appropriate empty state messages shown
- [ ] **Account deletion** — Settings → Delete Account → confirm → user removed, can't sign in

## 10. Profile Pictures (Avatars)

- [ ] **First-sign-in welcome prompt — Yes path** (fresh test account): sign up + pass age gate → lands on Events → welcome modal "Make yourself known" appears. Tap "Add a Photo" → picker sheet → crop + filter + frame → Save. Verify: avatar appears on Profile hero; kill & reopen app → prompt does NOT reappear (`shouldPromptForAvatar` now false because blob path is set).
- [ ] **First-sign-in welcome prompt — Maybe Later** (fresh account): tap "Maybe Later" → modal closes, no upload. Kill & relaunch → prompt does NOT reappear. SQL: `SELECT avatar_prompt_snoozed_until FROM users WHERE email_or_phone='<test>'` returns ~7 days out.
- [ ] **First-sign-in welcome prompt — No Thanks** (fresh account): tap "No Thanks" → modal closes. Relaunch → prompt does NOT reappear. SQL: `avatar_prompt_dismissed = TRUE`.
- [ ] **Cross-device welcome honoring**: sign in on iPhone, tap "Maybe Later". Sign in on Android 5 minutes later → prompt does NOT appear.
- [ ] **Cross-platform welcome (web)**: same user signs in at clique-pix.com → welcome modal appears if not yet dismissed/snoozed.
- [ ] **Profile tap to upload**: Profile → tap 'GW' gradient ring → bottom sheet → Take Photo → crop square → pick Warm filter → pick violet→pink frame preset → Save. Verify: confetti fires (first time only), haptic feedback, avatar updates in place.
- [ ] **Avatar on own photo cards**: navigate to an event feed where the user has uploaded a photo → within ≤30s (poll cycle) headshot appears on the card (not 'GW').
- [ ] **Avatar on other members' devices**: Device B opens the same event → verify uploader's headshot appears on their cards.
- [ ] **Avatar in DMs**: Device B opens a DM thread with the uploader → headshot in thread header + message bubbles.
- [ ] **Remove avatar**: Profile → tap avatar → Remove → confirm → avatar reverts to initials on Profile immediately; on feed cards after next poll.
- [ ] **Confetti one-shot**: second upload of a new headshot does NOT fire confetti again.
- [ ] **HEIC from iOS library**: pick a HEIC photo as avatar → JPEG conversion happens (network tab shows `image/jpeg` on the blob PUT).
- [ ] **PNG drag-drop (web)**: drag-drop a screenshot (.png) onto the web AvatarEditor → uploads as PNG → renders correctly.
- [ ] **Account delete cleans avatar blobs**: Profile → Delete Account → confirm → subsequent `GET https://stcliquepixprod.blob.core.windows.net/photos/avatars/{userId}/original.jpg` returns 404.

## 11. Profile & Legal

- [ ] **Settings tile order** — first settings group reads top-to-bottom: `About Clique Pix → Terms of Service → Privacy Policy → Contact Us`
- [ ] **Privacy Policy** — tap "Privacy Policy" on profile screen → in-app browser opens `https://clique-pix.com/docs/privacy` (legacy `/privacy.html` 301-redirects to this)
- [ ] **Terms of Service** — tap "Terms of Service" on profile screen → in-app browser opens `https://clique-pix.com/docs/terms` (legacy `/terms.html` 301-redirects to this)
- [ ] **Privacy Policy content** — page loads, 14 sections visible, covers photos, videos, DMs, effective date April 13, 2026
- [ ] **About dialog** — tap "About Clique Pix" → dialog shows version and "Private photo and video sharing" legalese
- [ ] **Contact Us dialog** — tap "Contact Us" → dark-themed dialog shows `support@xtend-ai.com` (selectable)
- [ ] **Contact Us — Copy Email** — tap "Copy Email" → dialog closes, "Email copied!" snackbar appears; pasting into another app yields `support@xtend-ai.com`
- [ ] **Contact Us — Send Email** — tap "Send Email" → device mail app opens with To `support@xtend-ai.com` and Subject `Clique Pix Support` pre-populated (Android requires the `mailto` `<queries>` entry in `AndroidManifest.xml`)
- [ ] **Delete account** — confirmation dialog appears, account deletion succeeds, redirects to login

## 11. Performance Checks

- [ ] **Photo upload speed** — capture to visible in feed: < 5 seconds on WiFi
- [ ] **Video transcoding** — compatible source (H.264 SDR): ready within ~25 seconds total
- [ ] **Feed scroll** — 60fps, no jank with 20+ items
- [ ] **App cold start** — splash to usable: < 3 seconds
- [ ] **Thumbnail load** — feed thumbnails load within 500ms on 4G
- [ ] **`deleterRole` telemetry recorded** — after running the organizer-delete tests above, query App Insights:
  ```kusto
  customEvents
  | where timestamp > ago(1h)
  | where name in ("photo_deleted","video_deleted")
  | where tostring(customDimensions.deleterRole) == "organizer"
  | project timestamp, name,
            uploaderId = tostring(customDimensions.uploaderId),
            eventOrganizerId = tostring(customDimensions.eventOrganizerId),
            userId = tostring(customDimensions.userId)
  ```
  Should return one row per organizer-delete with `userId == eventOrganizerId` and a non-empty `uploaderId` distinct from `eventOrganizerId`.
- [ ] **Background polling pauses** — open event feed (30 s polling active) → background the app → wait 2 minutes → check App Insights `customEvents` for `event_id=<eventId>` listings during the 2 min. **Should be zero** (polling pauses on `AppLifecycleState.paused`). Foreground the app → one immediate refresh fires + polling resumes.
- [ ] **WorkManager fires at most once per 4 hours** — `customEvents | where name == "wm_refresh_success" | summarize count() by bin(timestamp, 1h)` should show ≤ 1 per hour (designed cadence ~3 / day). If it exceeds, the 4 h `wm_last_run_at_ms` SharedPreferences floor in `background_token_service.dart:callbackDispatcher` is broken.

---

## 12. Web Client (`https://clique-pix.com`)

Run in a fresh browser window per test where possible; for cross-browser coverage hit the full flow in Chrome AND Safari at minimum. Incognito for first-time-user tests.

### 12.1 Landing page (unauthenticated)

- [ ] **First-visit render** — fresh incognito → `https://clique-pix.com` → lands on marketing page; no login redirect, no flash of a sign-in screen
- [ ] **Hero** — reads "Your moments. Your people. No strangers."; gradient spotlights drift gently behind the content; phone mockup renders on the right with a `DemoMediaCard`
- [ ] **Tappable reactions** — clicking ❤️ 😂 🔥 😮 in the phone mockup increments the counter; clicking again decrements
- [ ] **Nav CTA (unauthed)** — top-right reads "Sign in" → routes to `/login`
- [ ] **HowItWorks** — 3 steps in order: Start an Event / Create or invite your Clique / Share, react, save what matters
- [ ] **App Store + Google Play badges** — render with styled black background + icons; `href="#"` placeholder is expected until listings publish
- [ ] **Live QR code** — Download section renders a scannable QR of `https://clique-pix.com`; scan with phone camera → opens the site
- [ ] **Footer links** — Privacy routes to `/docs/privacy`, Terms to `/docs/terms`

### 12.2 Landing page (authenticated)

- [ ] **Nav CTA (authed)** — sign in, then navigate back to `/` in same tab; top-right now reads "My Events →" (no auto-redirect)
- [ ] **Hero primary CTA** — authed, the "Get Started" button reads "Open my events" and routes to `/events`

### 12.3 Auth

- [ ] **Sign in** — Get Started → Entra hosted form → returns to `/auth/callback` → lands on `/events` without any visible error state
- [ ] **Age gate** — if a new test account under 13 signs up, the backend returns 403 AGE_VERIFICATION_FAILED → toast "You must be at least 13…" → logoutRedirect back to `/`
- [ ] **Network tab** — every request to `api.clique-pix.com` carries `Authorization: Bearer …`; no 401s in a normal session
- [ ] **Sign-out** — profile → sign out → MSAL clears → lands on `/` with "Sign in" visible again

### 12.4 Cliques

- [ ] **Create** — Cliques tab → New Clique → submit → URL becomes `/cliques/<id>?invite=1` and the **Invite dialog auto-opens** with a scannable QR + readable invite code
- [ ] **Print QR card** — Invite dialog → Print QR code → new route renders branded card with gradient header/footer, logo, "You're invited to join", Clique name, QR, and code. Print preview shows full-color gradient bands (no need to toggle "Background graphics")
- [ ] **Accept invite on web** — copy invite link → paste in incognito / second account → sign in → lands on `/invite/<code>` → "Joined" toast → routed to the Clique as a new member
- [ ] **Accept invite on mobile** — tap the same link on a physical iPhone/Android → Flutter app opens via Universal Links / App Links

### 12.5 Events + media

- [ ] **Create event** — works end-to-end, including picking or creating a Clique inline
- [ ] **Upload photo** — drag-drop a JPEG or HEIC → compressed + uploaded → appears in feed card within seconds
- [ ] **HEIC on Chrome** — HEIC from iPhone library pre-converts via heic2any and uploads successfully
- [ ] **Upload video** — pick a short (10-30 s) MP4/MOV → progress bar shows filename + percent + MB counter → card appears "Processing" → within ~30 s (fast path) transitions to active via Web PubSub `video_ready`
- [ ] **Video validation** — try a file > 500 MB OR > 5 min → rejected client-side before any network call
- [ ] **Media card** — each card shows uploader avatar (initials + gradient) + name + relative time + photo + reaction pills + download icon
- [ ] **Reactions** — tap ❤️ on a photo → counter increments optimistically → persists after page refresh
- [ ] **Delete own media** — 3-dot menu visible only on your own cards → Delete → confirm dialog → card disappears
- [ ] **Organizer can remove others' media on web** — sign in (browser 2) as the event organizer who is NOT the uploader → 3-dot is visible on the uploader's photo + video cards → label reads "Remove" → confirm dialog title is "Remove this photo?" / "Remove this video?" with body about permanent deletion for everyone → confirm → toast "Photo removed" / "Video removed" → card vanishes. Test in BOTH Chrome AND Safari (HLS path differs)
- [ ] **Non-organizer non-uploader on web** — sign in as a third clique member who is neither uploader nor organizer → no 3-dot icon visible on others' cards in the feed
- [ ] **Photo download** — download icon saves `cliquepix-<id>.jpg` to Downloads folder
- [ ] **Video download** — download icon on a video card saves the MP4 fallback as `cliquepix-<id>.mp4`
- [ ] **Video playback (lightbox)** — tap a video card → lightbox opens; video auto-initializes and plays. Test on Safari (native HLS) AND Chrome (`hls.js` loads as a separate chunk)
- [ ] **SAS-expiry recovery** — leave the player paused > 15 minutes, then seek → player should re-fetch `/playback` and resume. Look for `web_playback_sas_recovered` in App Insights

### 12.6 DMs + notifications

- [ ] **DM thread real-time** — two accounts in the same Clique/event → account A sends a message → account B sees it within ~1 s (no refresh)
- [ ] **Rate limit** — send >10 messages in a minute → toast "Slow down — max 10 messages per minute"
- [ ] **Notifications bell** — a new photo upload by someone else triggers the notification bell badge (polling every 60s + Web PubSub real-time while the tab is open)
- [ ] **Expired event** — messages in an expired event's thread are read-only (composer hidden, banner shown)

### 12.7 Cross-browser matrix

- [ ] Chrome latest (desktop) — full pass
- [ ] Safari latest (desktop) — native HLS playback path, Web Share fallback
- [ ] Firefox latest (desktop) — `hls.js` playback path
- [ ] Edge latest (desktop) — should match Chrome
- [ ] iOS Safari — sign in, video playback, file picker (HEIC native)
- [ ] Android Chrome — video playback, file picker, drag-drop

### 12.8 Accessibility + performance

- [ ] **Keyboard navigation** — tab through landing page hero → CTA → badges → sections; no keyboard traps
- [ ] **`prefers-reduced-motion`** — enable in OS accessibility settings → gradient-drift animations stop on the landing hero; scroll-reveal falls through to immediate visibility
- [ ] **Lighthouse** — desktop, incognito landing page → Performance ≥ 90, Accessibility ≥ 90
- [ ] **Bundle budget** — initial JS ≤ 400 KB total / 130 KB gzip; `hls.js` loads as a separate on-demand chunk

---

## Test Results Template

| Test | iOS | Android | Notes |
|------|-----|---------|-------|
| 1. Sign in | | | |
| 2. Create clique | | | |
| ... | | | |

Fill in with Pass / Fail / Skip and any notes for each release.

---

## Known Limitations (Beta)

- No notification batching — multiple rapid reactions = multiple pushes
- No offline queue — actions require network connectivity
- Video upload requires app to stay open (no background upload)
- SAS token expiry (15 min) may interrupt paused video playback
- Web PubSub token refresh not auto-negotiated before expiry
