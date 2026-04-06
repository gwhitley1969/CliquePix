# CLAUDE.md – Clique Pix Development Guardrails

## What This File Is

This is the authoritative reference for Claude Code while developing Clique Pix. When any question arises about scope, architecture, patterns, or priorities — this file wins. Read it before generating code, making architectural decisions, or suggesting features.

If anything in this file conflicts with PRD.md or ARCHITECTURE.md, this file takes precedence for development decisions. Raise the conflict so the other docs can be updated.

---

## Product Identity

Clique Pix is a **private, event-based photo sharing** mobile app. Users create Cliques (persistent groups), start Events (temporary photo sessions), and share photos that auto-expire from the cloud.

**It is not** a social network, messaging app, content discovery platform, or photo editing suite.

### The Core Loop

Every line of code must serve this loop:

1. User signs in
2. User creates an Event (picks or creates a Clique during creation)
3. User takes or uploads a photo
4. User edits the photo (crop, draw, stickers, filters)
5. Photo is compressed on-device and uploaded directly to Blob Storage
6. Other event members are notified via push
7. Event feed displays the photo (thumbnail in feed, full-size on tap)
8. Members view, react, save to device, or share externally
9. Photos auto-delete from the cloud after the event duration expires

If a feature does not directly support this loop, it does not belong in v1.

---

## v1 Scope — Hard Boundaries

### Build These

- Authentication via Entra External ID (email OTP / magic link, minimal friction)
- 5-layer token refresh defense for the Entra 12-hour timeout bug
- Cliques: create, join via invite link / SMS / QR, list, view members, leave
- Deep linking for Clique invites (Universal Links on iOS, App Links on Android)
- Events: create Event first (pick or create Clique during creation), duration locked to three presets (24h / 3 days / 7 days default), list, expire, manual deletion by event organizer (with confirmation dialog)
- In-app camera capture
- Upload from camera roll
- Client-side image compression before upload (strip EXIF, resize to max 2048px, JPEG quality 80, convert HEIC to JPEG)
- Photo upload via User Delegation SAS (two-phase: get upload URL, then confirm)
- Event feed: vertical scroll, large photo cards, user attribution, timestamp, thumbnails
- Lightweight reactions: ❤️ 😂 🔥 😮 (unique constraint per user per photo per type)
- Save individual photo to device, multi-select batch download with progress
- External share via native OS share sheet (no direct third-party API integrations)
- Auto-deletion: timer-triggered cloud cleanup when event duration expires
- Orphan cleanup: pending uploads not confirmed within 10 minutes
- Push notifications via FCM: new photo added, event expiring in 24 hours
- Thumbnail generation (async, blob-triggered or queue-triggered, 400px longest edge, JPEG quality 70)

### Do Not Build

- ~~Chat, comments, or threads~~ (event-centric 1:1 DMs implemented — no group chat, no global inbox, no attachments)
- Followers / following
- Public feeds or discovery
- Custom photo editor UI (use `pro_image_editor` package — do not build editor from scratch)
- Video capture or playback
- AI features of any kind
- Monetization, subscriptions, or paywalls
- Printed albums
- User search or directory
- Read receipts or typing indicators
- Stories or ephemeral content beyond the event model
- Firebase backend services (Auth, Firestore, etc.) — FCM is used for push transport only
- Redis, SignalR, Service Bus, Notification Hubs (Web PubSub is now used for DMs)

### When In Doubt

Leave it out. A missing feature can be added later. A cluttered v1 cannot be un-cluttered.

---

## Tech Stack — Locked Decisions

### Frontend
- **Flutter** (Dart) — single codebase for iOS and Android
- **State management:** Riverpod
- **HTTP client:** Dio
- **Image picker:** image_picker
- **Image compression:** flutter_image_compress
- **Secure token storage:** flutter_secure_storage
- **Non-sensitive flags:** shared_preferences
- **Push notifications:** firebase_messaging (FCM transport only)
- **Image caching:** cached_network_image
- **Image editor:** pro_image_editor (^5.1.4 — crop, draw, stickers, filters, text). **Callback rule:** v5.x calls `onCloseEditor` after `onImageEditingComplete` completes. Only pop in `onCloseEditor`, never in `onImageEditingComplete`, or you get a double-pop.
- **Deep links:** app_links
- **QR code generation:** qr_flutter
- **MSAL authentication:** msal_auth (^3.3.0, v2 embedding, custom API scope `access_as_user`)

Do not introduce dependencies not listed here without discussing the tradeoff first.

### Backend (Azure)

| Layer | Service | Purpose |
|-------|---------|---------|
| Entry point | Azure Front Door | Global load balancing, SSL termination, WAF |
| API gateway | Azure API Management | Rate limiting, API versioning, policy enforcement |
| Compute | Azure Functions (TypeScript, Node.js) | REST API, timer cleanup, thumbnail generation |
| Database | PostgreSQL Flexible Server | Relational data |
| Object storage | Azure Blob Storage | Photo originals and thumbnails |
| Identity (consumer) | Microsoft Entra External ID | User auth (email OTP / magic link) |
| Identity (infra) | System-assigned managed identity | Function App → Blob Storage, Key Vault |
| Secrets | Azure Key Vault | DB connection string, FCM credentials |
| Observability | Application Insights | Telemetry, errors, dependencies |
| Realtime messaging | Azure Web PubSub | Real-time DM delivery via WebSocket |

### Architecture Pattern

All API traffic flows: **Flutter → Front Door → APIM → Azure Functions → PostgreSQL / Blob Storage**

No exceptions. No direct Function App URLs exposed to the client. APIM is the single published API surface.

Front Door and APIM are included from day one. This matches the production pattern used in My AI Bartender and avoids the pain of retrofitting API gateway infrastructure after the fact.

---

## Project Structure (Flutter)

```
/lib
  /app                    # App entry point, root widget
  /core
    /theme                # Colors, text styles, gradients, design tokens
    /routing              # Route definitions, deep link handling
    /constants            # API endpoints, duration presets
    /utils                # Date formatting, image helpers, validators
    /errors               # Error types, failure classes
  /features
    /auth                 # Login, signup, token management, 5-layer refresh
      /data
      /domain
      /presentation
    /cliques              # Clique CRUD, invites, membership
      /data
      /domain
      /presentation
    /events               # Event CRUD, duration presets, expiration
      /data
      /domain
      /presentation
    /photos               # Upload pipeline, feed, reactions, save, share
      /data
      /domain
      /presentation
    /notifications        # Push token registration, notification list
      /data
      /domain
      /presentation
    /profile              # User profile, settings
      /data
      /domain
      /presentation
  /models                 # Shared data models
  /services               # API client, storage service, notification service
  /widgets                # Reusable UI components
```

Keep this structure. Do not flatten it. Do not invent alternative organizations.

---

## Design System

### Reference Materials

The app icon concept (camera with aqua→blue→violet gradient, white body, prominent lens, pink/magenta accent dot) is the approved direction. The mockup screenshots are **color scheme references only** — do not implement specific UI elements, navigation structures, or features shown in the mockups. The actual UI will be designed and built from scratch following these design tokens.

### Color Palette

| Token                | Hex       | Usage                                    |
|----------------------|-----------|------------------------------------------|
| Electric Aqua        | #00C2D1   | Primary accent, gradient start           |
| Deep Blue            | #2563EB   | Primary action, gradient middle          |
| Violet Accent        | #7C3AED   | Gradient end, secondary highlights       |
| Soft Aqua Background | #E6FBFF   | Light background, cards                  |
| White Surface        | #FFFFFF   | Content surfaces, cards                  |
| Primary Text         | #0F172A   | Headlines, body text                     |
| Secondary Text       | #64748B   | Timestamps, captions, labels             |

### Primary Gradient

`#00C2D1 → #2563EB → #7C3AED` (left to right, or top to bottom depending on context)

Use for: app bar accents, CTA buttons, event headers, splash screen, onboarding highlights.

Do not overuse. Most surfaces should be white or soft aqua. The gradient is an accent, not a background.

### Typography

- Use system fonts (San Francisco on iOS, Roboto on Android) via Flutter defaults
- Do not import custom fonts for v1
- Headings: bold, 18–24sp
- Body: regular, 14–16sp
- Captions/timestamps: regular, 12sp, secondary text color

### Iconography

- Use Material Icons or Lucide as icon set
- Consistent weight and size throughout
- Camera icon is the brand's visual anchor

### Spacing & Layout

- Base unit: 8px
- Standard padding: 16px
- Card border radius: 12px
- Photo cards should be large and dominant — the feed is photo-first, not text-first
- Minimum tap target: 48x48px

### Brand Personality

Vibrant, modern, social, premium but approachable. Not overly feminine, not corporate.

---

## API Design

### Style

RESTful JSON APIs over HTTPS. No GraphQL. No event-driven patterns in v1.

### Endpoints

```
POST   /api/auth/verify
GET    /api/users/me
DELETE /api/users/me

POST   /api/cliques
GET    /api/cliques
GET    /api/cliques/{cliqueId}
POST   /api/cliques/{cliqueId}/invite
POST   /api/cliques/{cliqueId}/join
GET    /api/cliques/{cliqueId}/members
DELETE /api/cliques/{cliqueId}/members/me
DELETE /api/cliques/{cliqueId}/members/{userId}

POST   /api/cliques/{cliqueId}/events
GET    /api/cliques/{cliqueId}/events
GET    /api/events/{eventId}
DELETE /api/events/{eventId}

POST   /api/events/{eventId}/photos/upload-url
POST   /api/events/{eventId}/photos
GET    /api/events/{eventId}/photos
GET    /api/photos/{photoId}
DELETE /api/photos/{photoId}

POST   /api/photos/{photoId}/reactions
DELETE /api/photos/{photoId}/reactions/{reactionId}

GET    /api/notifications
PATCH  /api/notifications/{notificationId}/read
DELETE /api/notifications/{notificationId}
DELETE /api/notifications
POST   /api/push-tokens

POST   /api/events/{eventId}/dm-threads
GET    /api/events/{eventId}/dm-threads
GET    /api/dm-threads/{threadId}
GET    /api/dm-threads/{threadId}/messages
POST   /api/dm-threads/{threadId}/messages
PATCH  /api/dm-threads/{threadId}/read
POST   /api/realtime/dm/negotiate
```

### Upload Flow

**User Delegation SAS — RBAC-backed, no storage account keys.**

1. Client compresses image (see Image Handling Pipeline)
2. Client calls `POST /api/events/{eventId}/photos/upload-url`
3. Function validates Entra token and confirms user is a member of the event's clique
4. Function generates a photo ID and blob path (`photos/{cliqueId}/{eventId}/{photoId}/original.jpg`), creates a photo record with status `pending`
5. Function uses managed identity to request a **User Delegation Key**, generates a **write-only User Delegation SAS** scoped to that exact blob path, 5-minute expiry
6. Function returns the SAS upload URL and photo ID to the client
7. Client uploads compressed image directly to Blob Storage using the SAS URL
8. Client calls `POST /api/events/{eventId}/photos` with photo ID and metadata (dimensions, MIME type)
9. Function verifies blob exists, reads blob properties (content type, file size), updates photo record to status `active`
10. Function triggers async thumbnail generation
11. Function sends push notifications to event members
12. Function returns complete photo record to client

If the client does not confirm upload (step 8) within 10 minutes, the orphan cleanup process removes the blob and pending record.

**User Delegation SAS Rules:**
- SAS expiry: 5 minutes maximum
- Upload SAS permissions: write-only (client cannot read, list, or delete)
- View SAS permissions: read-only (client cannot write, list, or delete)
- SAS scope: single blob path only, never container-level
- User Delegation Key: cache and reuse for up to 1 hour (valid for up to 7 days, but rotate frequently)

### Photo View / Download

- Feed endpoints return photo metadata with short-lived read-only User Delegation SAS URLs for both thumbnail and original
- Feed cards load thumbnails only
- Full-size loads on photo detail view / full-screen tap

### Response Format

Success:
```json
{
  "data": { ... },
  "error": null
}
```

Error:
```json
{
  "data": null,
  "error": {
    "code": "CLIQUE_NOT_FOUND",
    "message": "The requested clique does not exist."
  }
}
```

Use consistent error codes. Never return raw exception messages or stack traces to the client.

---

## Data Architecture

### PostgreSQL Tables

**users**: id (UUID PK), external_auth_id, display_name, email_or_phone, avatar_url (nullable), created_at, updated_at

**cliques**: id (UUID PK), name, invite_code (unique), created_by_user_id (FK → users), created_at, updated_at

**clique_members**: id (UUID PK), clique_id (FK), user_id (FK), role (owner/member), joined_at — unique constraint on (clique_id, user_id)

**events**: id (UUID PK), clique_id (FK), name, description (nullable), created_by_user_id (FK), retention_hours (24/72/168 — three presets only), status (active/expired), created_at, expires_at (computed: created_at + retention_hours)

**photos**: id (UUID PK, generated server-side at upload-url step), event_id (FK), uploaded_by_user_id (FK), blob_path, thumbnail_blob_path (nullable until generated), original_filename, mime_type (JPEG/PNG), width, height, file_size_bytes, status (pending/active/deleted), created_at, expires_at (inherits from event), deleted_at (nullable)

**reactions**: id (UUID PK), photo_id (FK), user_id (FK), reaction_type (heart/laugh/fire/wow), created_at — unique constraint on (photo_id, user_id, reaction_type)

**push_tokens**: id (UUID PK), user_id (FK), platform (ios/android), token (FCM registration token), created_at, updated_at

**notifications**: id (UUID PK), user_id (FK), type (new_photo/event_expiring/event_expired/member_joined/event_deleted), payload_json (JSONB), is_read (boolean, default false), created_at

### Photo Status Flow

`pending` (upload-url issued) → `active` (client confirmed upload) → `deleted` (cleanup job ran)

### Blob Storage

Single container named `photos` with virtual path hierarchy:

```
photos/{cliqueId}/{eventId}/{photoId}/original.jpg
photos/{cliqueId}/{eventId}/{photoId}/thumb.jpg
```

---

## Entra External ID — Known Bug & Required Workaround

### The Problem

Entra External ID (CIAM) tenants have a **hardcoded 12-hour inactivity timeout** on refresh tokens. This is a confirmed Microsoft bug — standard Entra ID tenants get 90-day lifetimes. No portal-based configuration options exist.

Error signature: `AADSTS700082: The refresh token has expired due to inactivity... inactive for 12:00:00`

### Required: 5-Layer Token Refresh Defense

This pattern is proven in production on My AI Bartender. Implement all five layers.

| Layer | Mechanism | Trigger | Reliability | Purpose |
|-------|-----------|---------|-------------|---------|
| 1 | Battery Optimization Exemption | First login (Android only) | Critical | Allows background tasks on Samsung/Xiaomi/Huawei |
| 2 | AlarmManager Token Refresh | Every 6 hours | Very High | Fires even in Doze mode via `exactAllowWhileIdle` |
| 3 | Foreground Refresh on App Resume | Every app open | Very High | Safety net — catches all background failures |
| 4 | WorkManager Background Task | Every 8 hours | Medium | Backup mechanism |
| 5 | Graceful Re-Login UX | When all else fails | N/A | "Welcome back" dialog with stored user hint, one-tap re-auth |

### Layer Details

**Layer 1 — Battery Optimization Exemption (Android)**
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` must be requested at **runtime**, not just declared in the manifest
- Show a user-facing dialog after first login: "To keep you signed in, Clique Pix needs permission to run in the background"
- Without this, Samsung/Xiaomi/Huawei will kill background tasks
- Service: `BatteryOptimizationService` (singleton)

**Layer 2 — AlarmManager (Android)**
- Use `zonedSchedule` with `AndroidScheduleMode.exactAllowWhileIdle`
- Schedule every 6 hours (half the 12-hour timeout = safe margin)
- Use a silent notification channel (`Importance.min`, `Priority.min`, `silent: true`)
- Filter `TOKEN_REFRESH_TRIGGER` payloads in main.dart to prevent navigation errors if user taps the notification
- Reschedule after each successful refresh
- Cancel on logout

**Layer 3 — Foreground Refresh (Both platforms, most reliable)**
- On `AppLifecycleState.resumed`, check token age via `lastRefreshTime` in secure storage
- If token is > 6 hours old, proactively refresh before it expires
- If refresh succeeds, reschedule AlarmManager
- If refresh fails, trigger Layer 5 (graceful re-login)
- This is the primary iOS defense since iOS lacks reliable background task guarantees

**Layer 4 — WorkManager (Backup)**
- `registerPeriodicTask` every 8 hours with `NetworkType.connected` constraint
- With Layer 1 exemption granted, reliability improves on Android
- This is a backup, not the primary mechanism

**Layer 5 — Graceful Re-Login UX (Fallback)**
- When all background mechanisms fail, show a "Welcome back, [Name]!" dialog instead of a full login screen
- Store `lastKnownUser` before clearing auth state
- Use `loginHint` to pre-fill email in the MSAL interactive flow
- Try silent acquisition first, fall back to interactive with hint

### Android Permissions Required

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

### iOS Considerations

- `BGAppRefreshTask` via BGTaskScheduler — request 6-hour intervals, but iOS controls actual timing
- Foreground refresh (Layer 3) is the most reliable mechanism on iOS
- Users who disable Background App Refresh will need to re-login after 12 hours — Layer 5 handles this gracefully

### Token Storage

- Auth tokens and refresh tokens: `flutter_secure_storage` only — **never** `shared_preferences`
- Track `lastRefreshTime` in secure storage for proactive refresh decisions
- Store `lastKnownUser` profile for the graceful re-login dialog
- Clear all stored tokens, user data, and cancel all background refresh jobs on logout

### Key Timing

- Microsoft inactivity timeout: 12 hours (hardcoded, not configurable)
- AlarmManager interval: 6 hours
- Foreground refresh threshold: 6 hours since last refresh
- WorkManager interval: 8 hours (backup)
- Safety margin: 6 hours (half the timeout)

### Reference

Full implementation details, code samples, and debug log tags are in `ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

---

## Image Handling Pipeline

Photo uploads are the most performance-critical path in Clique Pix. Uncompressed phone photos are 5–12MB each. Without client-side compression, a 10-photo event eats 50–120MB of Blob Storage and takes ages on mobile data.

### Client Side (Before Upload)
1. User selects or captures photo
2. Strip EXIF data (removes GPS coordinates, device info, timestamps)
3. Resize: longest edge max 2048px, maintain aspect ratio
4. Compress: JPEG quality 80
5. Convert HEIC to JPEG on-device before upload
6. Reject files over 10MB after compression (safety net)
7. Use `flutter_image_compress` for this pipeline

### Why These Numbers

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max dimension | 2048px | Covers all current phone screens. This is a group photo app, not a stock photography service. |
| JPEG quality | 80 | Industry standard for "visually indistinguishable." Quality 90+ wastes bytes; quality 70 shows artifacts on gradients and skin tones. |
| Max file size | 10MB | Post-compression safety net. At 2048px / quality 80, photos land around 500KB–1.5MB. |
| Format | JPEG | Universal compatibility. HEIC converted client-side. |

### Server Side (After Client Upload to Blob)

The Function never touches photo bytes during the upload flow. At the confirmation step:

1. Verify blob exists at expected path via managed identity
2. Read blob properties to validate content type (JPEG, PNG only) and file size (reject > 15MB)
3. Update photo metadata in PostgreSQL
4. Trigger async thumbnail generation

### Thumbnail Generation

- Triggered by blob upload event or queue message
- Function reads original blob via managed identity (`DefaultAzureCredential`), generates a 400px longest edge / JPEG quality 70 thumbnail, writes it back to Blob Storage
- Updates `thumbnail_blob_path` in photo record
- Target thumbnail size: ~30–80KB
- If thumbnail generation fails, the feed falls back to loading the original (slower but not broken)

### Feed Display

- Feed cards load thumbnails only
- Full-size loads on photo detail view / full-screen tap
- Use `cached_network_image` for client-side image caching
- Placeholder shimmer animation while images load

---

## Deep Linking — Clique Invites

Clique invites are core to the product loop. When a user taps an invite link, the app must open directly to the invite acceptance screen.

### Link Format

```
https://clique-pix.com/invite/{inviteCode}
```

QR codes encode the same URL. Generate QR on the client using `qr_flutter`.

### Platform Setup

**iOS — Universal Links:**
- Host `apple-app-site-association` at `https://clique-pix.com/.well-known/apple-app-site-association`
- Configure Associated Domains in Xcode: `applinks:clique-pix.com`
- Handle incoming link via `app_links` package

**Android — App Links:**
- Host `assetlinks.json` at `https://clique-pix.com/.well-known/assetlinks.json`
- Configure intent filter in AndroidManifest with `autoVerify="true"`
- Handle incoming link via `app_links` package

### Hosting Well-Known Files

Serve from Azure Front Door or a simple static web app. Static JSON files that rarely change.

### Flow

1. **App installed:** open app, route to invite acceptance screen, call `POST /api/cliques/{cliqueId}/join` with invite code
2. **App not installed:** open App Store / Play Store listing. Deferred deep linking is a post-v1 enhancement.

---

## Security Rules

### API Authorization — Every Endpoint Must Enforce:
- User is authenticated (valid Entra token verified by the Function)
- User belongs to the clique/event they are accessing (membership check)
- User can only delete their own photos

### Blob Storage Access — RBAC + User Delegation SAS:
- **No storage account keys.** No account-key-based SAS tokens anywhere in the system.
- `allowSharedKeyAccess: false` on the storage account
- Function App managed identity assigned `Storage Blob Data Contributor` + `Storage Blob Delegator` roles
- Client uploads via write-only User Delegation SAS (scoped to single blob, 5-minute expiry)
- Client views via read-only User Delegation SAS (scoped, short-lived)
- All server-side blob access via `DefaultAzureCredential` (managed identity in Azure, developer credentials locally)

### Storage
- No public anonymous access on any container
- Container access policy: private
- Photo URLs are never permanent or publicly accessible (always behind short-lived SAS)

### Privacy
- Private by default — no public feeds, no user directory, no content discovery
- EXIF data stripped client-side before upload (GPS, device info, timestamps)
- Photos only visible to event members

### Client
- Auth tokens and refresh tokens in `flutter_secure_storage` only — **never** `shared_preferences`
- `shared_preferences` acceptable only for non-sensitive flags (e.g., `has_seen_onboarding`, `battery_dialog_shown`)
- No tokens, credentials, or PII in debug logs (even in debug builds)
- Clear all auth state, stored tokens, and cached user data on logout
- Cancel all background refresh mechanisms (AlarmManager, WorkManager) on logout

---

## Error Handling Patterns

### Client
- Wrap all API calls in try/catch
- Map HTTP errors to typed failure classes (NetworkFailure, AuthFailure, NotFoundFailure, etc.)
- Show user-friendly error messages, not technical details
- Retry upload failures with exponential backoff (max 3 retries)
- Handle offline state: show cached content where available, queue actions where possible

### Backend
- Return structured error responses (see Response Format above)
- Log errors to Application Insights with correlation IDs
- Never return stack traces or internal details to the client
- Validate all input — never trust the client

---

## Expiration & Cleanup

### Photo Expiration

Timer-triggered Azure Function (every 15 minutes):

1. Query photos where `expires_at < now()` and `status = 'active'`
2. Delete blobs (original + thumbnail) via managed identity
3. Update photo records: `status = 'deleted'`, `deleted_at = now()`
4. If all photos in event are deleted, update event `status = 'expired'`
5. Log `expired_photos_deleted` telemetry with count

### Orphan Cleanup

Separate scheduled check:

1. Query photos where `status = 'pending'` and `created_at < now() - 10 minutes`
2. Delete orphaned blob if it exists
3. Delete pending record
4. Log `orphaned_uploads_cleaned` telemetry with count

### Important

Device-saved copies remain untouched. Only cloud-managed copies are deleted. Users are notified 24 hours before expiration via push.

---

## Notification Architecture

### Delivery

FCM (Firebase Cloud Messaging) for push delivery to both Android and iOS. FCM is a transport mechanism only — no Firebase backend services, no Firebase Auth, no Firestore.

### Push Triggers

| Trigger | Notification Type | Recipients | Payload |
|---------|------------------|------------|---------|
| Photo uploaded to event | `new_photo` | All event clique members except uploader | `{ event_id, photo_id }` |
| Someone joins a clique | `member_joined` | All existing clique members except joiner | `{ clique_id, clique_name, joined_user_name }` |
| Event expiring in 24h | `event_expiring` | All event clique members | `{ event_id }` |
| Event expired | `event_expired` | All event clique members | `{ event_id }` |
| Event deleted by organizer | `event_deleted` | All clique members except deleter | `{ event_id, event_name }` |

**No notifications sent** for member removals or voluntary departures.

### Backend Flow

1. Backend action (photo upload, clique join, timer) queries relevant members' push tokens
2. Function sends push via FCM HTTP v1 API using `sendToMultipleTokens()` with `notification` + `data` payloads
3. Function creates notification records in `notifications` table for in-app display
4. Failed token sends trigger stale token cleanup

### Client Flow

| App State | Handler Location | Display |
|-----------|-----------------|---------|
| **Foreground** | `main.dart` → `FirebaseMessaging.onMessage` | `flutter_local_notifications.show()` heads-up banner |
| **Background** | OS auto-displays from FCM `notification` payload | `onMessageOpenedApp` → GoRouter navigation on tap |
| **Terminated** | OS auto-displays from FCM `notification` payload | `getInitialMessage()` → GoRouter navigation on tap |

**Key pattern:** The `onMessage` listener is set up in `main.dart` immediately after `flutter_local_notifications` plugin initialization — not in a separate service class. This ensures the plugin is always ready when `show()` is called.

### Notification Channel

Created programmatically in `main.dart` at startup:
- Channel ID: `cliquepix_default` (referenced in AndroidManifest)
- Importance: HIGH (heads-up banners)
- Android 13+ permission requested via `requestNotificationsPermission()`

### Token Management

- `PushNotificationService` initializes after auth — gets FCM token, registers via `POST /api/push-tokens`
- Listens to `FirebaseMessaging.instance.onTokenRefresh` and re-registers when tokens rotate
- Backend upserts on conflict (same token → update timestamp)
- Remove on logout
- Failed sends remove stale tokens via `DELETE FROM push_tokens WHERE token = ANY($1)`

### Notification Tap Navigation

All taps navigate via GoRouter using `data` payload:
- `event_id` → `router.push('/events/$eventId')`
- `clique_id` → `router.push('/cliques/$cliqueId')`

Foreground taps use a static callback: `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter

---

## Real-Time / Near-Real-Time Feed

### v1 Approach

- Push notification on new photo / clique join → user taps to open relevant screen
- Refresh on app resume via `WidgetsBindingObserver` (`didChangeAppLifecycleState`)
- Pull-to-refresh via `RefreshIndicator` on all list/detail screens
- 30-second polling via `Timer.periodic` while clique list/detail screens are active
- This pattern applies to: event feed, cliques list, clique detail (members)

This is sufficient. Most photo sharing happens in bursts during active events. Do not introduce SignalR, Web PubSub, or event streaming for v1.

---

## Performance Expectations

- Photo capture to visible in feed: < 5 seconds on good connectivity
- Feed scroll: 60fps, no jank
- App cold start to usable: < 3 seconds
- Thumbnail loads: < 500ms on 4G
- Never block the UI thread with image processing or network calls

---

## Testing Expectations

### v1 Minimum
- Unit tests for business logic (duration calculations, membership checks, error mapping)
- Widget tests for critical flows (auth, photo upload, feed rendering)
- Manual testing on both iOS and Android devices
- Test on slow networks (throttle to 3G in dev tools)

### Not Required for v1
- Full integration test suite
- Automated E2E tests
- Load testing (do this before public launch, not during MVP)

---

## Observability

### Application Insights Telemetry Events

- `clique_created`, `clique_joined`, `clique_left`
- `event_created`, `event_expired`, `event_deleted`
- `photo_upload_started`, `photo_upload_completed`, `photo_upload_failed`
- `photo_saved_to_device`
- `reaction_added`, `reaction_removed`
- `notification_sent`, `notification_send_failed`
- `expired_photos_deleted` (include count)
- `orphaned_uploads_cleaned` (include count)
- `token_refresh_success`, `token_refresh_failed` (include layer that triggered it)
- `account_deleted`
- `dm_thread_created`, `dm_message_sent`, `dm_message_send_failed`
- `dm_push_sent`, `dm_thread_marked_read_only`

### Logging Rules
- Always log: correlation IDs, error codes, function execution duration
- Never log: auth tokens, storage credentials, user PII, raw photo content

---

## Networking (Dio Configuration)

Configure Dio with:
- Base URL pointing to the Front Door endpoint
- Auth interceptor that attaches the Entra access token to every request
- Error interceptor that maps HTTP status codes to typed failure classes
- Retry interceptor for transient failures (5xx, timeouts)

---

## Development Workflow

### Iteration Order
1. **Scaffold** the full project structure and navigation shell
2. **Auth flow** end-to-end (signup → login → token management → 5-layer refresh)
3. **Cliques** CRUD and invite flow with deep linking
4. **Events** creation and listing with duration presets
5. **Photo upload** pipeline (capture → compress → upload-url → blob upload → confirm)
6. **Event feed** with thumbnails and real-time-ish updates
7. **Reactions** and **save/download**
8. **Push notifications** (FCM token registration, new photo alerts, clique join alerts, expiration alerts)
9. **Auto-deletion** cleanup job and orphan cleanup
10. **Polish** UI, transitions, error states, empty states

Do not perfect one screen before the next exists. Get the full loop working end-to-end first, then refine.

### Build Strategy
- Build features vertically: UI + state + API + backend for each feature before moving to the next
- Commit working increments, not half-finished features
- Test on a real device early and often — emulators hide performance issues

---

## Environment Configuration

### Environments
- `dev` — local development, points to dev Azure resources
- `prod` — production Azure resources

Two environments is sufficient for solo development. Add staging before public launch.

### Configuration Separation

Maintain separate config per environment:
- API base URL (Front Door endpoint)
- Entra External ID tenant ID and client ID
- Application Insights instrumentation key
- FCM project credentials

Use Flutter flavor/environment mechanisms. Do not hardcode environment-specific values.

---

## Infrastructure

### Azure Resource Naming

| Resource | Convention |
|----------|-----------|
| Resource Group | `rg-cliquepix-prod` |
| Function App | `func-cliquepix-fresh` |
| Storage Account | `stcliquepixprod` (no hyphens) |
| PostgreSQL | `pg-cliquepixdb` |
| App Insights | `appi-cliquepix-{env}` |
| Key Vault | `kv-cliquepix-{env}` |
| Front Door | `fd-cliquepix-prod` |
| APIM | `apim-cliquepix-002` |

### Managed Identity & RBAC Role Assignments

Function App system-assigned managed identity requires:

| Role | Scope | Purpose |
|------|-------|---------|
| `Storage Blob Data Contributor` | Storage account | Server-side blob read/write/delete (thumbnails, cleanup, validation) |
| `Storage Blob Delegator` | Storage account | Generate User Delegation Keys for SAS tokens |
| `Key Vault Secrets User` | Key Vault | Read connection strings and credentials |

No storage account keys anywhere. `allowSharedKeyAccess: false` on the storage account. Use `DefaultAzureCredential` in all Azure SDK calls. PostgreSQL connection string stored in Key Vault, referenced via Key Vault reference in Function App settings.

### Key Vault Contents

Store in Key Vault:
- PostgreSQL connection string
- FCM server key / service account credentials

Not stored (managed identity eliminates the need):
- Storage account keys (disabled entirely)
- Storage account connection strings

### IaC

Bicep is preferred but must not delay the MVP. Manual deployment is acceptable for initial setup — document what was provisioned.

---

## Communication Rules for Claude Code

- Explain architectural decisions briefly when they matter. Do not over-explain basics.
- Do not suggest alternative approaches unless asked. Pick the one defined here and implement it.
- Do not introduce dependencies not listed in this document without discussing the tradeoff first.
- When generating code, include only essential comments. No verbose explanations in code.
- If a request conflicts with this document, flag the conflict and ask for clarification.
- If a request is ambiguous, refer to the Core Loop. Does it serve the loop? If yes, proceed. If unclear, ask.

---

## What v1 Success Looks Like

A user can:
1. Sign up and log in with minimal friction
2. Create a Clique and invite friends via link, SMS, or QR code
3. Tap an invite link and land in the app at the right screen
4. Start an Event with a chosen duration (24h / 3 days / 7 days)
5. Take a photo or pick one from their gallery
6. See the photo appear in the event feed within seconds
7. React to others' photos
8. Save a photo to their device
9. Share a photo externally via the OS share sheet
10. Receive push notifications when new photos are added
11. See photos automatically disappear from the cloud when the event expires

If all eleven of these work cleanly on both iOS and Android, v1 is done.

---

## Companion Documents

| Document | Purpose |
|----------|---------|
| `PRD.md` | Product requirements, feature definitions, UX principles, branding |
| `ARCHITECTURE.md` | Full technical architecture, data model, security, deployment strategy |
| `ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Complete 5-layer token refresh implementation (code samples, debug tags, test procedures) |
