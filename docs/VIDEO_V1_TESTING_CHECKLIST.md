# Video v1 — Manual On-Device Testing Checklist

## What this is

The end of Phase 7 of the video v1 implementation requires real-device testing because:
1. Most video bugs surface as platform-specific playback or capture issues that can't be reproduced in CI or unit tests
2. The full upload→transcode→playback round-trip needs to be verified on real network conditions (WiFi + LTE)
3. Push notification routing must be tested with the device backgrounded
4. The user contribution defaults (FFmpeg parameters, retry policy, processing UX copy) need real-eye review

This checklist is structured so you can power through it in 30-45 minutes on one device, longer if you also test the second platform. **Don't merge `feature/video` to `main` until at least one full pass is green.**

## Prerequisites

1. The latest release APK is installed on your test device. Build with:
   ```
   cd app
   flutter clean
   flutter pub get
   flutter build apk --release --target-platform android-arm64
   ```
   Output: `app/build/app/outputs/flutter-apk/app-release.apk`
2. You're signed into the app with your Entra account
3. You have an active event ("Day Drinking" or similar) you can upload to
4. You have a second test account / device available for the multi-user push notification scenarios (optional but recommended)
5. Your phone has at least 1 sample video in the gallery — record a 30-second clip if needed

## Test scenarios

### 1. Video upload — happy path

- [ ] Open the app, sign in, navigate to your active event
- [ ] You should see two buttons side-by-side: "Photo" (gradient) and "Video" (outlined)
- [ ] Tap "Video" — VideoCaptureScreen opens
- [ ] Tap "Choose from gallery" — system picker opens
- [ ] Pick a 30-second video
- [ ] Verify the spinner appears with "Checking your video..."
- [ ] After validation succeeds, the upload screen takes over with progress 0%
- [ ] Watch the progress percentage tick up smoothly (you'll see one update per 4MB block uploaded)
- [ ] Verify "Uploading 5%" → "Uploading 50%" → "Uploading 99%" → "Finalizing..." → upload completes
- [ ] After completion, you're returned to the event detail screen
- [ ] **The video card appears in the feed with the "Almost ready... / Polishing your video" placeholder**
- [ ] Wait ~1-2 minutes for transcoding to complete
- [ ] The card transitions automatically to show the poster + duration overlay + play icon
  - If it doesn't transition automatically, pull-to-refresh the feed

**Pass criteria:** The video appears in the feed within 2-3 minutes of selecting it.

### 2. Video playback — HLS path

- [ ] In the event feed, find the video card (poster + play icon visible)
- [ ] Tap the video card — VideoPlayerScreen opens
- [ ] Verify a loading spinner appears, then the video starts playing automatically
- [ ] The chewie controls should appear at the bottom (play/pause, scrub bar, fullscreen)
- [ ] Scrub to a different position — playback resumes from there
- [ ] Tap fullscreen — orientation rotates and video fills the screen
- [ ] Exit fullscreen
- [ ] Tap back to return to the feed

**Pass criteria:** The video plays without stuttering, controls work, fullscreen toggles correctly.

### 3. Video upload — validation failures

For each of these, verify the user sees a friendly error message and the upload doesn't start:

- [ ] **Duration too long:** Pick a video > 5 minutes from your gallery
  - Expected message: "Videos must be 5 minutes or shorter. Please trim your video and try again."
- [ ] **Per-user limit reached:** Upload 5 videos to one event, then try a 6th
  - Expected message: "You've reached the 5-video limit for this event. Delete a video to upload another."
- [ ] **Cancel during upload:** Start an upload, then close the app via the system close gesture
  - Expected: app closes cleanly. No data corruption when you re-open.

### 4. Resume after interrupt

This tests the block upload's resume mechanism.

- [ ] Pick a video for upload
- [ ] Start the upload — wait until it's ~30-60% done
- [ ] **Force-quit the app** (swipe up from app switcher, NOT just background it)
- [ ] Re-open the app, navigate to the same event
- [ ] Pick the same video again
- [ ] **The upload should resume from where it left off**, not start from 0%
  - You'll see the progress jump quickly past the already-uploaded blocks
- [ ] Let it finish and verify the video appears in the feed

**Pass criteria:** Re-uploading the same file is significantly faster than the first upload.

### 5. Push notifications — foreground

- [ ] Sign in with Account B on a second device, join the same clique
- [ ] On Account A's device, open the event detail screen and KEEP the app in foreground
- [ ] On Account B's device, upload a video to the same event
- [ ] Wait ~1-2 minutes for transcoding to complete
- [ ] **On Account A's device:** the new video card should appear in the feed without manual refresh, transitioning from placeholder to ready state in real-time

This tests the Web PubSub `video_ready` push (no FCM involved when foreground).

### 6. Push notifications — background

- [ ] On Account A's device, navigate AWAY from the event (e.g., to the home tab) or BACKGROUND the app entirely
- [ ] On Account B's device, upload a video to the same event
- [ ] Wait ~1-2 minutes
- [ ] **On Account A's device:** an FCM push notification appears with title "New video ready"
- [ ] Tap the notification
- [ ] **The app opens directly to the video player screen** for that specific video

This tests the FCM `video_ready` push routing in `push_notification_service.dart`.

### 7. Save to device

- [ ] Open a video in the player screen
- [ ] Use the share / save mechanism (TODO: confirm how this is exposed in the player UI — may need adding)
- [ ] Verify the video appears in your phone's gallery / Photos app

**Note:** Video save-to-device may not have a UI button yet — the `saveVideoToGallery` method exists in `storage_service.dart` but isn't wired to a player button. This is a v1.5 polish item.

### 8. Reactions on videos

- [ ] In the feed, find a ready (non-processing, non-failed) video card — the ❤️ 😂 🔥 😮 row is visible below the poster
- [ ] Tap each reaction in turn — pill highlights + count increments immediately
- [ ] Tap an active reaction again — pill de-highlights, count decrements, DELETE fires against `/api/videos/{id}/reactions/{reactionId}`
- [ ] Pull-to-refresh — counts match backend state (no flicker)
- [ ] Verify the bar does NOT appear on a processing video card, failed video card, or a local-pending (still-uploading) video card — backend rejects reactions on non-active media, UI gates on `video.isReady`

**Implementation note (2026-04-17):** `ReactionBarWidget` was refactored from photo-repo-coupled to media-agnostic (callback-based). Both `photo_card_widget.dart` and `video_card_widget.dart` now use the same widget via `onAdd` / `onRemove` closures constructed from their respective repos.

### 9. Video deletion

Delete is exposed in **two** places, gated by `canDelete = isUploader || isOrganizerDeletingOthers` (since 2026-04-28):
- **Feed card 3-dot menu** (`MediaOwnerMenu` in `video_card_widget.dart`) — visible on your own videos in all three states (processing / failed / ready), and on OTHER members' videos in events YOU created. Hidden when the feed is in multi-select download mode. Menu label flips between "Delete" (self) and "Remove" (organizer-of-others).
- **Video player AppBar PopupMenu** — gated on `canDelete = isUploader || isOrganizerDeletingOthers`, computed from `videoDetailProvider` + `eventDetailProvider(eventId)`.

Backend authorization runs via `canDeleteMedia` (`backend/src/shared/utils/permissions.ts`); uploader takes precedence over organizer when both apply. Telemetry: `video_deleted` carries `deleterRole` ∈ `'uploader' | 'organizer'` plus `uploaderId` and `eventOrganizerId` for moderation auditing.

**Self-uploader delete:**
- [ ] Find a video you uploaded; tap its 3-dot in the feed header → "Delete" (red) → dark "Delete Video?" dialog → Confirm → card disappears immediately. SnackBar "Video deleted".
- [ ] Try the same from the player screen PopupMenu — same flow, pops back to feed on success.
- [ ] Delete while video is still processing → card disappears → NO ghost "Polishing your video" card re-appears (local-pending retire loop).
- [ ] Verify the corresponding blob is cleaned up by checking Azure Storage Explorer (or wait for the next timer cleanup).

**Organizer-deleting-others (added 2026-04-28):**
- [ ] Sign in as the event organizer (you created the event but did NOT upload the target video). The other user's video card shows the 3-dot icon. Tap → menu reads "Remove" (red, not "Delete"). Tap → dark "Remove Video?" dialog with body "You're removing this video. It will be permanently deleted for everyone in this event." Confirm → card disappears. SnackBar "Video removed".
- [ ] Same flow from the video player AppBar PopupMenu when opening someone else's video as the organizer.
- [ ] Organizer-delete works on a still-processing video (organizer + Q5 mechanics). Card disappears, no ghost card re-renders.
- [ ] Telemetry: `customEvents | where name == "video_deleted" and tostring(customDimensions.deleterRole) == "organizer"` returns the row with `userId == eventOrganizerId` and a non-empty `uploaderId` distinct from `userId`.

**Negative tests:**
- [ ] Non-uploader, non-organizer viewing the same clique sees NO 3-dot on your videos.
- [ ] Organizer deleting their own upload sees the **self-uploader** copy ("Delete Video?", SnackBar "Video deleted") — uploader takes precedence over organizer in `canDeleteMedia`.

### 10. Event expiration

This is hard to test in real-time without manipulating the database. Skip in v1 testing — verified during the integration test in Phase 5 against synthetic data.

### 11. iOS-specific tests

If you have an iOS device available:

- [ ] Build and install the iOS version: `flutter build ios --release`
- [ ] Repeat scenarios 1-6 above
- [ ] Verify the iOS permission prompts work (camera, microphone, photo library)
- [ ] Verify HEVC playback specifically — record an iPhone video in "High Efficiency" mode and confirm it plays after upload

## Telemetry verification (App Insights)

After running the test scenarios, verify telemetry events are firing in Application Insights. Open the Azure Portal → `appi-cliquepix-prod` → Logs, and run:

```kql
customEvents
| where timestamp > ago(1h)
| where name startswith "video_"
| summarize count() by name
| order by name asc
```

**You should see at minimum:**
- `video_upload_started` (1 per upload attempt)
- `video_upload_committed` (1 per successful commit)
- `video_transcoding_queued` (1 per committed upload)
- `video_transcoding_completed` (1 per successful transcode)
- `video_played` (1 per playback)
- `video_ready_push_sent` (1 per successful transcode that has notifiable recipients)

**You may also see (depending on what you tested):**
- `video_upload_failed` (validation rejections)
- `video_upload_block_failed` (network blip during upload)
- `video_transcoding_failed` (if a video failed transcoding)
- `video_processing_callback_idempotent_skip` (if the callback was retried)
- `video_hls_manifest_cache_hit` / `_cache_miss` (per playback)

If any of the "should see" events are missing, the corresponding code path isn't being exercised. Investigate.

## Cost verification

After 24 hours of testing, check the Azure Cost Analysis for `rg-cliquepix-prod`:

```bash
az consumption usage list --start-date 2026-04-08 --end-date 2026-04-08 --query "[?contains(instanceName, 'cracliquepix') || contains(instanceName, 'caj-cliquepix')].{name:instanceName, cost:pretaxCost}" -o table
```

Expected total daily cost during testing: under $1 (mostly ACR + a few transcoder runs).

## Known issues and follow-ups for v1.5

These were noted during the implementation and don't block v1 merge:

1. **KEDA scaler didn't auto-trigger during Phase 5 integration test.** Manual `az containerapp job start` was needed. Could be polling-interval lag, scaler config, or RBAC. Investigate before relying on automatic scale-up under real load.
2. **`allowSharedKeyAccess: True` on storage account** — CLAUDE.md says it should be `False`. Audit code paths and disable it.
3. ~~**Video reactions UI not wired** — `video_card_widget.dart` doesn't currently show the reaction bar. Add it to match `photo_card_widget.dart`.~~ **Shipped 2026-04-17** — `ReactionBarWidget` refactored to media-agnostic callback API, rendered on ready video cards. Video player screen reactions remain a separate follow-up (out of scope for this change).
4. **Save-to-device button missing on player screen** — the `saveVideoToGallery` service method exists but no button calls it. Add to the player UI.
5. **Video delete button missing** — the API endpoint exists but no UI calls it. Add a delete action to the video card or player.
6. **Function App on Node 20** (EOL 2026-04-30) — migrate to Node 24.
7. **Internal callback uses function key, not managed identity** — works but a real Azure AD app registration for the Function App would be cleaner. Revisit in v1.5.
8. **Video metadata stripping (EXIF-equivalent)** — videos don't get their metadata stripped client-side like photos do. Could leak GPS coordinates if the source video has them.

## Sign-off

Once all "Pass criteria" items are checked and you're satisfied with the user experience:

- [ ] Update the "Phase 7" row in `docs/DEPLOYMENT_STATUS.md` to ✅
- [ ] Merge `feature/video` to `main`:
  ```bash
  git checkout main
  git pull --ff-only origin main
  git merge --ff-only feature/video
  git push origin main
  git branch -d feature/video
  git push origin --delete feature/video
  ```
- [ ] Build the production release APK and distribute to your testers

If anything fails, fix the bug, push to `feature/video`, rebuild, re-test the failed scenario, and don't merge until clean.
