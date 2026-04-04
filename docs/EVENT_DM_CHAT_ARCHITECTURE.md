# EVENT_DM_CHAT_ARCHITECTURE.md

## Purpose

This document defines the **approved architecture and implementation direction** for adding **event-centric, ephemeral direct messaging (DM)** to Clique Pix.

This file is intended to be handed directly to Claude Code.

It is intentionally specific.
Claude Code should **implement against this document**, not invent a different messaging system.

---

## Why This Document Exists

Clique Pix was originally scoped as a private, event-based photo sharing app. Direct messaging was explicitly out of scope for v1 in the current docs.

That has changed.

The founders have agreed to **explore event-centric DMs for v1**.

This feature materially changes the app architecture, data model, notification model, and product boundaries, so it needs a dedicated design brief instead of scattered instructions.

---

## Product Decision — Locked

### DM model

Direct messaging in Clique Pix is now defined as:

- **1:1 only** in this phase
- **event-centric**
- **ephemeral**
- **text-only**
- **no photo attachments**
- **no global inbox independent of events**
- **no group chat**
- **no user search/discovery for chat**

### Meaning of event-centric

A DM thread exists **inside the context of a specific event**.

That means:

- A thread is tied to a single `event_id`
- Only users who are valid members of that event's circle can participate
- The same two users may have a **different thread per event**
- A thread does **not** become a permanent global DM relationship between two users

### Meaning of ephemeral

DMs follow the event lifecycle.

Approved behavior:

- While the event is active, both participants can send and receive messages
- When the event expires, the thread becomes **read-only immediately**
- After a **24-hour grace period**, the thread and all its messages are **hard deleted**
- No indefinite message retention

This keeps DMs aligned with Clique Pix's event-first and ephemeral product identity.

---

## Important Product Boundary

This feature must **not** turn Clique Pix into a general messaging app.

Do **not** implement any of the following in this phase:

- global cross-event chat
- persistent messaging relationships outside an event
- chat attachments
- voice notes
- typing indicators
- online presence
- delivered/read receipts beyond simple unread state
- message editing
- message reactions
- message forwarding
- message search
- group chat rooms
- moderation systems beyond basic abuse blocking hooks if absolutely needed later

If something is not explicitly described in this file, leave it out.

---

## Architecture Decision — Locked

## Best option for real chat feel

For event-centric text DMs that should feel like actual chat, the approved architecture is:

- **Azure Web PubSub** for real-time message delivery to connected clients
- **Azure Functions** for authenticated API and message write path
- **PostgreSQL Flexible Server** as the source of truth for threads, messages, and unread state
- **FCM** for background / terminated app notifications
- **Azure Service Bus is NOT part of the first implementation**

### Why Web PubSub

Polling is not good enough if the product requirement is that chat should feel live.

Web PubSub is the right service for:

- low-latency message delivery
- socket-based active-thread updates
- future optional support for typing/presence if ever needed

### Why not Service Bus first

Service Bus is for **durable asynchronous workflows**, retries, dead-lettering, and decoupled side effects.

It is **not** the primary transport for a live chat experience.

Do not introduce Service Bus unless the message send path later becomes overloaded with side effects.

---

## High-Level Message Flow

### Foreground / active chat thread

1. User opens an event DM thread
2. Flutter requests a Web PubSub client token from the backend
3. Flutter connects to Azure Web PubSub via WebSocket
4. User sends a message through the normal authenticated API path
5. Azure Function validates auth and event membership
6. Azure Function writes the message to PostgreSQL
7. Azure Function publishes the message to Web PubSub
8. Connected recipient receives the message instantly
9. Sender UI is updated immediately from the API response and/or socket echo event

### Background / terminated app

1. Sender posts a message
2. Azure Function writes the message to PostgreSQL
3. Azure Function publishes to Web PubSub
4. If recipient is offline or not actively in-thread, backend sends FCM push notification
5. Recipient taps notification and is routed into the correct event DM thread

### Source of truth

**PostgreSQL is the source of truth.**

Web PubSub is delivery infrastructure, not the authoritative message store.

---

## Azure Services — Final Decision

## Required new Azure service

Add:

- **Azure Web PubSub**

## Existing services that remain in place

Continue using:

- Azure Front Door
- Azure API Management
- Azure Functions (TypeScript)
- PostgreSQL Flexible Server
- Application Insights
- FCM via existing Firebase setup
- Key Vault

## Not introduced in this phase

Do not add yet:

- Azure Service Bus
- Azure SignalR Service
- Redis
- Notification Hubs

---

## Approved Request / Delivery Topology

### API path

All client-originated message writes must still go through the current published API surface:

```text
Flutter App → Front Door → APIM → Azure Functions → PostgreSQL
```

Do **not** bypass APIM.
Do **not** let the client write chat messages directly to Web PubSub as a source of truth.

### Real-time fanout path

```text
Azure Functions → Azure Web PubSub → Connected clients
```

### Offline notification path

```text
Azure Functions → FCM → Mobile device
```

---

## Data Model — Locked Initial Shape

Use a dedicated event-DM model. Do **not** overload existing notification or event tables.

## Table: `event_dm_threads`

Purpose: one thread per event for one user pair.

Columns:

- `id` UUID PK
- `event_id` UUID FK → `events.id`
- `user_a_id` UUID FK → `users.id`
- `user_b_id` UUID FK → `users.id`
- `created_at` TIMESTAMPTZ NOT NULL
- `last_message_at` TIMESTAMPTZ NOT NULL
- `status` VARCHAR NOT NULL
  - allowed values: `active`, `read_only`, `expired`, `deleted`
- `expires_at` TIMESTAMPTZ NOT NULL
- `read_only_at` TIMESTAMPTZ NULL
- `deleted_at` TIMESTAMPTZ NULL

### Constraints

- normalized uniqueness so the same two users only get **one thread per event**
- implement by ordering IDs in application logic before insert, or use generated min/max columns if desired
- unique constraint on `(event_id, normalized_user_low, normalized_user_high)` behavior

### Status rules

- `active` = event active, sends allowed
- `read_only` = event expired, thread visible but no new messages allowed
- `expired` = grace window elapsed, pending cleanup or hidden from client
- `deleted` = hard-delete lifecycle marker if using a two-step cleanup approach

## Table: `event_dm_participants`

Purpose: per-user state within a thread.

Columns:

- `thread_id` UUID FK → `event_dm_threads.id`
- `user_id` UUID FK → `users.id`
- `last_read_message_id` UUID NULL
- `last_read_at` TIMESTAMPTZ NULL
- `is_muted` BOOLEAN NOT NULL DEFAULT false
- `created_at` TIMESTAMPTZ NOT NULL
- `updated_at` TIMESTAMPTZ NOT NULL

### Constraints

- composite PK or unique constraint on `(thread_id, user_id)`

## Table: `event_dm_messages`

Purpose: stores actual text messages.

Columns:

- `id` UUID PK
- `thread_id` UUID FK → `event_dm_threads.id`
- `sender_user_id` UUID FK → `users.id`
- `body` TEXT NOT NULL
- `created_at` TIMESTAMPTZ NOT NULL
- `deleted_at` TIMESTAMPTZ NULL

### Message rules

- text-only
- max length should be enforced, e.g. 2000 chars
- empty or whitespace-only message must be rejected
- no edit support in this phase
- no soft-delete UX in this phase

## Recommended indexes

- `event_dm_threads(event_id)`
- `event_dm_threads(last_message_at desc)`
- `event_dm_messages(thread_id, created_at desc)`
- `event_dm_participants(user_id)`

---

## Authorization Rules — Locked

Every DM API and realtime token issuance path must enforce all of the following:

1. user is authenticated
2. user belongs to the thread they are accessing
3. both participants are valid members of the event's circle while thread is active
4. no new messages can be sent after thread becomes read-only

### Event membership rule

A thread may be created only if:

- both users are members of the circle that owns the event
- the event is active

### Sender validation rule

A message send must fail if:

- event is expired
- thread is read-only / expired / deleted
- sender is not one of the two participants
- sender is no longer a valid member of the event's circle

### Recipient validation rule

A thread may be listed or read only for a participant in that thread.

Do not expose thread existence to non-participants.

---

## Expiration / Retention Rules — Locked

DMs are ephemeral and follow the event model.

## Lifecycle

### While event is active

- thread status = `active`
- send allowed
- receive allowed
- unread tracking active
- realtime delivery active

### At event expiration

Immediately:

- set thread status = `read_only`
- set `read_only_at = now()`
- block new sends
- keep thread readable for 24 hours
- optional push notification is **not required** for thread read-only transition in this phase

### 24 hours after event expiration

- hard delete all messages in the thread
- hard delete participant rows
- hard delete thread row, or mark deleted then purge depending on implementation preference
- remove thread from all client lists

### Cleanup implementation

Use timer-triggered Azure Functions, similar in spirit to existing expiration cleanup.

Recommended timers:

- `expireEventDmThreads` — moves eligible threads from `active` to `read_only`
- `purgeExpiredEventDmThreads` — hard deletes messages + threads after grace window

---

## API Surface — Approved Initial Endpoints

Add the following endpoints.

## Thread creation / discovery

```text
POST   /api/events/{eventId}/dm-threads
GET    /api/events/{eventId}/dm-threads
GET    /api/dm-threads/{threadId}
```

### `POST /api/events/{eventId}/dm-threads`

Purpose:
- open or fetch the 1:1 thread between current user and target user for this event

Request body:

```json
{
  "target_user_id": "uuid"
}
```

Behavior:
- validate current user and target user are both circle members for the event
- if thread already exists for this event + pair, return it
- else create thread + 2 participant rows

## Message APIs

```text
GET    /api/dm-threads/{threadId}/messages
POST   /api/dm-threads/{threadId}/messages
PATCH  /api/dm-threads/{threadId}/read
```

### `GET /api/dm-threads/{threadId}/messages`

Behavior:
- paginated
- newest or oldest ordering is implementation choice, but UI should behave like normal chat
- recommended API shape: fetch newest page, then allow older-history paging

### `POST /api/dm-threads/{threadId}/messages`

Request body:

```json
{
  "body": "text message"
}
```

Behavior:
- validate membership
- validate thread status = active
- validate body length / not blank
- insert message
- update thread `last_message_at`
- publish realtime event to Web PubSub
- optionally create in-app notification record if you want DM notifications visible in the Notifications screen
- send FCM if recipient is not actively connected/in thread, or simply always send FCM in first phase for simplicity

### `PATCH /api/dm-threads/{threadId}/read`

Request body:

```json
{
  "last_read_message_id": "uuid"
}
```

Behavior:
- update participant row
- unread count becomes computable
- no need for fine-grained read receipts in UI

## Realtime negotiation

```text
POST   /api/realtime/dm/negotiate
```

Purpose:
- returns Web PubSub connection info for authenticated user

Behavior:
- validate user auth
- issue short-lived Web PubSub token
- user should connect using a user-specific identity and be authorized only for allowed event/thread channels

---

## Web PubSub Design — Locked Direction

## Delivery model

Use **user-targeted delivery** via `sendToUser(recipientUserId, payload)`.

This is simpler and more reliable than thread-scoped groups for 1:1 DMs:
- No group membership management needed (no `addUser`/`removeUser` lifecycle)
- Survives WebSocket reconnection without re-joining groups
- One fewer server-side call per chat session

When a user opens a thread:

- client obtains negotiation token (includes userId claim)
- client connects to Web PubSub via WebSocket (simple protocol, no subprotocol)
- backend sends messages directly to the recipient's userId — no group subscription needed

> **Previous approach (deprecated):** Thread-scoped groups (`dm-thread-{threadId}`) with `addUser`/`sendToAll`. This was fragile — if `addUserToThreadGroup` failed silently, the user never received messages. Switched to `sendToUser` in April 2026.

## Server event publishing

When a message is created, the backend publishes directly to the recipient user via `sendToUser(recipientId, payload)`.

Payload includes enough to render the message immediately:

```json
{
  "type": "dm_message_created",
  "thread_id": "uuid",
  "event_id": "uuid",
  "message": {
    "id": "uuid",
    "thread_id": "uuid",
    "sender_user_id": "uuid",
    "sender_name": "Display Name",
    "body": "hello",
    "created_at": "2026-04-03T12:34:56Z"
  }
}
```

## Connection model

Keep it simple:

- one WebSocket connection per user (singleton `DmRealtimeService`)
- client filters incoming messages by `thread_id` to display in the active chat
- on reconnect, the service re-negotiates a fresh URL (client access tokens expire after 1 hour)
- do not implement presence yet
- do not implement typing events yet

---

## Notification Model

## Realtime vs push

Use both, for different app states.

### Web PubSub
Use for:
- active connected users
- instant chat feel
- open thread updates

### FCM
Use for:
- background app
- terminated app
- user tap routing into the right DM thread

## New notification type

If keeping DM notifications inside the existing Notifications screen, add:

- `dm_message`

Suggested payload:

```json
{
  "thread_id": "uuid",
  "event_id": "uuid",
  "sender_user_id": "uuid",
  "sender_name": "Paula",
  "preview": "On our way now"
}
```

If you decide not to store DM notifications in the in-app notifications table for this phase, that is acceptable, but FCM push still needs to work.

## Tap routing

Notification tap should navigate to:

```text
/events/{eventId}/dm/{threadId}
```

or equivalent route structure chosen by the app.

---

## Flutter Client Architecture Changes

Add a new feature area:

```text
/lib/features/dm
  /data
  /domain
  /presentation
```

## Expected client pieces

### Data layer
- DM API client
- repositories for threads/messages
- Web PubSub realtime service

### Domain models
- `DmThreadModel`
- `DmMessageModel`
- `DmParticipantStateModel`

### Presentation
- event DM thread list screen
- DM thread screen
- message composer
- unread badge handling

## Navigation entry points

The event-centric nature means DM entry points should live inside the event experience.

Approved entry points:

- from event member list / participant UI
- from event detail screen where members are shown
- from an event-level “Messages” or “Chats” section if desired

Not approved:

- a global standalone DM tab on the main bottom nav in this phase

## Client behavior expectations

### Open thread
- fetch thread metadata and latest messages
- connect to realtime service
- join authorized thread channel
- append incoming messages live

### Send message
- optimistic UI is allowed, but server acknowledgment must reconcile the final message record
- handle failures cleanly

### Leaving thread screen
- disconnect or unsubscribe from thread realtime updates if appropriate
- do not keep complicated background socket behavior in this phase

---

## UX Rules — Keep It Tight

This is not a full messenger product.

## Minimum viable UX

- open a DM from an event participant
- see the 1:1 thread for that event only
- send text messages
- receive messages live while thread is open
- receive push when app is backgrounded
- see unread state
- thread becomes read-only when event expires
- thread disappears after grace window purge

## Read-only state UX

When event expires:

- show a clear banner: `This chat is now read-only because the event ended.`
- disable composer input
- do not allow send retries to sneak through

## Empty states

- no messages yet
- event ended / thread read-only
- other participant unavailable (only if edge case is surfaced)

---

## What Claude Code Must NOT Build

Do not build any of this unless explicitly requested later:

- global chat inbox independent of event context
- chat attachments
- typing indicators
- presence / online status
- read receipts UI like “Seen”
- message edit/delete UX
- emoji reactions on messages
- blocking/reporting UI
- Service Bus integration
- Redis caching
- SignalR instead of Web PubSub
- direct client-to-database or client-to-WebPubSub source-of-truth message writes

---

## When Service Bus Gets Introduced

Service Bus is deferred.

Introduce it **only** when the send-message path becomes too heavy with asynchronous side effects.

Examples of triggers for introducing Service Bus later:

- message send performs too many non-critical side effects inline
- FCM notification delivery should be retried independently of API success
- in-app notification creation should be decoupled
- analytics / moderation / auditing consumers multiply
- send latency becomes unacceptable because of too much inline work

### At that point, a possible split is:

Synchronous path:
- validate
- persist message
- publish realtime event
- return success

Asynchronous side effects via Service Bus:
- send push notification
- create in-app notification
- analytics event processing
- moderation hooks
- audit/event archival hooks

But that is **not phase 1**.

---

## Security / Abuse / Privacy Notes

Even in a narrow DM feature, do not be sloppy.

## Required safeguards now

- strict participant authorization on every endpoint
- no thread enumeration for unauthorized users
- no message send after expiration/read-only transition
- no logging of message bodies in debug or production logs
- no exposure of other users outside event membership context

## Not required in first implementation

- full abuse reporting system
- keyword moderation
- content scanning

But the code should not make those impossible later.

---

## Telemetry / Observability

Add Application Insights events for at least:

- `dm_thread_created`
- `dm_thread_opened`
- `dm_message_sent`
- `dm_message_send_failed`
- `dm_message_received_realtime`
- `dm_push_sent`
- `dm_thread_marked_read_only`
- `dm_thread_purged`

Do not log message bodies.
Do log correlation IDs, thread IDs, event IDs, and sender/recipient IDs where appropriate.

---

## Suggested Delivery Order for Claude Code

Implement in this order.

### Phase 1 — Schema and backend foundation
1. add PostgreSQL migrations for DM tables
2. add backend models/types
3. add repository/service layer for DM threads and messages
4. add authz helpers for event-based DM validation

### Phase 2 — Basic REST thread/message flow
5. implement create/fetch thread API
6. implement list messages API
7. implement send message API
8. implement mark-read API
9. add unit tests around authz and expiry behavior

### Phase 3 — Realtime
10. provision/configure Azure Web PubSub integration points
11. add negotiate endpoint
12. publish new message events to recipient via `sendToUser` (originally used thread groups, switched to user-targeted delivery)
13. add Flutter realtime service with auto-reconnect and fresh URL negotiation

### Phase 4 — Notifications
14. send FCM for DM messages
15. add DM notification tap routing
16. optionally add `dm_message` notification type to in-app notification list

### Phase 5 — Expiration behavior
17. add timer-triggered functions for thread read-only transition and purge
18. add client read-only UX banner and disabled composer
19. test expiry edge cases carefully

### Phase 6 — Polish
20. unread badges
21. loading and empty states
22. connection-loss handling
23. instrumentation and telemetry review

---

## Acceptance Criteria

This feature is complete when all of the following are true:

1. A user can open a 1:1 DM with another valid participant **within a specific event**
2. A second DM with the same person in a different event is a separate thread
3. Users can send and receive text messages only
4. Messages arrive live while both users are connected and viewing the thread
5. Messages are persisted in PostgreSQL and survive app restarts while the event is active
6. Users receive FCM push when not actively in the thread
7. Unauthorized users cannot access the thread or messages
8. When the event expires, the thread becomes read-only immediately
9. After the 24-hour grace period, the thread and messages are deleted
10. The implementation does not introduce global chat behavior or messaging-app sprawl

---

## Required Documentation Follow-Up

After implementation direction is accepted, update these existing docs to remove contradictions:

- `docs/PRD.md`
- `docs/ARCHITECTURE.md`
- `.claude/CLAUDE.md`
- `docs/DEPLOYMENT_STATUS.md`

The current docs explicitly position Clique Pix as non-messaging and defer Web PubSub/Service Bus. Those statements will become stale once this DM feature is accepted.

---

## Final Instruction to Claude Code

Implement **event-centric, ephemeral, text-only 1:1 DMs** using:

- PostgreSQL as source of truth
- Azure Functions for authenticated write/read APIs
- Azure Web PubSub for realtime message delivery
- FCM for background notifications

Do not generalize this into a permanent messaging system.
Do not add attachments.
Do not add group chat.
Do not add Service Bus in the first pass.

Build only what is described here.
