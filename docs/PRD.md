# Clique Pix – Product Requirements Document (PRD)

## 1. Overview

Clique Pix is a private, event-based photo sharing mobile application designed to allow small groups of people to instantly share photos during real-world moments.

The core value proposition:

> Take a photo → Share it instantly with your group → Everyone gets it immediately → Save what you want → Everything else disappears.

Clique Pix is NOT a social network. It is a **private, real-time group photo sharing experience**.

---

## 2. Goals (v1.0)

### Primary Goals
- Enable instant sharing of photos within a defined group (Clique/Event)
- Reduce friction compared to texting or AirDrop
- Provide a clean, beautiful, and fast experience
- Ensure privacy and control

### Secondary Goals
- Drive repeat usage through recurring groups (Cliques)
- Create a strong brand identity (modern, vibrant, non-corporate)

---

## 3. Target Audience

Primary:
- People aged 21–45
- Social groups (friends, brunch, girls night, trips, birthdays, bachelor party)

Secondary:
- Mixed groups (friends, couples, events)

**Minimum age: 13.** Verified at sign-up via a self-declared date of birth on the Entra External ID signup form. The DOB is stored on the Entra user principal (never in Clique Pix's product database) and emitted as a `dateOfBirth` claim on every access token. Clique Pix's backend reads the claim on first login (`POST /api/auth/verify`), computes age server-side, and either stamps `users.age_verified_at` on ≥13 or returns HTTP 403 + best-effort Microsoft Graph account deletion on <13. See `docs/ARCHITECTURE.md` §5, `docs/AGE_VERIFICATION_RUNBOOK.md`, and `website/privacy.html` §2.2 + §11.

---

## 4. Core Concepts

### 4.1 Event
A temporary shared photo session — the primary action in Clique Pix
- Example: “Friday Night – Downtown”
- Duration: 24 hours, 3 days, or 7 days (default)
- Created first, then assigned to a Clique

### 4.2 Clique
A persistent group of people (e.g., “Girls Night Out” or bachelor party)
- Reusable across multiple Events
- Created during Event creation or independently

---

## 5. Core Features (v1.0)

### 5.1 Authentication
- Sign in with Google, Apple, or email OTP
- Powered by Microsoft Entra External ID (CIAM)
- Minimal friction onboarding
- **Stay-signed-in experience.** Users who open the app on a normal cadence (daily, or even every few days) never see a login screen again after the initial sign-in. The app refreshes silently in the background using a combination of server-triggered wake-ups and on-resume checks.
- **Instant cold start.** Returning users with a valid cached session land directly on the Events screen — no splash, no "checking authentication" spinner. Session verification happens in the background and only surfaces a Welcome Back prompt if the cached session has actually expired.
- **Graceful "Welcome back" recovery.** If background refresh ever fails — for example, an iOS user who force-killed the app and didn't open it for a week — the next launch shows a *"Welcome back, [Name]!"* dialog with their email pre-recognized. One tap re-authenticates and returns them to the app. No cold login screen, no retyping an email address.
- **Implementation note (not user-facing):** a 5-layer defense backs this — see `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md`.

---

### 5.2 Event Creation & Management
- Events are the primary action — create Event first
- Fields:
  - Event name
  - Optional description
  - Duration (24h / 3 days / 7 days — three presets only, default 7 days)
  - Clique picker (select existing Clique or create new one inline)
- Create Event button
- Event organizer (creator) can manually delete an event at any time
  - Confirmation dialog warns that deletion is permanent
  - All photos are removed from cloud storage
  - Clique members are notified via push notification

---

### 5.3 Clique Management

- Create Clique
- Invite users via:
  - Link
  - SMS
  - QR code
- View members
- Leave Clique
- Originator of clique can "remove" members as well

------

### 5.4 In-App Camera & Photo Editor

- Capture photo directly in app or select from gallery
- Full editing suite via `pro_image_editor`:
  - Crop & rotate
  - Drawing / painting (freehand with color picker)
  - Text overlays
  - Emoji stickers
  - Photo filters (preset)
  - Brightness / contrast / saturation tuning
- Flow: Pick photo → Edit → Preview with prominent "Upload to Event" button → Upload with progress

---

### 5.5 Upload from Camera Roll
- Select existing photos
- Upload to Event

---

### 5.6 Real-Time Photo Sharing
- Photos compressed on-device before upload (resized to max 2048px, JPEG quality 80)
- Photos uploaded directly to cloud storage via short-lived, scoped authorization
- Instantly visible in Event feed (thumbnails for fast loading)
- Push notifications:
  - “Paula added a photo”

---

### 5.7 Event Feed
- Vertical scrolling feed
- Large image cards
- Display:
  - User
  - Timestamp
  - Photo

---

### 5.8 Reactions
- Lightweight emoji reactions:
  - ❤️ 😂 🔥 😮

---

### 5.9 Save & Download
- Save individual photo to device from photo detail screen
- Save individual video to device from video player menu (uses MP4 fallback URL)
- Multi-select download: enter selection mode in event feed, tap photos and/or videos to select, Select All / Deselect All, download selected media to device with progress indicator
- Dynamic download label: "Download 3 Photos" / "Download 2 Videos" / "Download 5 Items" depending on selection
- Processing or failed videos are excluded from selection (not yet downloadable)
- Batch download saves full-resolution photo originals (falls back to thumbnail if unavailable) and MP4 video fallbacks

---

### 5.10 Social Sharing
- Share externally via the **native OS share sheet** (iOS Share Sheet / Android Sharesheet)
- Users can share to any app installed on their device (Instagram, Messages, WhatsApp, etc.)
- No direct API integrations with third-party social platforms in v1

---

### 5.11 Auto-Delete (Core Differentiator)
- Default: 7 days
- Photos removed from cloud automatically
- Users notified before deletion
- Saved photos remain on device

---

### 5.12 Direct Messages (Event-Centric DMs)
- 1:1 text-only direct messaging within the context of a specific event
- Event-centric: a DM thread is tied to a single event; same two users get separate threads per event
- Ephemeral: threads become read-only when the event expires and are deleted with the event
- Real-time delivery via Azure Web PubSub (instant when both users are online)
- FCM push notifications for background/terminated app
- Accessible via "Messages" button on event detail screen
- Member picker to start new DMs with event clique members
- Rate limited: max 10 messages per minute per sender per thread
- Not a global messaging inbox — DMs exist only within events
- No attachments, no group chat, no typing indicators, no read receipts UI

---

### 5.13 Notifications
- Push notifications via FCM (Firebase Cloud Messaging)
- Notification types:
  - New photo added to event ("New Photo!")
  - Someone joins a clique ("New Member!")
  - Event expiring in 24 hours
  - Event expired
  - Event deleted by organizer
- Foreground: heads-up banner slides down from top of screen
- Background/terminated: standard system notification; tap navigates to relevant screen
- In-app notification list with read/unread state, type-specific icons
- No notifications sent for member removals or departures

---

### 5.14 Privacy & Controls
- Private by default
- No public feed
- **Privacy Policy** — accessible from the profile screen, opens `https://clique-pix.com/privacy.html` in an in-app browser. Covers photos, videos, DMs, data retention, security, and user rights. 14 sections.
- **Terms of Service** — accessible from the profile screen, opens `https://clique-pix.com/terms.html` in an in-app browser. 16 sections.
- Controls:
  - Leave event
  - Remove own photos and videos
  - Mute notifications
  - **Delete account** — permanently removes user account, photos, videos, DM history, and clique memberships. Shared cliques/events are preserved for other members (creator set to null). Required by Apple App Store Review Guideline 5.1.1(v).

---

## 6. Non-Goals (v1.0)

- No public social feed
- No followers/following
- No advanced editing suite
- No printed albums (future)
- ~~No video-first features~~ (video promoted to v1 — capture, upload, transcode, HLS playback, save/share)

---

## 7. UX Principles

- Fast (capture → share → view must feel instant)
- Private (no public exposure)
- Clean (minimal clutter)
- Emotional (feels like shared memories, not storage)

---

## 8. Branding & Design

### 8.1 Brand Personality
- Vibrant
- Modern
- Social
- Premium but approachable
- Not overly feminine

---

### 8.2 Color Palette (Final)

#### Primary Colors
- Electric Aqua: #00C2D1
- Deep Blue: #2563EB
- Violet Accent: #7C3AED
- Pink Accent: #EC4899

#### Surface Colors
- Dark Background: #0E1525 (primary app background)
- Dark Surface: #111827 (bottom nav, cards)
- Dark Card: #1A1F35 (avatar backgrounds, elevated surfaces)
- Soft Aqua Background: #E6FBFF (light accents where needed)
- White Surface: #FFFFFF (content surfaces)

#### Text Colors
- Primary Text (on dark): #FFFFFF at 90% opacity
- Secondary Text (on dark): #FFFFFF at 50% opacity
- Primary Text (on light): #0F172A
- Secondary Text (on light): #64748B

#### Semantic Colors
- Error: #DC2626
- Success: #16A34A
- Warning: #F59E0B

#### Design Note
The app uses a dark theme throughout, consistent from the login screen through all main screens (Cliques, Notifications, Profile). Gradient accents from the primary colors provide vibrant contrast against the dark surfaces.

---

### 8.3 Gradient

Primary Gradient:
- #00C2D1 → #2563EB → #7C3AED

Used for:
- App icon
- Splash screen
- CTA highlights
- Event headers

---

### 8.4 Icon Design

Concept:
- Rounded square background with aqua → blue gradient
- Centered white camera body with subtle depth/shadow
- Prominent glass lens with aqua-to-deep-blue gradient and specular highlight
- Pink/magenta accent dot (top-right of camera body)
- Viewfinder bump on top of camera

Design Rules:
- Simple and recognizable at small sizes
- Lens is the focal point — draws the eye immediately
- Pink accent dot adds personality and aids recognition at icon scale
- Generated via `flutter_launcher_icons` from a single 1024x1024 source

---

## 9. Technical Architecture (High Level)

### 9.1 Frontend

**Flutter** — single codebase for iOS and Android.

Why Flutter for Clique Pix:
- Strong UI consistency across iOS & Android
- Excellent for custom design systems
- Better control over animations and gradients
- Best fit for a visual-first consumer app where design is the product

---

### 9.2 Backend

- Entry Point: Azure Front Door
- API Gateway: Azure API Management
- API Layer: Azure Functions (TypeScript)
- Storage: Azure Blob Storage (images, accessed via managed identity + User Delegation SAS)
- Database: PostgreSQL Flexible Server
- Auth: Microsoft Entra External ID
- Secrets: Azure Key Vault
- Observability: Application Insights
- Notifications: FCM (Firebase Cloud Messaging) for push delivery to both platforms

---

## 10. Key User Flow

1. User opens app → lands on Events tab (home)
2. Creates Event (name, duration, pick or create Clique)
3. Takes or uploads photo
4. Shares to Event
5. Group receives notification
6. Members view/save/react
7. Photos auto-delete after duration

---

## 11. Risks

- Group adoption friction
- Competition from native sharing (iMessage, AirDrop)
- Need for extremely fast performance

---

## 12. Success Metrics

- Daily active users per event
- Photos shared per event
- % of users saving photos
- Event creation rate
- Retention (return to create another event)

---

## 13. Future Roadmap (Post v1)

- Printed albums
- AI highlights / recap
- ~~Multi-photo download~~ (implemented in v1)
- Video support
- Premium subscription tier

---

## 15. Web Client

A browser-based client hosted at `clique-pix.com`. Feature-parity with the mobile app for everything except native camera capture; uses the same backend API (Azure Functions behind APIM) and same Entra External ID tenant.

**In scope for v1:**
- Sign in via MSAL.js (same Entra tenant, 13+ age gate enforced server-side)
- Create and join Cliques; view members; **print QR invite codes** from the browser
- Create and manage Events (same 24h / 3 days / 7 days presets)
- Upload photos from a file picker or drag-drop, with client-side compression + EXIF strip + HEIC→JPEG conversion
- View event feed, open lightbox, react, download individual and batch photos
- View videos uploaded from mobile (poster + HLS playback — browser-side video *upload* ships in a follow-up)
- Event-centric DMs with real-time delivery via Azure Web PubSub
- In-app notifications list (polling + real-time signals while the tab is open)
- Profile: sign out, delete account, links to Privacy/Terms

**Not in v1 (web):**
- Browser push notifications (Web Push / VAPID) — users who want background alerts use the mobile app
- Video upload from the browser (planned follow-up; upload-url/commit endpoints already present on the backend)
- In-browser photo editor (pro_image_editor is Flutter-only)
- PWA / installable

Privacy Policy and Terms now live at `clique-pix.com/docs/privacy` and `clique-pix.com/docs/terms`. Legacy `/privacy.html` and `/terms.html` 301-redirect.

Full technical detail: `docs/WEB_CLIENT_ARCHITECTURE.md`.

---

## 14. Summary

Clique Pix v1.0 focuses on one core experience:

> Instant, private group photo sharing for real-life moments.

Everything in this version supports that loop and avoids unnecessary complexity.

---

## Companion Documents

| Document | Purpose |
|----------|---------|
| `ARCHITECTURE.md` | Full technical architecture, data model, security, deployment |
| `CLAUDE.md` | Development guardrails and locked decisions for Claude Code |
| `ENTRA_REFRESH_TOKEN_WORKAROUND.md` | Authentication token refresh implementation details |
| `WEB_CLIENT_ARCHITECTURE.md` | Web client architecture, deployment, CORS/CSP config |

