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
2. **Optimize for the core product loop** — every architectural decision serves the Circle → Event → Photo → Feed → Expire flow.
3. **Use managed Azure services** — minimize operational overhead, maximize reliability.
4. **Separate concerns cleanly** — UI, state, API client, and backend are distinct layers.
5. **No storage account keys anywhere** — RBAC and managed identity for all Azure resource access.
6. **Simple until proven otherwise** — do not introduce queues, caches, or event streaming until the product demands them.

---

# 2. Core Product Loop

Everything in the architecture must support this loop:

1. User signs in
2. User creates or joins a Circle
3. User creates an Event
4. User takes or uploads a photo
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
| Image compression | flutter_image_compress |
| Secure token storage | flutter_secure_storage |
| Non-sensitive flags | shared_preferences |
| Push notifications | firebase_messaging (FCM transport only — no Firebase backend services) |
| Image caching | cached_network_image |
| Deep links | app_links |
| QR code generation | qr_flutter |
| MSAL authentication | msal_flutter (or equivalent Entra-compatible package) |

## Backend / Cloud (Azure)

| Layer | Service | Purpose |
|-------|---------|---------|
| Entry point | **Azure Front Door** | Global load balancing, SSL termination, WAF |
| API gateway | **Azure API Management** | Rate limiting, API versioning, policy enforcement, single published API surface |
| Compute | **Azure Functions** (TypeScript, Node.js) | REST API endpoints, timer-triggered cleanup, thumbnail generation |
| Database | **PostgreSQL Flexible Server** | Relational data (users, circles, events, photos, reactions) |
| Object storage | **Azure Blob Storage** | Photo originals and thumbnails |
| Identity (consumer) | **Microsoft Entra External ID** | User authentication (magic link / OTP) |
| Identity (infra) | **System-assigned managed identity** | Function App access to Blob Storage, Key Vault |
| Secrets | **Azure Key Vault** | Database connection string, push notification credentials |
| Observability | **Application Insights** | API telemetry, error tracking, dependency monitoring |

### What Is Not In v1

| Service | Why deferred |
|---------|-------------|
| Azure Cache for Redis | Not needed at v1 scale |
| Azure SignalR / Web PubSub | Push notifications + pull-to-refresh is sufficient for v1 |
| Azure Service Bus | No async workflow complexity needed yet |
| Azure Notification Hubs | Direct FCM/APNs is simpler; add Hubs if multi-platform orchestration grows |

---

# 4. High-Level Architecture

## Request Flow

All API traffic follows this path — no exceptions:

```
Flutter App → Azure Front Door → Azure API Management → Azure Functions → PostgreSQL / Blob Storage
```

No direct Function App URLs are exposed to the client. APIM is the single published API surface. Front Door handles SSL, WAF, and global routing.

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
- social providers (Google, Apple) can be added later via Entra configuration
- no Firebase dependency

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
```

### Circles
```
POST   /api/circles
GET    /api/circles
GET    /api/circles/{circleId}
POST   /api/circles/{circleId}/invite
POST   /api/circles/{circleId}/join
GET    /api/circles/{circleId}/members
DELETE /api/circles/{circleId}/members/me
```

### Events
```
POST   /api/circles/{circleId}/events
GET    /api/circles/{circleId}/events
GET    /api/events/{eventId}
```

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

### Notifications
```
GET    /api/notifications
PATCH  /api/notifications/{notificationId}/read
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
    "code": "CIRCLE_NOT_FOUND",
    "message": "The requested circle does not exist."
  }
}
```

Use consistent error codes. Never return raw exception messages or stack traces to the client.

---

# 7. Data Architecture

## PostgreSQL Flexible Server

Relational model fits the circles/events/memberships domain cleanly. Predictable structure, strong querying for feeds and membership checks.

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

### circles
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| name | VARCHAR | |
| invite_code | VARCHAR | Unique, for invite links and QR codes |
| created_by_user_id | UUID | FK → users |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### circle_members
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| circle_id | UUID | FK → circles |
| user_id | UUID | FK → users |
| role | VARCHAR | owner / member |
| joined_at | TIMESTAMPTZ | |

Unique constraint on (circle_id, user_id).

### events
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| circle_id | UUID | FK → circles |
| name | VARCHAR | |
| description | VARCHAR | Nullable |
| created_by_user_id | UUID | FK → users |
| retention_hours | INTEGER | 24, 72, or 168 (three presets only) |
| status | VARCHAR | active / expired |
| created_at | TIMESTAMPTZ | |
| expires_at | TIMESTAMPTZ | Computed: created_at + retention_hours |

### photos
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key, generated server-side at upload-url step |
| event_id | UUID | FK → events |
| uploaded_by_user_id | UUID | FK → users |
| blob_path | VARCHAR | e.g., photos/{circleId}/{eventId}/{photoId}/original.jpg |
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
| type | VARCHAR | new_photo / event_expiring / event_expired |
| payload_json | JSONB | Structured notification data |
| is_read | BOOLEAN | Default false |
| created_at | TIMESTAMPTZ | |

---

# 8. Object Storage Architecture

## Azure Blob Storage

Single storage account. Single container with virtual path hierarchy. No separate containers for originals and thumbnails.

### Container

Name: `photos`

### Path Convention

```
photos/{circleId}/{eventId}/{photoId}/original.jpg
photos/{circleId}/{eventId}/{photoId}/thumb.jpg
```

### Access Model — RBAC + User Delegation SAS

**No storage account keys. No account-key-based SAS tokens.**

All blob access is through one of two mechanisms:

| Access Type | Mechanism | Used By |
|-------------|-----------|---------|
| Server-side (thumbnail gen, cleanup, existence checks) | Managed identity via `DefaultAzureCredential` | Azure Functions |
| Client-side (upload, view/download) | User Delegation SAS (generated by managed identity) | Flutter app |

Storage account configuration:
- `allowSharedKeyAccess: false`
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
2. Strip EXIF data (removes GPS coordinates, device info, timestamps)
3. Resize: longest edge max 2048px, maintain aspect ratio
4. Compress: JPEG quality 80
5. Convert HEIC to JPEG on-device before upload
6. Reject files over 10MB after compression (safety net)

### Compression Rationale

| Setting | Value | Why |
|---------|-------|-----|
| Max dimension | 2048px | Covers all current phone screens. This is a group photo app, not a stock photography service. |
| JPEG quality | 80 | Industry standard for "visually indistinguishable." Quality 90+ wastes bytes; quality 70 shows artifacts on gradients and skin tones. |
| Max file size | 10MB | Post-compression safety net. At 2048px / quality 80, photos land around 500KB–1.5MB. |
| Format | JPEG | Universal compatibility. HEIC converted client-side. |

## Upload Flow

1. Client calls `POST /api/events/{eventId}/photos/upload-url`
2. Function validates Entra token and confirms user is a member of the event's circle
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
- Writes thumbnail to `photos/{circleId}/{eventId}/{photoId}/thumb.jpg` via managed identity
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
- an event is nearing expiration (24 hours before)

## Delivery

Use direct FCM (Firebase Cloud Messaging) for push delivery to both Android and iOS. FCM is a transport mechanism only — no Firebase backend services, no Firebase Auth, no Firestore.

### Flow

1. User registers push token via `POST /api/push-tokens`
2. When a photo is uploaded, the confirming Function queries event members' push tokens
3. Function sends push notification via FCM HTTP v1 API
4. Notification payload includes event ID and photo ID for deep navigation

### Push Token Management

- Store tokens in `push_tokens` table
- Update on each app launch (tokens rotate)
- Remove on logout
- Handle token expiry gracefully (failed sends remove stale tokens)

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

Timer-triggered Azure Function on a schedule (e.g., every 15 minutes):

1. Query photos where `expires_at < now()` and `status = 'active'`
2. Delete corresponding blobs (original + thumbnail) via managed identity
3. Update photo records: set `status = 'deleted'`, set `deleted_at = now()`
4. If all photos in an event are deleted, update event status to `expired`
5. Log `expired_photos_deleted` telemetry event with count

### Orphan Cleanup

Separate scheduled check for orphaned uploads:
- Query photos where `status = 'pending'` and `created_at < now() - 10 minutes`
- Delete the orphaned blob if it exists
- Delete the pending record

### Important Behavior

- Device-saved copies remain untouched — only cloud-managed copies are deleted
- Users are notified 24 hours before expiration via push notification

---

# 12. Real-Time / Near-Real-Time Feed Updates

## v1 Approach

Do not overbuild live infrastructure. The following is sufficient to feel responsive:

- Push notification on new photo → user taps to open feed
- Refresh feed on app open / app resume / pull-to-refresh
- Optional short polling while event feed is actively open (every 30 seconds)

This is enough. Most photo sharing happens in bursts (everyone at the same event, actively using the app). The push + pull-to-refresh pattern covers the offline-then-open case.

## Future Option

If true real-time becomes a strong requirement post-v1, consider Azure Web PubSub or SignalR. Not needed now.

---

# 13. Deep Linking Architecture

## Purpose

Circle invites are core to the product loop. When a user taps an invite link (via SMS, social share, or QR code), the app must open directly to the invite acceptance screen.

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

The `.well-known` files can be served from Azure Front Door or a simple static web app. They are static JSON files that rarely change.

## Flow

1. **App installed:** open app, route to invite acceptance screen with `inviteCode`, call `POST /api/circles/{circleId}/join`
2. **App not installed:** open App Store / Play Store listing. Deferred deep linking (remembering the invite across install) is a post-v1 enhancement.

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
- user belongs to the circle/event they are accessing (membership check)
- user can only delete their own photos

## Blob Storage Security

- `allowSharedKeyAccess: false` on the storage account
- No account-key-based SAS tokens anywhere
- Client upload/view via User Delegation SAS (scoped, short-lived, RBAC-backed)
- Server-side operations via managed identity + `DefaultAzureCredential`
- No public anonymous access on any container

## Privacy

- Private by default — no public feeds, no user directory, no content discovery
- Photo URLs are never permanent or publicly accessible (always behind short-lived SAS)
- EXIF data stripped client-side before upload (GPS, device info, timestamps)

## Client-Side Security

- Auth tokens in `flutter_secure_storage` only
- No tokens, credentials, or PII in debug logs
- Clear all auth state and cancel background refresh jobs on logout

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
    /circles              # Circle CRUD, invites, membership
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

- Bicep for infrastructure provisioning (preferred, but must not delay MVP)
- CI/CD for Function App deployment when ready
- Manual deployment is acceptable for initial setup — document what was provisioned

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

- `circle_created`, `circle_joined`, `circle_left`
- `event_created`, `event_expired`
- `photo_upload_started`, `photo_upload_completed`, `photo_upload_failed`
- `photo_saved_to_device`
- `reaction_added`, `reaction_removed`
- `notification_sent`, `notification_send_failed`
- `expired_photos_deleted` (include count)
- `orphaned_uploads_cleaned` (include count)
- `token_refresh_success`, `token_refresh_failed` (include layer that triggered it)

## Logging Rules

Log enough to troubleshoot, not enough to leak:
- Always log: correlation IDs, error codes, function execution duration
- Never log: auth tokens, storage credentials, user PII, raw photo content

---

# 21. Future Evolution Path

## Likely Post-v1 Additions

- Premium subscription tier
- Printed albums
- Multi-photo bulk save / download
- Video support
- Event recap / AI-assisted highlights
- Silent push for iOS token refresh reliability

## Architecture Readiness

The v1 architecture leaves room to add:
- Azure Service Bus (for async workflow orchestration)
- Azure Cache for Redis (if feed performance demands it)
- Azure SignalR / Web PubSub (if real-time feed updates are needed)
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
