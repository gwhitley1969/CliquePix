# Clique Pix Video Feature Specification

## Purpose
Add video upload, processing, playback, and sharing to Clique Pix.

This file is intended as a handoff specification for Claude Code so it can plan and implement video support in the app and backend.

---

## High-Level Goal
Users must be able to upload, share, and view videos inside Clique Pix.

The feature is intended for normal consumer mobile usage, especially videos captured on iPhone and Android devices.

---

## Core Product Requirements

### Required Capabilities
1. Users can upload videos into Clique Pix.
2. Users can share videos inside the same social/event/clique flows used by the app.
3. Users can view uploaded videos reliably on mobile and web.
4. Videos must support playback through adaptive streaming when appropriate.
5. The system must generate a broadly compatible fallback for playback where HLS is not ideal.

### Hard Requirements
- Maximum video length: **5 minutes**
- Maximum supported playback quality: **1080p**
- Supported upload containers: **MP4** and **MOV**
- Supported source codecs: **H.264/AVC** and **HEVC/H.265**
- Normalize **HDR to SDR** during processing
- Use **HLS** for streaming delivery
- Provide **MP4 fallback** for compatibility

---

## Product Decisions

### Upload Rules
The system must accept:
- `.mp4`
- `.mov`

The system must reject:
- files longer than 5 minutes
- unsupported containers
- unsupported codecs
- corrupt or unreadable media

### Quality Policy
- Do not deliver above 1080p in v1.
- If a user uploads a higher-resolution source, the system may accept it, but delivery assets must be normalized to **1080p maximum**.
- Source videos below 1080p should not be artificially upscaled.

### Codec Policy
- Accept **H.264** and **HEVC** uploads.
- Generate delivery assets that maximize compatibility.
- Claude Code should assume playback compatibility is more important than preserving original codec choices.

### Color / HDR Policy
- If source video is HDR, process it to **SDR** for v1 delivery.
- The goal is consistent playback across devices and browsers rather than preserving HDR output in v1.

### Playback Policy
- Primary delivery: **HLS**
- Fallback delivery: **progressive MP4**
- Video playback should work reliably in iOS, Android, and web clients.

---

## Recommended Technical Approach

### Ingestion and Validation
Implement validation in two layers:

#### Client-side validation
Before upload begins, validate at minimum:
- file extension/container
- duration
- approximate file size if available

Client-side validation is for user experience only.

#### Server-side authoritative validation
The backend must enforce the real rules for:
- max duration = 5 minutes
- allowed containers = MP4, MOV
- allowed source codecs = H.264, HEVC
- media readability / integrity

Server-side validation is the source of truth.

---

## Processing Pipeline
Claude Code should implement or scaffold a media pipeline with the following stages:

1. **Upload intake**
   - Receive original file
   - Store original asset in durable storage
2. **Media inspection**
   - Read container, codec, resolution, duration, frame rate, audio stream, and HDR metadata if available
3. **Validation**
   - Reject unsupported files
4. **Normalization / Transcoding**
   - Convert HDR to SDR when needed
   - Normalize to max 1080p output
   - Generate HLS renditions/playlists
   - Generate MP4 fallback asset
5. **Thumbnail generation**
   - Create poster/preview image for UI cards and lists
6. **Persistence**
   - Save media metadata and asset URLs/paths
7. **Playback readiness**
   - Mark processing state as ready/failed/pending

---

## Storage Strategy
- Store the original uploaded video as the private source master.
- Store generated delivery assets separately.
- Store at minimum:
  - original asset reference
  - HLS manifest reference
  - HLS segment location
  - MP4 fallback reference
  - poster/thumbnail reference
  - duration
  - width/height
  - codec metadata
  - processing state
  - file size
  - upload timestamp
  - owning user / clique / event linkage

Important:
- Keep the original master even if the playback output is constrained to 1080p.
- This gives future flexibility for reprocessing without forcing users to re-upload.

---

## Suggested Processing Outputs
For v1, Claude Code should target a practical and reliable output set.

### Required outputs
1. **HLS package**
   - HLS manifest (`.m3u8`)
   - TS or fMP4 segments, whichever is simpler and more stable in the chosen implementation
2. **MP4 fallback**
   - One broadly compatible progressive MP4 asset
3. **Poster image**
   - At least one thumbnail/poster frame

### Delivery target
- Max output quality: **1080p**
- Preserve aspect ratio
- Do not stretch video
- Letterbox only if absolutely necessary; prefer preserving original aspect ratio naturally

---

## User Experience Requirements

### Upload UX
- User selects a video from device library or file picker
- User sees validation errors before upload when possible
- User sees upload and processing status
- User should not be told the upload is fully complete until server-side processing is done or clearly marked as processing

### Failure UX
Provide clear errors for at least:
- video is longer than 5 minutes
- unsupported file type
- unsupported codec
- upload failed
- processing failed

### Playback UX
- Video cards should show a poster image and duration
- Tapping a video should open an in-app player
- Player should prefer HLS where supported
- Player should fall back to MP4 when needed

---

## Sharing Requirements
Videos must participate in Clique Pix sharing flows.

Claude Code should wire videos into the same core sharing model as photos wherever sensible, including:
- ownership
- permissions
- association to event/clique/feed/post
- visibility rules
- deletion rules

If the existing photo model cannot cleanly support video, Claude Code should introduce a shared media abstraction rather than bolting video on in an inconsistent way.

---

## Data Model Guidance
Claude Code should evaluate whether the current schema needs:
- a generalized `media` entity/table/model
- media type enum: `photo`, `video`
- processing status enum: `pending`, `processing`, `ready`, `failed`
- fields for original asset and derived assets
- playback metadata

Suggested metadata fields:
- `mediaType`
- `sourceContainer`
- `sourceVideoCodec`
- `sourceAudioCodec`
- `durationSeconds`
- `width`
- `height`
- `isHdrSource`
- `normalizedToSdr`
- `hlsManifestUrl`
- `mp4FallbackUrl`
- `thumbnailUrl`
- `processingStatus`
- `processingError`

---

## API / Backend Expectations
Claude Code should design or update APIs for:
- initiating upload
- creating a media record
- reporting upload completion
- triggering processing
- reading media status
- retrieving playback URLs/metadata
- deleting media

The backend must not trust client-provided metadata alone.

The backend should inspect the actual uploaded file.

---

## Web, iOS, and Android Considerations

### iPhone / iOS
- Must handle iPhone-originated MOV files
- Must handle HEVC-originated captures

### Android
- Must handle common MP4 uploads with H.264 or HEVC

### Web
- Web playback should prefer HLS if supported by the chosen player stack
- MP4 fallback must exist for compatibility cases

Claude Code should choose libraries and player components that are proven and boring rather than clever.
Reliability matters more than novelty.

---

## Security and Reliability Requirements
- Validate media server-side
- Do not expose private originals publicly unless intentionally designed
- Use signed or controlled access for delivery if the app’s access model requires it
- Protect against unsupported or malicious file uploads
- Log processing failures with enough detail to troubleshoot
- Ensure deletion flows clean up derived assets as well as the original where appropriate

---

## Non-Goals for v1
The following are out of scope unless they are trivial to add without destabilizing delivery:
- 4K delivery
- HDR playback preservation
- video editing inside the app
- captions/subtitles
- trimming/cropping UI
- filters/effects
- live streaming
- direct messaging video attachments unless already part of scope elsewhere
- advanced transcoding ladders beyond what is needed for reliable 1080p delivery

---

## Acceptance Criteria
Claude Code should treat the feature as complete only when all of the following are true:

1. A user can upload an MP4 video under 5 minutes.
2. A user can upload a MOV video under 5 minutes.
3. H.264 uploads are accepted and playable.
4. HEVC uploads are accepted and playable.
5. A source video above 1080p is normalized so delivery does not exceed 1080p.
6. HDR source video is normalized to SDR.
7. HLS playback works in supported clients.
8. MP4 fallback playback works when needed.
9. Videos longer than 5 minutes are rejected cleanly.
10. Unsupported formats/codecs are rejected cleanly.
11. A thumbnail/poster is generated.
12. Media processing status is visible to the system and usable by the UI.
13. Videos can be shared through Clique Pix in the intended feed/event/clique flows.

---

## Implementation Guidance for Claude Code
Claude Code should:
1. Review the current repo and architecture first.
2. Identify all places where the app currently assumes media = photo only.
3. Produce a short implementation plan before making changes.
4. Prefer incremental, testable changes.
5. Reuse existing patterns where sensible.
6. Avoid hacks that treat video as a special-case blob with no durable metadata model.
7. Document any schema, storage, API, or UI changes.
8. Call out open questions or risks before implementing anything irreversible.

---

## Preferred Outcome
The end result should feel like video is a first-class media type in Clique Pix, not a bolted-on afterthought.

The v1 implementation should be dependable, cross-platform, and simple enough to operate without creating unnecessary complexity.
