# Local-First Uploader Video Playback — Claude Code Handoff

## Purpose

This document defines the **required architecture and implementation changes** for Clique Pix video so that:

- the **uploader** can play their just-recorded or just-selected video **immediately from the local device**
- other **members of the clique** continue to consume the **cloud-hosted processed version**
- the current Azure-based media pipeline remains intact for shared playback, compatibility normalization, expiration, and governance

This is **not** a full rewrite of the video feature.

This is a **targeted architecture correction** to improve UX without throwing away the existing work already done on the `feature/video` branch.

---

## Product decision

### Required behavior

1. When a user records or selects a video, they must be able to **play it locally right away** on their own device.
2. The uploader must **not** have to wait for Azure upload, queueing, transcoding, HLS generation, or poster generation before they can watch their own video.
3. Other clique members must **not** play the uploader's raw original capture from the uploader's device.
4. Other clique members must continue to play the **processed cloud version** from Azure.
5. The processed cloud version remains the system of record for shared playback.
6. Download/save for other users remains **optional**, not automatic.

### Why this decision is correct

This gives us the best tradeoff:

- **best UX for uploader** → instant local playback
- **best compatibility for clique members** → normalized cloud playback
- **best control over lifecycle** → Azure Blob remains source of truth for shared media
- **best cost discipline** → do not auto-download videos to all devices

---

## Non-goals

The following are **not** part of this change:

- no peer-to-peer streaming
- no uploader-device-origin playback for other users
- no full media architecture rewrite
- no replacement of Blob Storage with another vendor
- no auto-download of shared videos to member devices
- no adaptive bitrate ladder work in this task
- no CDN redesign in this task
- no background-upload native-service implementation in this task unless already trivial

---

## Current problem

The current branch already made the right move by uploading originals to Azure and processing them in the cloud.

That part should stay.

The remaining UX issue is this:

- the uploader still experiences a wait before the video feels available
- the app currently ties the uploader's usable playback too closely to cloud upload/commit/processing state
- even though a `preview_url` exists after commit, it still depends on successful upload + backend response
- this means the uploader does **not** get the fastest possible experience

That is the wrong user experience for the person who just captured the video.

They already have the file on the device. We should use it.

---

## Architecture decision

## Final model

### Uploader path

**Local-first playback**

The uploader's client should:

1. capture or pick the video
2. validate it locally
3. create a **local pending video item** in app state immediately
4. allow immediate playback from the local file path
5. start upload in the background/foreground upload flow
6. reconcile that local item with the server-side `videoId` once upload-url + commit succeed
7. replace local-only playback with normal cloud playback once processing completes

### Clique member path

**Cloud-first playback**

Other clique members should:

1. see a video only when it is represented in backend feed state
2. play the processed Azure-hosted version
3. use HLS first and MP4 fallback exactly as currently designed
4. optionally download/save if they choose

### Shared backend path

Keep the current backend model:

- original uploaded to Azure Blob
- queue-driven processing
- Container Apps transcoder
- HLS manifest + MP4 fallback + poster
- video_ready signal via Web PubSub / push
- expiration and cleanup in Azure

---

## Hard requirements for Claude Code

## 1. Do not remove the existing Azure shared playback design

Keep these existing concepts:

- Blob Storage for original and derived assets
- block upload flow
- server-side processing pipeline
- processed video for shared playback
- Web PubSub `video_ready`
- HLS + MP4 fallback playback for shared videos

Do **not** replace the current shared playback design with device-origin sharing.

---

## 2. Add a local-only uploader playback state

A video uploaded by the current user must support a **local playback state** before the backend has finished processing.

We need a client-side concept like this:

```dart
class LocalPendingVideo {
  final String localTempId;      // client-generated UUID
  final String eventId;
  final String localFilePath;
  final int durationSeconds;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final DateTime createdAt;
  final UploadStage uploadStage; // localOnly | uploading | committing | processing | failed | complete
  final String? serverVideoId;
  final String? errorMessage;
}
```

This may be a dedicated model or folded into an existing view model, but the behavior must exist.

### Required behavior

- the app creates this local item immediately after validation
- this local item appears in the event feed immediately for the uploader
- it should **not** be shown to other clique members until backend/shared state exists
- it must be tappable by the uploader for immediate playback

---

## 3. Event feed must merge local uploader items with server items

The event feed currently merges photos and videos from backend providers.

That is no longer enough.

The uploader's event feed must also merge in **client-local pending videos**.

### Required behavior

For the current logged-in uploader only:

- show local pending video cards in the event feed immediately
- place them in correct chronological order
- visually distinguish them as local/pending/processing as needed
- once the backend record exists and is reconciled, avoid duplicate cards

### Deduplication requirement

You must prevent this bad UX:

- local temporary card appears
- later backend processing card appears separately
- uploader now sees two copies of the same video

That is unacceptable.

### Required reconciliation strategy

At minimum:

- local item starts with `localTempId`
- when server returns `videoId`, associate local item with `serverVideoId`
- when event feed fetches backend video items, merge by `serverVideoId`
- once backend item is active and fully authoritative, local-only state can be retired

---

## 4. Uploader playback must use local file path first

When the uploader taps their own newly captured/selected video before processing completes, playback must use the **local file path**, not Azure.

### Required precedence

For uploader playback:

1. if local file exists for this item, play local file
2. else if uploader has preview URL and video still processing, use preview URL
3. else use normal `/playback` path

This precedence is important.

Local file path is the fastest path and should win.

### Why

- zero network wait
- zero Blob egress for uploader's first view
- codec compatibility is guaranteed for the recording device because it created or selected the file

---

## 5. Keep `preview_url` as fallback, not primary

The current `preview_url` design is still useful.

Do **not** remove it.

But its role changes:

- it becomes a fallback when the local file is no longer available
- or if the local item has already been reconciled and the local path was lost

The local file is primary. `preview_url` is secondary.

---

## 6. Video card UX requirements

The video card state machine must support these uploader-visible states:

### Local pending

- card appears instantly after selection/capture
- card is tappable
- subtitle should reflect local state, for example:
  - `Ready to upload`
  - `Uploading...`
  - `Finalizing...`
  - `Processing for sharing...`
- uploader can play immediately from local file

### Processing in cloud

- uploader still can play from local file while cloud processing is happening
- do not block playback during processing
- card should communicate that shared version is still being prepared

### Active

- when `video_ready` arrives and feed refreshes, card becomes normal shared video card
- future playback can use the standard cloud playback path

### Failed

- if upload or processing fails, uploader should still see a meaningful failed state
- if local file still exists, keep local playback possible where feasible
- provide retry affordance if practical

---

## 7. Player screen requirements

The video player must support three inputs:

1. `localFilePath`
2. `previewUrl`
3. normal backend playback metadata

### Required precedence logic

```text
if localFilePath != null:
    play local file
else if previewUrl != null:
    play preview url
else:
    call backend /playback and use HLS + MP4 fallback
```

### Required note

This is uploader-specific behavior.

Other clique members should never receive a local path and should never depend on uploader-device content.

---

## 8. Upload flow changes

The upload flow must create the local pending item **before** network work begins.

### Required sequence

1. user records or selects a video
2. local validation succeeds
3. client creates local pending feed item immediately
4. client navigates back to event feed or keeps context in a way that the item is visible immediately
5. upload-url request starts
6. block upload starts
7. commit starts
8. local item gets associated with serverVideoId
9. backend processing continues
10. `video_ready` transitions item to shared active state

### Important

Do not make the uploader sit on a blocking upload screen as the only experience.

A blocking progress screen is acceptable only if it still preserves the local-first item and does not delay visible availability in the feed.

Ideal UX:

- return user to the event feed quickly
- show inline item progress there
- allow immediate tap-to-play on the local item

If full inline-progress refactor is too large for this pass, still implement the local item architecture first so the uploader's card exists immediately after upload begins.

---

## 9. Backend behavior remains largely unchanged

Backend should continue to do the following:

- accept block uploads
- commit assembled blob
- enqueue transcode
- generate HLS manifest + segments + MP4 fallback + poster
- publish `video_ready`
- support deletion and expiry

### Only backend adjustments if needed

Backend changes should be minimal and only used to support clean client reconciliation.

Potential acceptable additions:

- extra fields helpful for reconciliation
- more explicit processing-state payloads
- better status fields for uploader UX

But do not redesign the backend around local playback. Local playback is a client concern.

---

## 10. Cost and architecture rules

### Keep

- cloud processing for shared playback
- normalized cloud-hosted playback for clique members
- explicit optional download only

### Do not do

- do not auto-download every shared video to every member device
- do not use raw original source as the default shared playback asset
- do not switch other clique members to uploader-local playback
- do not introduce peer-to-peer architecture

### Why

Raw originals are a bad shared-playback contract because of:

- HEVC / H.264 variability
- HDR / SDR issues
- MOV / MP4 differences
- larger file sizes
- worse first-frame behavior

The processed cloud asset is the right shared contract.

---

## 11. Definition of done

This work is complete only when all of the following are true:

1. uploader can record/select a video and see it appear immediately in their event feed
2. uploader can tap and play that video immediately from the local device
3. uploader does not have to wait for Azure processing to watch their own video
4. backend upload/transcode pipeline still works for shared playback
5. other clique members only play the cloud-hosted processed version
6. no duplicate local/server cards remain after reconciliation
7. when `video_ready` arrives, uploader's item transitions cleanly to normal shared state
8. error states do not strand the uploader with a broken or duplicate feed item

---

## Implementation guidance

## Recommended client architecture

Use a small uploader-local state store, likely Riverpod-backed, scoped per event.

Example shape:

```dart
final localPendingVideosProvider = StateNotifierProvider.family<
    LocalPendingVideosNotifier,
    List<LocalPendingVideo>,
    String>((ref, eventId) => LocalPendingVideosNotifier(eventId));
```

Responsibilities:

- add local item immediately after validation
- update upload stage through upload lifecycle
- attach `serverVideoId` after commit
- reconcile with `eventVideosProvider`
- remove or retire local-only item once backend state is authoritative

---

## Recommended feed merge order

For uploader's device:

1. fetch backend photos
2. fetch backend videos
3. fetch local pending videos for this event
4. merge backend videos + local pending videos
5. dedupe by `serverVideoId` where available
6. sort by createdAt descending

For non-uploader members:

- only backend items should appear

---

## Recommended card rendering rules

A local pending video card should be a separate rendering path, not hacked awkwardly into the fully shared server `VideoModel` if that makes state messy.

Clean is better than clever here.

If needed, introduce a unified feed item abstraction like:

```dart
sealed class MediaFeedItem {}
class PhotoFeedItem extends MediaFeedItem {}
class CloudVideoFeedItem extends MediaFeedItem {}
class LocalPendingVideoFeedItem extends MediaFeedItem {}
```

That is better than overloading one model until it becomes nonsense.

---

## Recommended player API

If needed, change the player screen constructor to support:

```dart
VideoPlayerScreen(
  eventId: ...,
  videoId: ...,              // optional for local-only pending items until commit
  localFilePath: ...,        // preferred for uploader local playback
  previewUrl: ...,           // secondary fallback
)
```

The player should not assume cloud assets are always required.

---

## Suggested phases

### Phase 1

- add local pending video model/state
- create immediate local card in feed
- local playback from file path

### Phase 2

- reconcile local item with backend `videoId`
- eliminate duplicate cards
- preserve current backend preview/cloud pipeline

### Phase 3

- polish uploader state transitions
- improve retry/error UX
- reduce or remove blocking upload-only screen if practical

---

## Guardrails

- do not regress existing cloud playback for clique members
- do not regress delete behavior
- do not regress `video_ready` behavior
- do not remove HLS + MP4 fallback shared playback
- do not make local-only uploader items visible to other users
- do not create duplicate feed cards for same video

---

## Final instruction to Claude Code

Implement this as a **local-first uploader UX enhancement** on top of the current `feature/video` branch architecture.

Do **not** rewrite the whole video system.

The correct end state is:

- **uploader watches local immediately**
- **clique members watch processed cloud version**
- **Azure remains the shared media pipeline**

That is the architecture we want.

---

## Implementation Status

**Implemented: 2026-04-09** on `feature/video` branch.

### Files created

| File | Purpose |
|---|---|
| `app/lib/features/videos/domain/local_pending_video.dart` | `LocalPendingVideo` model, `UploadStage` enum, `copyWith`, UUID generation |
| `app/lib/features/videos/presentation/local_pending_video_card.dart` | Feed card for local pending videos (upload-stage subtitles, play button, retry) |

### Files modified

| File | Change |
|---|---|
| `app/lib/features/videos/presentation/videos_providers.dart` | `LocalPendingVideosNotifier` + `localPendingVideosProvider` (StateNotifier.family, not autoDispose) |
| `app/lib/features/videos/presentation/video_capture_screen.dart` | Creates `LocalPendingVideo` on "Upload" tap before navigating to upload screen |
| `app/lib/features/videos/presentation/video_upload_screen.dart` | Accepts `localTempId`, updates local item stages (uploading/committing/processing/failed) |
| `app/lib/features/photos/presentation/event_feed_screen.dart` | `_MediaListItem` extended with `localVideo` variant; merge + dedup logic; auto-retire via `Future.microtask()`; `video_ready` listener calls `reconcileComplete()` |
| `app/lib/features/videos/presentation/video_player_screen.dart` | `localFilePath` parameter, 3-tier init precedence, `_playbackInfo` state, save/share/delete menu |
| `app/lib/features/videos/presentation/video_card_widget.dart` | Processing card tap migrated from `extra: String?` to `extra: Map<String, String?>` |
| `app/lib/core/routing/app_router.dart` | Upload route parses `localTempId`; player route parses structured `extra` map |
| `app/lib/services/storage_service.dart` | `downloadToTempFile` generalized with `extension` parameter |

### Also implemented in this session (not in original architecture doc)

- **Video save-to-device** — `StorageService.saveVideoToGallery()` wired into video player PopupMenu
- **Video share** — `downloadToTempFile(extension: 'mp4')` + `Share.shareXFiles()` wired into video player PopupMenu
- Both mirror the photo detail screen pattern. Only shown when video is in active/ready state (not during preview or local playback).

### Implementation notes

- **Blocking upload screen retained** — the architecture doc's "ideal UX" (return to feed immediately, inline progress) was deferred. The blocking `VideoUploadScreen` stays, but the `LocalPendingVideo` is created before it, so the feed card exists when the user returns.
- **State is in-memory only** — `localPendingVideosProvider` is not persisted to `SharedPreferences`. If the app is killed, local pending items are lost and the backend video (processing or active) takes over on next launch. Acceptable for v1.
- **`UploadStage.complete` vs removal** — local items are marked `complete` (not removed) when retired. This prevents a visual gap between retirement and server item fetch. Stale `complete` items accumulate in memory but are filtered from the UI and lost on app restart.
- **`VideoPlayerController.file()` used for local playback** — the `formatHint` caveat in CLAUDE.md only applies to HLS manifests. Local MP4/MOV files auto-detect correctly via `.file()`.
- **Retry affordance** — failed upload cards show Play + Retry buttons. Retry reuses the same local file and `localTempId`.
