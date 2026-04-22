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
- [ ] **Upload error — friendly message, not raw exception** — if the upload fails, the Share Photo screen shows a user-facing message (e.g., "Upload permission expired. Tap retry." / "Network timed out. Check your connection and retry."), NOT a raw `DioException`/stack-trace dump. The retry button re-runs the full flow from a fresh SAS.
- [ ] **Delete own photo from feed 3-dot** — your own photo card shows a 3-dot icon in the header; tap → "Delete" (red) → dark "Delete Photo?" dialog → Confirm → card disappears immediately (no 30s flicker). SnackBar "Photo deleted".
- [ ] **Non-uploader sees no 3-dot on others' photos** — another user's photo card in the same feed has no 3-dot icon. Tapping into detail → PopupMenu shows Save + Share but no Delete.
- [ ] **Photo detail delete — feed invalidation** — delete a photo from the AppBar PopupMenu in detail view → pop back → feed is already missing the photo (no 30s wait).

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
- [ ] **Dialog consistency** — open each destructive dialog (event delete, leave clique, delete clique, remove member, delete account, delete photo, delete video). All 7 dialogs are pixel-identical (dark `#1A2035` bg, 16px corners, red `#EF4444` destructive button, 70% alpha body text).

## 6. Direct Messages

- [ ] **Start DM thread** — Device A taps member in event → DM screen opens
- [ ] **Send message** — type and send, message appears instantly
- [ ] **Real-time delivery** — Device B receives message in real-time (Web PubSub)
- [ ] **Push notification** — if Device B is backgrounded, receives "Message from..." push
- [ ] **Tap notification** — tapping DM push opens the correct thread
- [ ] **Rate limiting** — send >10 messages in 1 minute → 429 error shown
- [ ] **Read-only after expiry** — after event expires, DM thread is read-only

## 7. Notifications

- [ ] **In-app list** — notification bell shows list of all received notifications
- [ ] **Unread badge** — unread notifications show visual indicator
- [ ] **Mark as read** — tapping notification marks it read
- [ ] **Swipe to dismiss** — swipe right deletes individual notification
- [ ] **Clear all** — "Clear All" button with confirmation deletes all
- [ ] **Tap navigation** — tapping a notification navigates to the correct event/clique

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

## 10. Profile & Legal

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
