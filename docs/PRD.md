# Clique Pix – Product Requirements Document (PRD)

## 1. Overview

Clique Pix is a private, event-based photo sharing mobile application designed to allow small groups of people to instantly share photos during real-world moments.

The core value proposition:

> Take a photo → Share it instantly with your group → Everyone gets it immediately → Save what you want → Everything else disappears.

Clique Pix is NOT a social network. It is a **private, real-time group photo sharing experience**.

---

## 2. Goals (v1.0)

### Primary Goals
- Enable instant sharing of photos within a defined group (Circle/Event)
- Reduce friction compared to texting or AirDrop
- Provide a clean, beautiful, and fast experience
- Ensure privacy and control

### Secondary Goals
- Drive repeat usage through recurring groups (Circles)
- Create a strong brand identity (modern, vibrant, non-corporate)

---

## 3. Target Audience

Primary:
- Women aged 21–45
- Social groups (friends, brunch, girls night, trips, birthdays)

Secondary:
- Mixed groups (friends, couples, events)

---

## 4. Core Concepts

### 4.1 Circle
A persistent group of people (e.g., “Girls Night Out”)

### 4.2 Event
A temporary shared photo session within a Circle
- Example: “Friday Night – Downtown”
- Duration: 24 hours, 3 days, or 7 days (default)

---

## 5. Core Features (v1.0)

### 5.1 Authentication
- Phone number or email-based signup
- Magic link or OTP
- Minimal friction onboarding

---

### 5.2 Circle Management
- Create Circle
- Invite users via:
  - Link
  - SMS
  - QR code
- View members
- Leave Circle

---

### 5.3 Event Creation
- Create Event inside Circle
- Fields:
  - Event name
  - Optional description
  - Duration (24h / 3 days / 7 days — three presets only, default 7 days)
- Start Event button

---

### 5.4 In-App Camera
- Capture photo directly in app
- Basic editing tools:
  - Crop
  - Brightness
  - Contrast
  - Simple filters

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
- Save individual photo to device
- Multi-select save (future enhancement)

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

### 5.12 Notifications
- New photo alerts
- Event reminders
- Expiration reminders

---

### 5.13 Privacy & Controls
- Private by default
- No public feed
- Controls:
  - Leave event
  - Remove own photos
  - Mute notifications

---

## 6. Non-Goals (v1.0)

- No public social feed
- No followers/following
- No advanced editing suite
- No printed albums (future)
- No video-first features

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

#### Secondary Colors
- Soft Aqua Background: #E6FBFF
- White Surface: #FFFFFF

#### Text Colors
- Primary Text: #0F172A
- Secondary Text: #64748B

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
- Rounded square background
- Aqua → blue → violet gradient
- Centered white camera icon
- Bold, slightly thickened camera outline
- Prominent lens with subtle glow

Design Rules:
- Simple
- Recognizable at small sizes
- Pink/magenta accent dot adds personality and aids recognition at small sizes
- Lens is focal point

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

1. User opens app
2. Creates or joins Circle
3. Starts Event
4. Takes or uploads photo
5. Shares to Event
6. Group receives notification
7. Members view/save/react
8. Photos auto-delete after duration

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
- Multi-photo download
- Video support
- Premium subscription tier

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

