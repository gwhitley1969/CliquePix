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
- [ ] **Token persists** — kill app, reopen, still signed in
- [ ] **Token refresh** — leave app closed for 6+ hours, reopen, still signed in (Android: verify AlarmManager fired in logs)
- [ ] **Sign out** — tap sign out, returns to login screen, reopening app shows login
- [ ] **Re-login after 12h** — if token expired, graceful "Welcome back" dialog appears (Layer 5)
> **Age gate enforced server-side** in `authVerify` via the `dateOfBirth` token claim. Entra collects DOB once at signup; backend reads the claim on first login; under-13 returns HTTP 403 and the Entra account is best-effort deleted via Microsoft Graph. See `docs/AGE_VERIFICATION_RUNBOOK.md`.

- [ ] **Age gate — new sign-up over 13** — tap Get Started → Entra sign-up form asks for DOB once → **DOB ≥ 13** (e.g. 1990-05-15) → signup completes → app lands on home screen. App Insights: `age_gate_passed` event with coarse `ageBucket` (never raw DOB). SQL: `SELECT age_verified_at FROM users WHERE email_or_phone = '<test>'` returns a recent timestamp.
- [ ] **Age gate — new sign-up under 13** — tap Get Started → Entra sign-up form → **DOB < 13** (e.g. 2020-01-01) → Entra signup completes, but Clique Pix shows "You must be 13+ to use Clique Pix" and does NOT let them in. App Insights: `age_gate_denied_under_13`. Within ~60s verify the Entra account is deleted: `az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?\$filter=mail eq '<test-email>'"` returns empty `value: []`.
- [ ] **Age gate — returning user — no re-prompt** — sign out of a valid over-13 account, tap Get Started → Entra sign-in only (no DOB field) → lands on home screen. `age_verified_at` unchanged (COALESCE preserves it).
- [ ] **Age gate — different account on same device** — sign out, register a NEW account with a different email → Entra sign-up form asks for DOB (new account). Independent of prior account's verification.
- [ ] **Age gate — JWT claim check** — decode a post-login access token at `https://jwt.ms`. Verify `extension_<GUID>_dateOfBirth` is present in claims.
- [ ] **Age gate — endpoint check** — unauth `curl -X POST https://func-cliquepix-fresh.azurewebsites.net/api/auth/verify` returns 401 with `UNAUTHORIZED`. `validate-age` endpoint returns 404 (deleted — expected).

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
- [ ] **Privacy Policy** — tap "Privacy Policy" on profile screen → in-app browser opens `https://clique-pix.com/privacy.html`
- [ ] **Terms of Service** — tap "Terms of Service" on profile screen → in-app browser opens `https://clique-pix.com/terms.html`
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
