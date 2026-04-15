# Clique Pix — Open Beta Smoke Test Plan

**Last Updated:** April 13, 2026

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

### Error handling

- [ ] **Video limit reached** — upload 10 videos, attempt 11th → error message shows correct limit ("10-video limit")
- [ ] **Network error** — start upload, disable WiFi mid-upload → error message, retry possible
- [ ] **Failed upload card** — if upload fails, card shows error state with Play + Retry buttons

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
