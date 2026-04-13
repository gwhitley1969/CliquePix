# ARCHITECTURE.md – Clique Pix v1

## Purpose

This document defines the technical architecture for **Clique Pix v1**, a private, event-based group photo sharing mobile application.

The architecture is designed to support the v1 product goals:
- fast private photo sharing
- clean mobile experience
- event-based organization
- automatic expiration of cloud photos
- production-grade security from day one

This is not a "someday" architecture. This is what we build and deploy.

---

# 1. Architecture Principles

1. **Build for production from day one** — Front Door, APIM, managed identity, RBAC. No shortcuts to retrofit later.
2. **Optimize for the core product loop** — every architectural decision serves the Clique → Event → Photo → Feed → Expire flow.
3. **Use managed Azure services** — minimize operational overhead, maximize reliability.
4. **Separate concerns cleanly** — UI, state, API client, and backend are distinct layers.
5. **No storage account keys anywhere** — RBAC and managed identity for all Azure resource access.
6. **Simple until proven otherwise** — do not introduce queues, caches, or event streaming until the product demands them.

---

# 2. Core Product Loop

Everything in the architecture must support this loop:

1. User signs in
2. User creates an Event (picks or creates a Clique during creation)
3. User takes or uploads a photo
5. Photo is compressed on-device and uploaded directly to Blob Storage
6. Other event members are notified via push
7. Event feed displays the photo (thumbnail in feed, full-size on tap)
8. Members can view, react, save to device, and share externally
9. Photo expires and is deleted automatically from the cloud

---

# 3. Tech Stack

## Mobile Frontend

**Flutter** — single codebase for iOS and Android.

Why Flutter for Clique Pix:
- strong visual consistency across platforms
- better control over branded UI, gradients, and animations
- excellent fit for a consumer app where look and feel are the product
- strong support for camera, local media, and native platform integrations

### Flutter Libraries

| Purpose | Package |
|---------|---------|
| State management | Riverpod |
| HTTP client | Dio |
| Image picker | image_picker |
| Image editor | pro_image_editor (^5.1.4 — crop, draw, stickers, emoji, filters, text) |
| Image compression | flutter_image_compress |
| Secure token storage | flutter_secure_storage |
| Non-sensitive flags | shared_preferences |
| Push notifications | firebase_messaging (FCM transport only — no Firebase backend services) |
| Image caching | cached_network_image |
| Deep links | app_links |
| QR code generation | qr_flutter |
| MSAL authentication | msal_auth (^3.3.0, Entra-compatible, v2 embedding) |

## Backend / Cloud (Azure)

| Layer | Service | Purpose |
|-------|---------|---------|
| Entry point | **Azure Front Door** (Standard) | Global load balancing, SSL termination |
| API gateway | **Azure API Management** | Rate limiting, API versioning, policy enforcement, single published API surface |
| Compute | **Azure Functions** (TypeScript, Node.js) | REST API endpoints, timer-triggered cleanup, thumbnail generation |
| Database | **PostgreSQL Flexible Server** | Relational data (users, cliques, events, photos, reactions) |
| Object storage | **Azure Blob Storage** | Photo originals and thumbnails |
| Identity (consumer) | **Microsoft Entra External ID** | User authentication (Google, Apple, email OTP) |
| Identity (infra) | **System-assigned managed identity** | Function App access to Blob Storage, Key Vault |
| Secrets | **Azure Key Vault** | Database connection string, push notification credentials |
| Observability | **Application Insights** | API telemetry, error tracking, dependency monitoring |
| Realtime messaging | **Azure Web PubSub** | Real-time DM delivery via WebSocket (Standard S1) |

### What Is Not In v1

| Service | Why deferred |
|---------|-------------|
| Azure Cache for Redis | Not needed at v1 scale |
| Azure SignalR Service | Web PubSub used instead for DMs |
| Azure Service Bus | No async workflow complexity needed yet |
| Azure Notification Hubs | Direct FCM/APNs is simpler; add Hubs if multi-platform orchestration grows |

---

# 4. High-Level Architecture

## Request Flow

All API traffic follows this path — no exceptions:

```
Flutter App → Azure Front Door → Azure API Management → Azure Functions → PostgreSQL / Blob Storage
```

No direct Function App URLs are exposed to the client. APIM is the single published API surface. Front Door handles SSL and global routing. Custom domain: `api.clique-pix.com`.

## Photo Upload Flow

Photo uploads bypass the Function App for the heavy payload:

```
Flutter App → POST /api/.../upload-url → Function validates + generates User Delegation SAS
Flutter App → PUT directly to Blob Storage (SAS URL) → upload bytes
Flutter App → POST /api/.../photos → Function confirms upload, writes metadata, triggers notifications
```

## Photo View Flow

```
Flutter App → GET /api/.../photos → Function returns metadata + short-lived read-only SAS URLs
Flutter App → GET directly from Blob Storage (SAS URL) → load thumbnail/original
```

---

# 5. Authentication Architecture

## Provider

**Microsoft Entra External ID** — Azure-native consumer identity (CIAM).

Supports:
- email-based signup with OTP / magic link
- social providers (Google, Apple) configured via Entra identity providers
- no Firebase dependency (FCM used for push transport only)

## Token Acquisition (MSAL)

The app uses `msal_auth` (^3.3.0) with a **custom API scope** to get a properly signed access token:

- **Exposed API scope**: `api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user`
- **MSAL scopes**: `['api://7db01206.../access_as_user']` — only the custom API scope
- OIDC scopes (`openid`, `profile`, `email`) are added implicitly by MSAL and must NOT be requested explicitly (mixing causes `MsalDeclinedScopeException`)

**Why this matters:** Without a custom API scope, MSAL returns a Microsoft Graph access token signed by Graph's keys. The backend cannot verify Graph tokens — only Microsoft Graph can. The custom API scope ensures MSAL returns an access token with `aud = clientId`, signed by the CIAM tenant's keys.

## iOS MSAL Platform Configuration

Three iOS-specific configurations are required for MSAL authentication:

1. **URL Scheme** (`Info.plist`): `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` — registered as a `CFBundleURLSchemes` entry. MSAL uses this to receive the auth callback from Safari after the user authenticates.
2. **Keychain Entitlements** (`Runner.entitlements`): Keychain group `$(AppIdentifierPrefix)com.microsoft.adalcache` — required by the MSAL iOS SDK for token caching and sign-out.
3. **AppDelegate URL Handler** (`AppDelegate.swift`): `MSALPublicClientApplication.handleMSALResponse()` in the `application(_:open:options:)` override — processes the callback URL from Safari.
4. **Azure Entra iOS Platform**: Bundle ID `com.cliquepix.app` registered under Authentication → iOS/macOS. The redirect URI (`msauth.com.cliquepix.app://auth`) is auto-generated by Azure.

The `AppleConfig` in `auth_repository.dart` uses `Broker.safariBrowser`, which presents `SFSafariViewController` for interactive authentication. No redirect URI is passed — MSAL auto-generates it from the bundle ID.

## Backend JWT Validation

The backend validates tokens using the CIAM tenant's OpenID configuration:

- **JWKS URI**: `https://cliquepix.ciamlogin.com/{tenantId}/discovery/v2.0/keys` (tenant **name** subdomain)
- **Expected issuer**: `https://{tenantId}.ciamlogin.com/{tenantId}/v2.0` (tenant **ID** subdomain)
- **Expected audience**: app client ID (`7db01206-135b-4a34-a4d5-2622d1a888bf`)

Note: The JWKS URI uses the tenant name as subdomain, but the issuer in tokens uses the tenant ID as subdomain. This is a CIAM quirk confirmed by the OpenID Connect discovery endpoint.

## Known Issue: 12-Hour Refresh Token Timeout

Entra External ID (CIAM) tenants have a **hardcoded 12-hour inactivity timeout** on refresh tokens. This is a confirmed Microsoft bug — standard Entra ID tenants get 90-day lifetimes. There are no portal-based configuration options to change this.

Error signature: `AADSTS700082: The refresh token has expired due to inactivity... inactive for 12:00:00`

### Required Mitigation: 5-Layer Token Refresh Defense

This pattern is proven in production on My AI Bartender. All five layers must be implemented.

| Layer | Mechanism | Trigger | Reliability | Purpose |
|-------|-----------|---------|-------------|---------|
| 1 | Battery Optimization Exemption | First login (Android) | Critical | Allows background tasks on Samsung/Xiaomi/Huawei |
| 2 | AlarmManager Token Refresh | Every 6 hours | Very High | Fires even in Doze mode via `exactAllowWhileIdle` |
| 3 | Foreground Refresh on App Resume | Every app open | Very High | Safety net — catches all background failures |
| 4 | WorkManager Background Task | Every 8 hours | Medium | Backup mechanism |
| 5 | Graceful Re-Login UX | When all else fails | N/A | "Welcome back" one-tap re-auth with stored user hint |

Key timing:
- Microsoft inactivity timeout: **12 hours** (hardcoded)
- AlarmManager / foreground refresh threshold: **6 hours** (half the timeout = safe margin)
- WorkManager interval: **8 hours** (backup)

Full implementation details, code samples, and debug log tags are in `ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

### Token Storage

- Auth tokens and refresh tokens: `flutter_secure_storage` only
- Non-sensitive flags (e.g., `has_seen_onboarding`): `shared_preferences` is acceptable
- Track `lastRefreshTime` in secure storage for proactive refresh decisions
- Clear all stored tokens and cancel all background refresh jobs on logout

### Android Permissions Required for Token Refresh

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

---

# 6. API Architecture

## Style

RESTful JSON APIs over HTTPS. No GraphQL. No event-driven backend patterns in v1.

## Endpoints

### Auth / Session
```
POST   /api/auth/verify
GET    /api/users/me
DELETE /api/users/me
```

### Cliques
```
POST   /api/cliques
GET    /api/cliques
GET    /api/cliques/{cliqueId}
POST   /api/cliques/{cliqueId}/invite
POST   /api/cliques/{cliqueId}/join
GET    /api/cliques/{cliqueId}/members
DELETE /api/cliques/{cliqueId}/members/me
DELETE /api/cliques/{cliqueId}/members/{userId}
```

**Member management:**
- `DELETE .../members/me` — member leaves clique (or sole owner deletes clique)
- `DELETE .../members/{userId}` — owner removes a specific member (owner-only, returns 403 for non-owners)
- Azure Functions route matching: literal `me` segment takes priority over parameterized `{userId}`, so no route conflict

### Events
```
POST   /api/cliques/{cliqueId}/events
GET    /api/cliques/{cliqueId}/events
GET    /api/events/{eventId}
DELETE /api/events/{eventId}
```

**Event list response fields:** `GET` endpoints return `photo_count` and `video_count` (conditional aggregation on `media_type`), along with `clique_name` and `member_count` for the all-events endpoint.

**Event deletion:**
- `DELETE /api/events/{eventId}` — only the event owner (organizer) can delete
- Deletes all photo blobs and video assets (original + HLS segments + MP4 fallback + poster) from Azure Storage before cascading the database delete (photos, videos, reactions, DM threads, DM messages)
- Sends push notification and in-app notification to clique members
- Hard delete — permanent, not recoverable

### Photos
```
POST   /api/events/{eventId}/photos/upload-url
POST   /api/events/{eventId}/photos
GET    /api/events/{eventId}/photos
GET    /api/photos/{photoId}
DELETE /api/photos/{photoId}
```

### Reactions
```
POST   /api/photos/{photoId}/reactions
DELETE /api/photos/{photoId}/reactions/{reactionId}
```

### Direct Messages (Event-Centric DMs)
```
POST   /api/events/{eventId}/dm-threads
GET    /api/events/{eventId}/dm-threads
GET    /api/dm-threads/{threadId}
GET    /api/dm-threads/{threadId}/messages
POST   /api/dm-threads/{threadId}/messages
PATCH  /api/dm-threads/{threadId}/read
POST   /api/realtime/dm/negotiate
```

**DM model:**
- 1:1 only, text-only, event-centric, ephemeral
- Threads tied to a specific event — same two users get a separate thread per event
- Threads become read-only when event expires, CASCADE-deleted when event is purged
- Real-time delivery via Azure Web PubSub (`sendToUser` for direct user-targeted delivery); FCM push for background/terminated app
- Rate limited: max 10 messages per minute per sender per thread

### Notifications
```
GET    /api/notifications
PATCH  /api/notifications/{notificationId}/read
DELETE /api/notifications/{notificationId}
DELETE /api/notifications
POST   /api/push-tokens
```

## Response Format

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
    "message": "The requested clique does not exist.",
    "request_id": "abc-123-def"
  }
}
```

`request_id` is the Azure Functions `invocationId` — included in every error response for correlation with App Insights logs. Use consistent error codes. Never return raw exception messages or stack traces to the client.

---

# 7. Data Architecture

## PostgreSQL Flexible Server

Relational model fits the cliques/events/memberships domain cleanly. Predictable structure, strong querying for feeds and membership checks.

## Core Tables

### users
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| external_auth_id | VARCHAR | Entra External ID subject |
| display_name | VARCHAR | |
| email_or_phone | VARCHAR | |
| avatar_url | VARCHAR | Nullable |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### cliques
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| name | VARCHAR | |
| invite_code | VARCHAR | Unique, for invite links and QR codes |
| created_by_user_id | UUID | Nullable, FK → users (ON DELETE SET NULL) |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### clique_members
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| clique_id | UUID | FK → cliques |
| user_id | UUID | FK → users |
| role | VARCHAR | owner / member |
| joined_at | TIMESTAMPTZ | |

Unique constraint on (clique_id, user_id).

### events
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| clique_id | UUID | FK → cliques |
| name | VARCHAR | |
| description | VARCHAR | Nullable |
| created_by_user_id | UUID | Nullable, FK → users (ON DELETE SET NULL) |
| retention_hours | INTEGER | 24, 72, or 168 (three presets only) |
| status | VARCHAR | active / expired |
| created_at | TIMESTAMPTZ | |
| expires_at | TIMESTAMPTZ | Computed: created_at + retention_hours |

### photos
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key, generated server-side at upload-url step |
| event_id | UUID | FK → events |
| uploaded_by_user_id | UUID | Nullable, FK → users (ON DELETE SET NULL) |
| blob_path | VARCHAR | e.g., photos/{cliqueId}/{eventId}/{photoId}/original.jpg |
| thumbnail_blob_path | VARCHAR | Nullable until thumbnail generated |
| original_filename | VARCHAR | |
| mime_type | VARCHAR | JPEG or PNG |
| width | INTEGER | From client metadata |
| height | INTEGER | From client metadata |
| file_size_bytes | BIGINT | From blob properties after upload |
| status | VARCHAR | pending / active / deleted |
| created_at | TIMESTAMPTZ | |
| expires_at | TIMESTAMPTZ | Inherits from event |
| deleted_at | TIMESTAMPTZ | Nullable, set by cleanup job |

Status flow: `pending` (after upload-url issued) → `active` (after client confirms upload) → `deleted` (after cleanup).

### reactions
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| photo_id | UUID | FK → photos |
| user_id | UUID | FK → users |
| reaction_type | VARCHAR | heart / laugh / fire / wow |
| created_at | TIMESTAMPTZ | |

Unique constraint on (photo_id, user_id, reaction_type).

### push_tokens
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| user_id | UUID | FK → users |
| platform | VARCHAR | ios / android |
| token | VARCHAR | FCM registration token |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### notifications
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| user_id | UUID | FK → users |
| type | VARCHAR | new_photo / event_expiring / event_expired / member_joined / event_deleted |
| payload_json | JSONB | Structured notification data |
| is_read | BOOLEAN | Default false |
| created_at | TIMESTAMPTZ | |

### event_dm_threads
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| event_id | UUID | FK → events (ON DELETE CASCADE) |
| user_a_id | UUID | FK → users (ON DELETE CASCADE), always < user_b_id |
| user_b_id | UUID | FK → users (ON DELETE CASCADE), always > user_a_id |
| status | VARCHAR | active / read_only |
| user_a_last_read_message_id | UUID | Nullable, FK → event_dm_messages |
| user_b_last_read_message_id | UUID | Nullable, FK → event_dm_messages |
| last_message_at | TIMESTAMPTZ | Nullable, updated on each new message |
| created_at | TIMESTAMPTZ | |

Unique constraint on (event_id, user_a_id, user_b_id). CHECK constraint ensures user_a_id < user_b_id to prevent duplicate threads.

### event_dm_messages
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| thread_id | UUID | FK → event_dm_threads (ON DELETE CASCADE) |
| sender_user_id | UUID | Nullable, FK → users (ON DELETE SET NULL) |
| body | TEXT | Max 2000 chars, non-empty enforced by CHECK |
| created_at | TIMESTAMPTZ | |

---

# 8. Object Storage Architecture

## Azure Blob Storage

Single storage account. Single container with virtual path hierarchy. No separate containers for originals and thumbnails.

### Container

Name: `photos`

### Path Convention

```
photos/{cliqueId}/{eventId}/{photoId}/original.jpg
photos/{cliqueId}/{eventId}/{photoId}/thumb.jpg
```

### Access Model — RBAC + User Delegation SAS

**No storage account keys. No account-key-based SAS tokens.**

All blob access is through one of two mechanisms:

| Access Type | Mechanism | Used By |
|-------------|-----------|---------|
| Server-side (thumbnail gen, cleanup, existence checks) | Managed identity via `DefaultAzureCredential` | Azure Functions |
| Client-side (upload, view/download) | User Delegation SAS (generated by managed identity) | Flutter app |

Storage account configuration:
- `allowSharedKeyAccess: true` — required because Azure Functions runtime (`AzureWebJobsStorage`) uses shared keys internally. All CliquePix application code uses `DefaultAzureCredential`. Migrate to identity-based `AzureWebJobsStorage__accountName` in v1.5 to fully disable.
- Public access: disabled on all containers
- Container access policy: private

### User Delegation SAS Rules

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Expiry | 5 minutes | Minimum practical window for upload |
| Permissions (upload) | Write only | Client cannot read, list, or delete |
| Permissions (view) | Read only | Client cannot write, list, or delete |
| Scope | Single blob path | Never container-level |
| Delegation Key caching | Up to 1 hour | Valid for up to 7 days, but rotate frequently |

### Required Managed Identity Roles

| Role | Purpose |
|------|---------|
| `Storage Blob Data Contributor` | Server-side read/write/delete (thumbnails, cleanup, validation) |
| `Storage Blob Delegator` | Generate User Delegation Keys for SAS token creation |

Both roles are required on the storage account.

---

# 9. Photo Upload Pipeline

## Client Side (Before Upload)

1. User captures photo or selects from gallery
2. User edits photo in `pro_image_editor` (crop, draw, stickers, emoji, filters, text)
3. Strip EXIF data (removes GPS coordinates, device info, timestamps)
4. Resize: longest edge max 2048px, maintain aspect ratio
5. Compress: JPEG quality 80
6. Convert HEIC to JPEG on-device before upload
7. Reject files over 10MB after compression (safety net)

### ProImageEditor Callback Pattern (v5.x)

ProImageEditor v5.x's `doneEditing()` calls `onImageEditingComplete` first (and awaits it), then **always** calls `onCloseEditor` afterward. The correct integration pattern:

- **`onImageEditingComplete`**: Save edited bytes to a temp file. Do NOT call `Navigator.pop()` — ProImageEditor will call `onCloseEditor` next.
- **`onCloseEditor`**: Call `Navigator.pop()` to dismiss the editor. If edited bytes were saved, update state to show the preview/upload screen.

Calling `Navigator.pop()` in both callbacks causes a double-pop that removes both the editor and the parent screen.

### Compression Rationale

| Setting | Value | Why |
|---------|-------|-----|
| Max dimension | 2048px | Covers all current phone screens. This is a group photo app, not a stock photography service. |
| JPEG quality | 80 | Industry standard for "visually indistinguishable." Quality 90+ wastes bytes; quality 70 shows artifacts on gradients and skin tones. |
| Max file size | 10MB | Post-compression safety net. At 2048px / quality 80, photos land around 500KB–1.5MB. |
| Format | JPEG | Universal compatibility. HEIC converted client-side. |

## Upload Flow

1. Client calls `POST /api/events/{eventId}/photos/upload-url`
2. Function validates Entra token and confirms user is a member of the event's clique
3. Function generates a photo ID and blob path, creates a photo record with status `pending`
4. Function uses managed identity to request a User Delegation Key, generates a write-only User Delegation SAS scoped to the exact blob path, 5-minute expiry
5. Function returns the SAS upload URL and photo ID
6. Client uploads compressed image directly to Blob Storage using the SAS URL
7. Client calls `POST /api/events/{eventId}/photos` with photo ID and client-side metadata (dimensions, MIME type)
8. Function verifies blob exists, reads blob properties (content type, file size), updates photo record to status `active`
9. Function triggers async thumbnail generation
10. Function sends push notifications to event members
11. Function returns complete photo record to client

If the client does not confirm upload (step 7) within 10 minutes, a cleanup process can treat the blob and pending record as orphaned.

## Server Side (After Upload Confirmed)

The Function never touches photo bytes during the upload flow. Post-confirmation:

1. Verify blob exists at expected path via managed identity
2. Read blob properties to validate content type (JPEG, PNG only) and file size (reject > 15MB)
3. Update photo metadata in PostgreSQL
4. Trigger thumbnail generation (async)

## Thumbnail Generation

- Triggered by blob upload event or queue message
- Function reads original blob via managed identity
- Generates thumbnail: 400px longest edge, JPEG quality 70
- Writes thumbnail to `photos/{cliqueId}/{eventId}/{photoId}/thumb.jpg` via managed identity
- Updates `thumbnail_blob_path` in photo record
- Target thumbnail size: ~30–80KB

If thumbnail generation fails, the feed falls back to loading the original (slower but not broken).

## Photo View / Download

- Feed endpoint returns photo metadata with short-lived read-only User Delegation SAS URLs for both thumbnail and original
- Feed cards load thumbnails only
- Full-size loads on photo detail view / full-screen tap
- Client uses `cached_network_image` for caching

---

# 10. Notification Architecture

## Purpose

Users must be notified when:
- a new photo is added to an active event
- someone joins one of their cliques
- an event is nearing expiration (24 hours before)

## Delivery

FCM (Firebase Cloud Messaging) for push delivery to both Android and iOS. FCM is a transport mechanism only — no Firebase backend services, no Firebase Auth, no Firestore. Messages use both `notification` (for OS-level display) and `data` (for app navigation) payloads via FCM HTTP v1 API.

### Notification Types

| Type | Trigger | Recipients | Payload |
|------|---------|------------|---------|
| `new_photo` | Photo uploaded to event | Event clique members (excl. uploader) | `{ event_id, photo_id }` |
| `member_joined` | User joins clique via invite | Existing clique members (excl. joiner) | `{ clique_id, clique_name, joined_user_name }` |
| `event_expiring` | Timer (24h before expiry) | Event clique members | `{ event_id }` |
| `event_expired` | Timer (after expiry) | Event clique members | `{ event_id }` |
| `event_deleted` | Event organizer deletes event | Clique members (excl. deleter) | `{ event_id, event_name }` |

**No notifications sent** for member removals or voluntary departures — the member simply disappears from the list.

### Push Notification Pipeline

**Backend (Azure Functions):**
1. Backend action (photo upload, clique join, timer) queries relevant members' push tokens from `push_tokens` table
2. Function sends push via FCM HTTP v1 API (`sendToMultipleTokens()`) with `notification` + `data` payloads
3. Function creates notification records in `notifications` table for in-app display
4. Failed token sends trigger stale token cleanup (`DELETE FROM push_tokens WHERE token = ANY($1)`)

**Client (Flutter) — three notification states:**

| App State | Handler | Display Mechanism |
|-----------|---------|-------------------|
| **Foreground** | `FirebaseMessaging.onMessage` in `main.dart` | `flutter_local_notifications.show()` — manually displays heads-up banner |
| **Background** | Android auto-displays from FCM `notification` payload | `FirebaseMessaging.onMessageOpenedApp` handles tap → navigates to clique/event |
| **Terminated** | Android auto-displays from FCM `notification` payload | `FirebaseMessaging.getInitialMessage()` handles cold-start tap → navigates |

**Key design:** The `onMessage` listener is set up in `main.dart` immediately after `flutter_local_notifications` plugin initialization — not in a separate service class. This ensures the plugin is always ready when `show()` is called.

### Notification Channel

Android 8.0+ requires notification channels. Created programmatically in `main.dart` at app startup:

```
Channel ID: cliquepix_default
Name: Clique Pix
Description: Photo sharing notifications
Importance: HIGH (heads-up banners)
```

Referenced in AndroidManifest as `com.google.firebase.messaging.default_notification_channel_id`.

### Android 13+ Permission

`POST_NOTIFICATIONS` runtime permission requested via `AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()` during app startup. Declared in AndroidManifest: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`.

### Push Token Management

- `PushNotificationService` registers FCM token after successful authentication via `POST /api/push-tokens`
- Listens to `FirebaseMessaging.instance.onTokenRefresh` for token rotation
- Backend upserts on conflict (`ON CONFLICT (token) DO UPDATE`)
- Token removed on logout
- Failed sends remove stale tokens

### Notification Tap Navigation

All notification taps (foreground local notification, background FCM, terminated cold-start) navigate via GoRouter:
- `data.event_id` → `router.push('/events/$eventId')`
- `data.clique_id` → `router.push('/cliques/$cliqueId')`

Foreground taps use a static callback pattern: `main.dart`'s `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter navigation.

### Future Enhancement

If multi-platform notification orchestration becomes complex, add Azure Notification Hubs as an abstraction layer. Not needed in v1.

---

# 11. Expiration / Deletion Architecture

## Product Requirement

Photos in the cloud must expire automatically after the event's retention window (24h, 72h, or 168h from event creation).

## Data Model

Each photo record stores:
- `created_at`
- `expires_at` (inherited from event)
- `deleted_at` (nullable, set by cleanup)
- `status` (pending → active → deleted)

## Cleanup Process

Timer-triggered Azure Function on a schedule (every 15 minutes):

1. Query photos where `expires_at < now()` and `status = 'active'`
2. Delete corresponding blobs (original + thumbnail) via managed identity
3. Update photo records: set `status = 'deleted'`, set `deleted_at = now()`
4. If all photos in an event are deleted, mark event `status = 'expired'`
5. Mark DM threads as `read_only` for expired events
6. Delete any remaining blobs for expired events (safety net)
7. **Hard-delete expired event records** from the database — CASCADE removes:
   - `photos` (FK `event_id` ON DELETE CASCADE)
   - `reactions` (FK `photo_id` ON DELETE CASCADE, cascaded from photos)
   - `event_dm_threads` (FK `event_id` ON DELETE CASCADE)
   - `event_dm_messages` (FK `thread_id` ON DELETE CASCADE, cascaded from threads)
8. Log `expired_photos_deleted` and `expired_events_deleted` telemetry events with counts

### Orphan Cleanup

Separate scheduled check for orphaned uploads:
- Query photos where `status = 'pending'` and `created_at < now() - 10 minutes`
- Delete the orphaned blob if it exists
- Delete the pending record

### Important Behavior

- Device-saved copies remain untouched — only cloud-managed copies are deleted
- Users are notified 24 hours before expiration via push notification
- Expired events are fully removed from the database, not soft-deleted

---

# 12. Real-Time / Near-Real-Time Feed Updates

## v1 Approach

Do not overbuild live infrastructure. The following is sufficient to feel responsive:

- Push notification on new photo / clique join → user taps to open relevant screen
- Refresh on app resume via `WidgetsBindingObserver` (`didChangeAppLifecycleState`)
- Pull-to-refresh via `RefreshIndicator` on list and detail screens
- 30-second polling via `Timer.periodic` while clique list/detail screens are active

This three-layer approach (push + app-resume + polling) covers all cases: push for immediate alerting, app-resume for returning users, polling for actively-open screens. Most photo sharing happens in bursts (everyone at the same event, actively using the app).

## Real-Time Channels (In Use)

Azure Web PubSub is used for two real-time channels (added during v1 development):

- **DM delivery:** event-centric 1:1 direct messages delivered via WebSocket, with FCM fallback for backgrounded users. See `docs/EVENT_DM_CHAT_ARCHITECTURE.md`.
- **Video processing-state push:** `video_ready` event pushed to all event members (including the uploader) so feed cards upgrade instantly when transcoding completes. See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 10.

The polling + push + app-resume approach above remains the primary feed update mechanism for photos and non-video content.

---

# 13. Deep Linking Architecture

## Purpose

Clique invites are core to the product loop. When a user taps an invite link (via SMS, social share, or QR code), the app must open directly to the invite acceptance screen.

## Link Format

```
https://clique-pix.com/invite/{inviteCode}
```

QR codes encode this same URL. Generate QR on the client using `qr_flutter`.

## Platform Configuration

### iOS — Universal Links
- Host `apple-app-site-association` at `https://clique-pix.com/.well-known/apple-app-site-association`
- Configure Associated Domains in Xcode: `applinks:clique-pix.com`
- Handle incoming link via `app_links` package in Flutter

### Android — App Links
- Host `assetlinks.json` at `https://clique-pix.com/.well-known/assetlinks.json`
- Configure intent filter in AndroidManifest with `autoVerify="true"`
- Handle incoming link via `app_links` package in Flutter

### Hosting the Well-Known Files

Served from Azure Static Web App (`swa-cliquepix-prod`). Static JSON files with proper MIME types and caching headers configured in `staticwebapp.config.json`.

- `apple-app-site-association`: Team ID `4ML27KY869`, bundle ID `com.cliquepix.app`, paths `/invite/*`
- `assetlinks.json`: Package `com.cliquepix.clique_pix`, SHA256 fingerprint (debug keystore; update for release)

### Invite Landing Page

`website/invite.html` — served via SWA rewrite rule `/invite/*` → `invite.html`:
- Extracts invite code from URL path
- Detects platform (iOS/Android/desktop) via user agent
- Android: Attempts `intent://` URI to open installed app; falls back to Play Store button
- iOS: Universal Links intercept before page loads; fallback shows App Store button
- Dark-themed, branded, with Open Graph meta tags for messaging app link previews

### Client Deep Link Handling

`DeepLinkService` initialized in `app.dart` — listens via `app_links` package for both cold-start and warm-start URIs. Extracts invite code from path, navigates to `/invite/:inviteCode` via GoRouter.

### Auth Gate for Invite Routes

Unauthenticated users hitting `/invite/{code}` are redirected to `/login?redirect=/invite/{code}`. After successful authentication, GoRouter reads the `redirect` query parameter and navigates to the invite screen. No code changes needed in the login screen — GoRouter's reactive rebuild (watching `authStateProvider`) handles the redirect automatically.

## Flow

1. **App installed + verified:** OS intercepts URL → app opens → `DeepLinkService` routes to `JoinCliqueScreen` → auto-joins clique
2. **App installed, not verified:** Browser loads `invite.html` → "Open in Clique Pix" button uses `intent://` (Android) → app opens
3. **App not installed:** Browser loads `invite.html` → shows branded page with app store download buttons and invite code for manual entry

---

# 14. Secret Management

## Azure Key Vault

Store in Key Vault:
- PostgreSQL connection string
- FCM server key / service account credentials
- Any future third-party API keys

**Not stored in Key Vault** (because managed identity eliminates the need):
- Storage account keys (disabled entirely)
- Storage account connection strings

## Function App Configuration

- Reference Key Vault secrets via Key Vault references in app settings (`@Microsoft.KeyVault(SecretUri=...)`)
- Never hardcode secrets in code or config files
- Never commit secrets to source control

---

# 15. Security

## API Authorization

Every API endpoint must enforce:
- user is authenticated (valid Entra token verified by the Function)
- user belongs to the clique/event they are accessing (membership check)
- user can only delete their own photos

## Blob Storage Security

- `allowSharedKeyAccess: true` — Azure Functions runtime requires shared keys for `AzureWebJobsStorage`; all CliquePix app code uses `DefaultAzureCredential` (v1.5: migrate to identity-based connection to fully disable)
- No account-key-based SAS tokens in application code
- Client upload/view via User Delegation SAS (scoped, short-lived, RBAC-backed)
- Server-side operations via managed identity + `DefaultAzureCredential`
- No public anonymous access on any container

## Privacy

- Private by default — no public feeds, no user directory, no content discovery
- Photo and video URLs are never permanent or publicly accessible (always behind short-lived SAS)
- Photo EXIF data stripped client-side before upload (GPS, device info, timestamps)
- Video metadata is NOT stripped client-side — original file is uploaded as-is; transcoded delivery files do not carry original metadata forward
- DM messages are event-scoped, text-only, and auto-deleted when the event expires
- Privacy Policy and Terms of Service accessible from the profile screen via in-app browser (`https://clique-pix.com/privacy.html`, `https://clique-pix.com/terms.html`)

## Client-Side Security

- Auth tokens in `flutter_secure_storage` only
- No tokens, credentials, or PII in debug logs
- Clear all auth state and cancel background refresh jobs on logout
- MSAL `browser_sign_out_enabled: true` in `msal_config.json` — clears browser session cookies on sign-out (prevents Google auto-login loop)
- `Prompt.login` on interactive `acquireToken` — forces re-authentication even if residual browser session exists
- `_pca = null` after sign-out — forces fresh MSAL instance on next login (prevents stale cached state)

---

# 16. Flutter Client Architecture

## Project Structure

Feature-based organization with clean separation of data, domain, and presentation:

```text
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

## State Management

**Riverpod.** One approach, used consistently throughout.

## Routing Architecture

**GoRouter** with `StatefulShellRoute.indexedStack` for bottom tab navigation (Home, Cliques, Notifications, Profile). Each tab is a `StatefulShellBranch` with its own navigation stack.

**Cross-shell navigation rule:** Screens outside the shell (e.g., Event Detail at `/events/:eventId`) must NOT push to routes inside a shell branch (e.g., `/cliques/:cliqueId`). Doing so causes broken back-navigation — the user gets stranded in the wrong tab instead of returning to the originating screen.

**Solution:** Top-level routes that reuse the same widgets but live outside the shell:
- `/view-clique/:cliqueId` → `CliqueDetailScreen` (for Event Detail → Clique)
- `/invite-to-clique/:cliqueId` → `InviteScreen` (for post-creation invite flow)
- Shell-internal routes (`/cliques/:cliqueId`, `/cliques/:cliqueId/invite`) remain for tab-based navigation

**Post-creation invite prompt:** When creating an event with a NEW clique, `GoRouter.extra` passes `{cliqueId, cliqueName}` to Event Detail. On `initState`, a modal bottom sheet prompts the user to invite friends. `extra` is ephemeral (not in URL, not restorable from deep links) — the prompt fires once per creation.

## Networking

**Dio** as the HTTP client. Configure with:
- Base URL pointing to the Front Door endpoint
- Auth interceptor that attaches the Entra access token
- Error interceptor that maps HTTP errors to typed failure classes
- Retry interceptor for transient failures

## Local Storage

- `flutter_secure_storage` for auth tokens and refresh tokens
- `shared_preferences` for non-sensitive flags only
- `cached_network_image` for image caching (thumbnails and full-size)

---

# 17. Environment Strategy

## Environments

- `dev` — local development, points to dev Azure resources
- `prod` — production Azure resources

Two environments is sufficient for solo development. Add a staging environment before public launch if needed.

## Configuration Separation

Maintain separate config per environment:
- API base URL (Front Door endpoint)
- Entra External ID tenant ID and client ID
- Application Insights instrumentation key
- FCM project credentials

Use Flutter flavor/environment mechanisms. Do not hardcode environment-specific values.

---

# 18. Deployment Strategy

## Backend

- Bicep for infrastructure provisioning (preferred, deferred to v1.5)
- **CI/CD implemented:** GitHub Actions workflows in `.github/workflows/`:
  - `backend-ci.yml` — lint (eslint) → type-check (tsc) → test (jest) on push/PR
  - `flutter-ci.yml` — analyze → test on push/PR
  - `transcoder-build.yml` — tsc → docker build → ACR push (main branch only)
- Manual deployment acceptable for Function App and transcoder image until CD is added

## Mobile

- Internal test builds first
- TestFlight for iOS beta testing
- Internal / closed testing track for Google Play
- Target Android first, iOS in parallel

---

# 19. Azure Resource Set

All resources for a given environment:

| Resource | Naming Convention |
|----------|-------------------|
| Resource Group | `rg-cliquepix-{env}` |
| Function App | `func-cliquepix-{env}` |
| Storage Account | `stcliquepix{env}` |
| PostgreSQL Flexible Server | `pg-cliquepix-{env}` |
| Application Insights | `appi-cliquepix-{env}` |
| Key Vault | `kv-cliquepix-{env}` |
| Front Door | `fd-cliquepix-{env}` |
| API Management | `apim-cliquepix-{env}` |
| Web PubSub | `wps-cliquepix-{env}` |

### Managed Identity Role Assignments

Function App system-assigned managed identity requires:

| Role | Scope | Purpose |
|------|-------|---------|
| `Storage Blob Data Contributor` | Storage account | Server-side blob read/write/delete |
| `Storage Blob Delegator` | Storage account | Generate User Delegation Keys for SAS tokens |
| `Key Vault Secrets User` | Key Vault | Read connection strings and credentials |

---

# 20. Observability

## Application Insights

Track these custom telemetry events:

- `clique_created`, `clique_joined`, `clique_left`
- `event_created`, `event_expired`, `event_deleted`
- `photo_upload_started`, `photo_upload_completed`, `photo_upload_failed`
- `photo_saved_to_device`
- `reaction_added`, `reaction_removed`
- `notification_sent`, `notification_send_failed`
- `expired_photos_deleted` (include count)
- `orphaned_uploads_cleaned` (include count)
- `token_refresh_success`, `token_refresh_failed` (include layer that triggered it)
- `dm_thread_created`, `dm_message_sent`, `dm_message_send_failed`
- `dm_push_sent`, `dm_thread_marked_read_only`

## Logging Rules

Log enough to troubleshoot, not enough to leak:
- Always log: correlation IDs, error codes, function execution duration
- Never log: auth tokens, storage credentials, user PII, raw photo content

---

# 21. Future Evolution Path

## Likely Post-v1 Additions

- Premium subscription tier
- Printed albums
- ~~Multi-photo bulk save / download~~ (implemented in v1)
- ~~Video support~~ (implemented in v1 — capture, upload, transcode, HLS playback, local-first uploader UX)
- Event recap / AI-assisted highlights
- Silent push for iOS token refresh reliability

## Architecture Readiness

The v1 architecture leaves room to add:
- Azure Service Bus (for async workflow orchestration)
- Azure Cache for Redis (if feed performance demands it)
- ~~Azure Web PubSub~~ (added in v1 for event DMs)
- Azure Notification Hubs (if push orchestration grows complex)
- Richer thumbnail pipeline (multiple sizes, lazy generation)

None of these require rewriting the core architecture. They are additive.

---

# 22. Final Architecture Position

Clique Pix v1 is a **production-grade, Azure-first, mobile-first application**. It uses managed identity and RBAC throughout, routes all traffic through Front Door and APIM, and handles the known Entra External ID token bug with a proven multi-layer defense.

The architecture is:
- **Secure** — no storage keys, no long-lived credentials, RBAC everywhere
- **Clean** — clear separation of concerns, consistent patterns
- **Practical** — production-ready without being overbuilt
- **Aligned to the product** — every component serves the core photo sharing loop

---

# Companion Documents

| Document | Purpose |
|----------|---------|
| `PRD.md` | Product requirements, features, UX principles, branding |
| `CLAUDE.md` | Development guardrails, locked decisions, implementation rules for Claude Code |
| `ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Complete 5-layer token refresh implementation (code samples, debug tags, test procedures) |
| `EVENT_DM_CHAT_ARCHITECTURE.md` | Event-centric 1:1 DM design: Web PubSub delivery, schema, auth rules |
| `VIDEO_ARCHITECTURE_DECISIONS.md` | 15 video architecture decisions (transcoder, HLS delivery, stream-copy fast path, local-first playback, etc.) |
| `VIDEO_LOCAL_FIRST_UPLOADER_ARCHITECTURE.md` | Local-first uploader playback handoff doc — architecture and implementation |
| `VIDEO_INFRASTRUCTURE_RUNBOOK.md` | As-built runbook for video Azure infra (ACR, Container Apps, KEDA, RBAC) |
| `NOTIFICATION_SYSTEM.md` | Push notification architecture: FCM payloads, Web PubSub events, token lifecycle |
| `BETA_TEST_PLAN.md` | Manual smoke test checklist for beta releases |
| `BETA_OPERATIONS_RUNBOOK.md` | Incident response, troubleshooting, DB backup/restore, key rotation, cost monitoring |
