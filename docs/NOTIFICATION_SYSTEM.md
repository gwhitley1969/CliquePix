# Clique Pix Notification System

**Last Updated**: April 10, 2026

This document describes the notification architecture for Clique Pix — push notifications (FCM), real-time events (Web PubSub), in-app notification list, and the push token lifecycle.

---

## Overview

Clique Pix uses three notification channels:

| Channel | Technology | Purpose | Latency |
|---------|-----------|---------|---------|
| **Push notifications** | Firebase Cloud Messaging (FCM) | Background/terminated delivery, heads-up banners | 1-3 seconds |
| **Real-time events** | Azure Web PubSub | Foreground delivery for DMs and video_ready | Sub-second |
| **In-app list** | PostgreSQL `notifications` table | Persistent notification history | On-demand fetch |

FCM is a **transport mechanism only** — no Firebase backend services (Auth, Firestore, etc.) are used.

---

## Notification Types

### Complete trigger matrix

| Trigger | Type | FCM Recipients | Web PubSub Recipients | DB Record | Payload |
|---------|------|---------------|----------------------|-----------|---------|
| Photo uploaded | `new_photo` | All event members except uploader | -- | All except uploader | `{ event_id, photo_id }` |
| Video ready | `video_ready` | All event members **except** uploader | All event members **including** uploader | All except uploader | `{ type, event_id, video_id }` |
| Video processing failed | `video_processing_failed` | Uploader only | -- | Uploader only | `{ type, event_id, video_id }` |
| DM message sent | `dm_message` | Recipient only (fallback) | Recipient only (primary) | -- | `{ thread_id, event_id, type }` |
| User joins clique | `member_joined` | All existing members except joiner | -- | All except joiner | `{ clique_id }` |
| Event expiring (24h) | `event_expiring` | All event members | -- | All members | `{ event_id }` |
| Event deleted | `event_deleted` | All clique members except deleter | -- | All except deleter | `{ event_id }` |
| **Token refresh (silent / invisible)** | `token_refresh` (silent) | Users inactive 9-11h, max 1/6h per user | -- | -- | `{ type: 'token_refresh', userId }` |

The `token_refresh` push is **silent** (no `notification` block, no user-visible UI). It wakes the app in the background so MSAL `acquireTokenSilent` can run before the Entra 12h inactivity cliff. Triggered by `refreshTokenPushTimer` in `backend/src/functions/timers.ts`. See `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` for the full Layer 2 design.

### Explicit non-triggers

These actions do **not** generate any notifications:

- Member removed from clique (no push, no in-app)
- Member voluntarily leaves clique (no push, no in-app)
- Video upload started / processing begins (feed placeholder card is sufficient signal)
- Event expired (the 24h warning covers this; by expiration, media is deleted)

### Why video_ready has split recipient lists

The uploader needs the Web PubSub `video_ready` signal so their instant-preview card upgrades from "Processing for sharing..." to the standard active state with poster + play icon. Without it, the uploader sees a stale processing card until the 30-second feed poll fires.

But the uploader does **not** need an FCM push about their own video — they already saw the upload complete on their device. A push would be redundant noise.

Other clique members need both channels: Web PubSub for instant feed refresh when foregrounded, FCM for background notification when the app isn't open.

---

## FCM Implementation

### Backend service

**File:** `backend/src/shared/services/fcmService.ts`

**Credential loading:**
- `FCM_CREDENTIALS` environment variable contains JSON service account credentials (`client_email`, `private_key`, `project_id`)
- JWT authentication with Firebase Messaging scope
- Token cached with automatic refresh before expiry (~3500s TTL)

**Key functions:**

| Function | Purpose |
|----------|---------|
| `sendPushNotification(message)` | Single-token send via FCM HTTP v1 API. `message.silent` routes through `buildFcmMessageBody` for background delivery |
| `sendToMultipleTokens(tokens, title, body, data)` | Batch visible-push send via `Promise.all()` — returns array of failed tokens for cleanup |
| `sendSilentToMultipleTokens(tokens, data)` | Batch silent-push send. Used by `refreshTokenPushTimer` (Entra Layer 2) |
| `buildFcmMessageBody(message)` | Exported for unit tests — builds the FCM v1 body, branching on `message.silent` |

**Visible payload structure** (`new_photo`, `video_ready`, DMs, etc.):
```json
{
  "token": "<fcm_token>",
  "notification": {
    "title": "New Photo!",
    "body": "Alice shared a photo"
  },
  "data": {
    "event_id": "uuid",
    "photo_id": "uuid"
  }
}
```

The `notification` payload drives OS-level display (title, body, sound). The `data` payload drives client-side routing on tap.

**Silent payload structure** (`token_refresh` — new 2026-04-19):
```json
{
  "token": "<fcm_token>",
  "data": {
    "type": "token_refresh",
    "userId": "uuid"
  },
  "android": { "priority": "high" },
  "apns": {
    "headers": {
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-topic": "com.cliquepix.app"
    },
    "payload": { "aps": { "content-available": 1 } }
  }
}
```

No `notification` block — this push must NOT display anything to the user. Required headers:
- **iOS:** `apns-push-type: background` + `apns-priority: 5` + `content-available: 1` wakes the app in the background. Priority 10 would be rejected by APNs for background-type pushes.
- **Android:** `android.priority: high` is required for data-only messages to wake the app. Without it, FCM may delay delivery until the next user-initiated action.

Client handling:
- **Foreground:** `PushNotificationService` listens on `FirebaseMessaging.onMessage` and branches on `data['type'] == 'token_refresh'` → calls `AuthRepository.refreshToken()`. The separate `_handleForegroundFcmMessage` listener in `main.dart` is a no-op for silent pushes because `message.notification` is null and the function returns early.
- **Background / terminated:** `_firebaseMessagingBackgroundHandler` (top-level, `@pragma('vm:entry-point')`) creates a fresh `SingleAccountPca` and runs `acquireTokenSilent`. On iOS plugin-channel failure, it sets `pendingRefreshFlagKey` in SharedPreferences which `AppLifecycleService` picks up on next foreground.

### Stale token cleanup

After every `sendToMultipleTokens()` call, the backend collects failed tokens and deletes them:

```sql
DELETE FROM push_tokens WHERE token = ANY($1)
```

This runs immediately after the send — no separate cleanup job needed. A token typically goes stale when a user reinstalls the app, changes devices, or revokes notification permissions.

---

## Web PubSub Implementation

### Backend service

**File:** `backend/src/shared/services/webPubSubService.ts`

**Hub name:** `cliquepix`

| Function | Purpose |
|----------|---------|
| `getClientAccessToken(userId)` | Returns WebSocket URL for client connection |
| `sendToUser(userId, payload)` | Send event to a specific user |
| `publishToThread(threadId, payload)` | Send event to all users in a DM thread |
| `addUserToThreadGroup(threadId, userId)` | Subscribe user to a thread's message stream |
| `removeUserFromThreadGroup(threadId, userId)` | Unsubscribe user from thread |

### Token negotiation endpoint

`POST /api/realtime/dm/negotiate` — returns a WebSocket URL with an embedded access token. The client connects via this URL to receive real-time events.

**Token TTL:** Standard Web PubSub access token lifetime (60 minutes by default).

### Events published

| Event Type | Payload | When |
|------------|---------|------|
| `dm_message_created` | `{ type, threadId, message: { id, body, senderId, createdAt } }` | DM message sent |
| `video_ready` | `{ type: 'video_ready', event_id, video_id }` | Video transcoding complete |

---

## Push Token Lifecycle

### Registration

**Flutter service:** `app/lib/services/push_notification_service.dart`

1. After successful authentication, `PushNotificationService.initialize()` is called
2. `FirebaseMessaging.instance.getToken()` obtains the FCM registration token
3. Token registered via `POST /api/push-tokens` with platform (`ios` or `android`)
4. Backend upserts — same token updates timestamp, new token creates record

### Token refresh

```dart
messaging.onTokenRefresh.listen(_registerToken);
```

FCM/APNs may rotate tokens at any time (app update, OS update, token invalidation). The listener re-registers automatically.

### Cleanup

- **On send failure:** Stale tokens deleted immediately after `sendToMultipleTokens()` (see above)
- **On logout:** Token removed from backend via `DELETE FROM push_tokens WHERE user_id = $1`
- **On account deletion:** CASCADE delete removes all push tokens with the user record

### Database schema

```sql
-- push_tokens table
id UUID PRIMARY KEY,
user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
token TEXT NOT NULL,
created_at TIMESTAMPTZ DEFAULT NOW(),
updated_at TIMESTAMPTZ DEFAULT NOW()
```

---

## Android Notification Channel

**File:** `app/lib/main.dart`

Created programmatically at app startup:

| Property | Value |
|----------|-------|
| Channel ID | `cliquepix_default` |
| Channel Name | `Clique Pix` |
| Description | `Photo sharing notifications` |
| Importance | `HIGH` (heads-up banners) |

```dart
await androidPlugin.createNotificationChannel(
  const AndroidNotificationChannel(
    'cliquepix_default',
    'Clique Pix',
    description: 'Photo sharing notifications',
    importance: Importance.high,
  ),
);
```

**Android 13+ permission:** Requested explicitly via `requestNotificationsPermission()` after plugin initialization.

**iOS permissions:** Handled by FCM's built-in permission request (`requestPermission()` on `FirebaseMessaging`).

---

## Client Message Handling

### Three app states

| App State | Handler | Display | Routing |
|-----------|---------|---------|---------|
| **Foreground** | `FirebaseMessaging.onMessage` | `flutter_local_notifications.show()` heads-up banner | `onDidReceiveNotificationResponse` callback |
| **Background** | OS auto-displays from FCM `notification` payload | System notification tray | `onMessageOpenedApp` → `_navigateFromNotification()` |
| **Terminated** | OS auto-displays from FCM `notification` payload | System notification tray | `getInitialMessage()` → `_navigateFromNotification()` |

### Foreground notification display

**File:** `app/lib/main.dart`, `_handleForegroundFcmMessage()`

When a push arrives while the app is open:
1. FCM `onMessage` listener fires
2. `notificationsListProvider` is invalidated (refreshes in-app notification list)
3. `flutter_local_notifications.show()` displays a heads-up banner using `_fcmNotificationDetails`

```dart
const _fcmNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'cliquepix_default',
    'Clique Pix',
    channelDescription: 'Photo sharing notifications',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  ),
  iOS: DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  ),
);
```

### Notification tap routing

Two callsites — keep them in sync.

**FCM tap (background / terminated / foreground-tap):** `app/lib/services/push_notification_service.dart`, `_navigateFromNotification()`

| Data Keys | Route |
|-----------|-------|
| `type: 'video_ready'` + `event_id` + `video_id` | `/events/{eventId}/videos/{videoId}` |
| `type: 'video_processing_failed'` + `event_id` | `/events/{eventId}` |
| `type: 'dm_message'` + `thread_id` + `event_id` | `/events/{eventId}/dm/{threadId}` |
| `event_id` (default) | `/events/{eventId}` |
| `clique_id` (no event) | `/cliques/{cliqueId}` |

**In-app list tap:** `app/lib/features/notifications/presentation/notifications_screen.dart`, `_handleNotificationTap()`

| `notification.type` | Required `payload_json` keys | Route |
|---------------------|------------------------------|-------|
| `new_photo` | `event_id`, `photo_id` | `/events/{eventId}/photos/{photoId}` |
| `new_video` / `video_ready` | `event_id`, `video_id` | `/events/{eventId}/videos/{videoId}` |
| `video_processing_failed` | `event_id` | `/events/{eventId}` |
| `event_expiring` / `event_expired` / `event_deleted` | `event_id` | `/events/{eventId}` |
| `member_joined` | `clique_id` | `/cliques/{cliqueId}` |
| Anything else / row missing its required key | — | Fallback: `event_id` → `/events/{eventId}` ; else `clique_id` → `/cliques/{cliqueId}` ; else no-op |

`markRead` always fires first regardless of which branch is taken, so the unread dot disappears even when a row has nowhere meaningful to navigate. All payload reads use `as String?` so a malformed JSONB row falls through to the fallback rather than crashing.

**FCM/in-app divergence on `new_photo`:** the FCM handler still bottoms out on `event_id` for `new_photo` rather than deep-linking to the photo. This is intentional for now — a stale FCM push minutes after the photo was deleted would 404 the user. The in-app list is safe to deep-link because the row was just fetched from the DB. Backfilling the FCM handler is a tracked follow-up.

**`dm_message` is not stored in the in-app list.** The `notifications.type` CHECK constraint forbids it; DM notifications are FCM-only. Don't add a `dm_message` branch to `_handleNotificationTap`.

---

## In-App Notification List

### Backend

**File:** `backend/src/functions/notifications.ts`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `GET /api/notifications` | GET | Fetch paginated notifications (cursor + limit, default 50) |
| `PATCH /api/notifications/{id}/read` | PATCH | Mark single notification as read |
| `DELETE /api/notifications/{id}` | DELETE | Delete single notification |
| `DELETE /api/notifications` | DELETE | Clear all user's notifications |

### Database schema

```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN (
    'new_photo', 'new_video', 'video_ready', 'video_processing_failed',
    'event_expiring', 'event_expired', 'member_joined', 'event_deleted'
  )),
  payload_json JSONB NOT NULL DEFAULT '{}',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
```

Note: `new_video` and `event_expired` are in the schema CHECK constraint but are not currently used in code. They exist for forward compatibility.

### Flutter screen

**File:** `app/lib/features/notifications/presentation/notifications_screen.dart`

- Gradient header, scrollable list
- Type-specific icons and color gradients per notification type (covers all eight schema types — `new_photo`, `new_video`, `video_ready`, `video_processing_failed`, `event_expiring`, `event_expired`, `event_deleted`, `member_joined`)
- Unread dot indicator
- "Time ago" display (e.g., "2 hours ago")
- Tap routing — type-aware via `_handleNotificationTap` (table above)
- Per-row delete — two affordances, both gated on the shared `confirmDestructive` dialog and both showing a floating SnackBar on success / a red error SnackBar on failure:
  - **Trailing trash IconButton** (discoverable single-tap affordance on every row). Lives outside the row's InkWell so its taps don't bubble to `onTap`.
  - **Swipe-to-dismiss (right-to-left)**. Uses `Dismissible.confirmDismiss` so the row only animates out on a successful `DELETE /api/notifications/{id}` — failed API calls snap the row back instead of disappearing-then-reappearing on next refresh.
- "Clear All" — separate confirmation dialog, surfaced both as a SliverAppBar action and an in-list TextButton row
- Empty state: "You'll be notified when new photos are shared"

---

## FCM Payload Structure per Notification Type

### new_photo

```json
{
  "notification": {
    "title": "New Photo!",
    "body": "Alice shared a photo"
  },
  "data": {
    "event_id": "uuid",
    "photo_id": "uuid"
  }
}
```

### video_ready

```json
{
  "notification": {
    "title": "New video ready",
    "body": "A new video has been added to your event"
  },
  "data": {
    "type": "video_ready",
    "event_id": "uuid",
    "video_id": "uuid"
  }
}
```

### video_processing_failed

```json
{
  "notification": {
    "title": "Video upload failed",
    "body": "We couldn't process your video. Try uploading again."
  },
  "data": {
    "type": "video_processing_failed",
    "event_id": "uuid",
    "video_id": "uuid"
  }
}
```

### dm_message

```json
{
  "notification": {
    "title": "Message from Alice",
    "body": "On our way now"
  },
  "data": {
    "thread_id": "uuid",
    "event_id": "uuid",
    "type": "dm_message"
  }
}
```

DM body is truncated to 100 characters.

### member_joined

```json
{
  "notification": {
    "title": "New Member!",
    "body": "Alice joined Beach Trip Crew"
  },
  "data": {
    "clique_id": "uuid"
  }
}
```

### event_expiring

```json
{
  "notification": {
    "title": "Event Expiring Soon",
    "body": "\"Beach Day 2026\" expires in 24 hours. Save your photos!"
  },
  "data": {
    "event_id": "uuid"
  }
}
```

### event_deleted

```json
{
  "notification": {
    "title": "Event Deleted",
    "body": "\"Beach Day 2026\" was deleted by Alice"
  },
  "data": {
    "event_id": "uuid"
  }
}
```

---

## Event Expiring Deduplication

**File:** `backend/src/functions/timers.ts`, `notifyExpiring()`

The timer function runs hourly (minute 0) and checks for events expiring within a 23-25 hour window. To prevent sending duplicate notifications:

- Query window: `expires_at BETWEEN NOW() + INTERVAL '23 hours' AND NOW() + INTERVAL '25 hours'`
- Deduplication: Checks if an `event_expiring` notification was already sent for this event in the last 20 hours
- If already sent, skips the event

---

## Notification cleanup on target deletion

**File:** `backend/src/shared/db/notificationCleanup.ts`

The `notifications` table has only one FK (`user_id` → users). Target IDs (`event_id`, `photo_id`, `video_id`, `clique_id`) live inside JSONB `payload_json` with no FK and no cascade. Without explicit cleanup, every notification about a deleted event / photo / video / clique would survive forever in OTHER users' lists, and tapping one would 404 on the resource fetch.

**Two-tier strategy:**

1. **Synchronous helpers** at user-visible delete sites — fire immediately so members see the related notification disappear on next list refresh, not 15 min later.
2. **Periodic sweep** (`sweepStaleNotifications`) appended to the existing 15-min `cleanupExpired` timer in `timers.ts`. Catches whatever the synchronous wiring missed (account deletion bulk-photo delete in `auth.ts`, sole-owner-leaves clique delete in `cliques.ts`, races, future delete sites we forget to wire).

| Helper | Used by | Trigger |
|---|---|---|
| `deleteNotificationsForEvent(eventId)` | `events.ts:deleteEvent` | Organizer manual event delete |
| `deleteNotificationsForPhoto(photoId)` | `photos.ts:deletePhoto` | Uploader / organizer photo delete |
| `deleteNotificationsForVideo(videoId)` | `videos.ts:deleteVideo` | Uploader / organizer video delete |
| `deleteNotificationsForClique(cliqueId)` | (none yet — clique delete relies on the sweep) | — |
| `sweepStaleNotifications()` | `timers.ts:cleanupExpired` (every 15 min) | Periodic safety net |

The sweep removes notifications whose target is missing OR (for photos / videos) soft-deleted. `getPhoto` / `getVideo` filter on `status='active'`, so soft-deleted rows return 404 to the client and are treated as gone for notification purposes. Cliques and events are hard-deleted at all sites, so the sweep checks raw existence.

**Drift hazard:** every NEW delete site that removes an event / photo / video / clique must EITHER call one of the targeted helpers OR rely on the periodic sweep covering it within 15 minutes. Add a one-line comment at any new site.

**Telemetry:** each cleanup fires `stale_notifications_deleted` with `trigger ∈ {event_manual_delete, photo_deleted, video_deleted, periodic_sweep}` and a count. Failures fire `stale_notifications_cleanup_failed` (non-fatal — the parent operation still completes; the next sweep catches the orphan).

**Operator runbook:** to force-clean stale rows immediately after deploy without waiting up to 15 min for the first timer pass, run the four sweep DELETEs from `backend/src/shared/db/notificationCleanup.ts` (`sweepStaleNotifications`) directly via psql. Idempotent and safe to re-run. See `docs/BETA_OPERATIONS_RUNBOOK.md` §X.

---

## Code References

| File | Purpose |
|------|---------|
| `backend/src/shared/services/fcmService.ts` | FCM HTTP v1 API client, batch send, stale token cleanup |
| `backend/src/shared/services/webPubSubService.ts` | Web PubSub event publishing, token negotiation |
| `backend/src/functions/photos.ts` | `new_photo` push trigger |
| `backend/src/functions/videos.ts` | `video_ready` and `video_processing_failed` push triggers |
| `backend/src/functions/cliques.ts` | `member_joined` push trigger |
| `backend/src/functions/events.ts` | `event_deleted` push trigger |
| `backend/src/functions/dm.ts` | `dm_message` Web PubSub + FCM fallback |
| `backend/src/functions/timers.ts` | `event_expiring` timer-driven push |
| `backend/src/functions/notifications.ts` | In-app notification CRUD endpoints |
| `backend/src/shared/db/notificationCleanup.ts` | Synchronous + periodic stale-notification cleanup |
| `app/lib/core/utils/api_error_messages.dart` | Friendly Dio-error mapping for destination screens (covers 404 / 401 / network / 5xx) |
| `app/lib/services/push_notification_service.dart` | FCM token registration, tap routing |
| `app/lib/main.dart` | Notification channel setup, foreground message handler |
| `app/lib/features/notifications/presentation/notifications_screen.dart` | In-app notification list UI |

---

## Known Limitations (Beta)

- **No notification batching:** If 10 people react quickly, the recipient gets 10 separate pushes. Batching (coalescing within a 30-second window) is a Tier 5 improvement.
- **No notification preferences:** Users cannot selectively mute notification types (e.g., mute reactions but keep new photos). They can only disable the entire channel via OS settings.
- **DM preview in push payload:** The message body is sent in cleartext in the FCM payload (TLS in transit only). A privacy-focused improvement would replace the body with a generic "New message from {name}" in production.
- **Web PubSub token refresh:** Token TTL is 60 minutes. Client-side auto-refresh before expiry is not yet implemented — if the token expires, the client falls back to polling until the next app resume triggers re-negotiation.
