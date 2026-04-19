# CLAUDE.md – Development Guardrails for Clique Pix

## Purpose

This document defines strict guardrails and expectations for Claude Code while developing the Clique Pix mobile application.

The goal is to:
- prevent scope creep
- maintain architectural clarity
- enforce product intent
- ensure high-quality, production-ready output

Claude must treat this document as authoritative guidance.

---

# 1. Core Product Definition

Clique Pix is:
- a **private, event-based photo sharing app**
- designed for **real-time group photo sharing**

Clique Pix is NOT:
- a social network
- a messaging app
- a content discovery platform

## Core Loop (Do Not Break)

1. User joins/creates Circle
2. User starts Event
3. User takes or uploads photo
4. Photo appears in Event feed
5. Other users view/save/react
6. Photos expire automatically

All development decisions must support this loop.

---

# 2. Scope Enforcement

## MUST BUILD (v1)
- Authentication (simple, low friction)
- Circles (create, join, list)
- Events (create, list, expire)
- Camera capture
- Upload from camera roll
- Event feed (photo-first)
- Reactions (lightweight)
- Save/download
- External share
- Auto-deletion logic
- Push notifications

## DO NOT BUILD (v1)
- Chat systems
- Comments/threads
- Followers/following
- Public feeds
- Advanced editing tools
- Video-first features
- AI features
- Monetization systems
- Printed albums

If unsure: **leave it out**.

---

# 3. Design & UX Rules

## Design Principles
- Clean, modern, and minimal
- Fast and responsive
- Photo-first UI
- Emotionally engaging (not utilitarian)

## Branding Rules
- Use defined aqua-based palette
- Use gradient: aqua → blue → violet
- Avoid generic corporate styling
- Avoid overly feminine or overly dark themes

## UI Priorities
1. Event feed must look beautiful
2. Photo viewing must feel premium
3. Camera flow must be fast

## Avoid
- cluttered layouts
- dense text
- small tap targets

---

# 4. Architecture Rules

## Frontend
- Use Flutter
- Maintain clean folder structure
- Separate UI, state, and services

## Backend
- Keep APIs simple and REST-based initially
- Avoid premature microservices complexity

## Data Flow
- Clear separation between:
  - UI
  - business logic
  - API layer

## Code Quality
- Modular
- Readable
- Well-named variables and functions
- No unnecessary abstraction

---

# 5. Performance Expectations

- Photo uploads must feel fast
- Feed must load quickly
- Avoid blocking UI threads
- Use async patterns properly

## Image Handling
- Support thumbnail + full-size pattern
- Avoid loading full images unnecessarily

---

# 6. Simplicity Rules

When making decisions:

### Prefer
- simpler solution
- fewer dependencies
- faster implementation

### Avoid
- overengineering
- adding "future-proof" complexity too early
- introducing patterns not needed for v1

---

# 7. Decision Framework

When uncertain, prioritize in this order:

1. Simplicity
2. Speed to working product
3. User experience
4. Scalability (only if needed now)

---

# 8. Feature Discipline

Before implementing any feature, ask:

- Is this in the PRD?
- Does this improve the core loop?
- Is this required for v1?

If the answer is NO → do not implement.

---

# 9. Communication Style

Claude should:
- explain architectural decisions briefly
- not over-explain basics
- not introduce unnecessary alternatives

When generating code:
- include only relevant comments
- avoid verbose explanations

---

# 10. File & Project Structure

Claude must create and maintain:

- clear directory structure
- consistent naming conventions
- separation of concerns

Example (Flutter):
- /features
- /core
- /services
- /models
- /ui

---

# 11. Iteration Strategy

Claude must:

1. Scaffold first
2. Build core flows end-to-end
3. Then refine UI and performance

Do NOT:
- perfect one screen while others don’t exist
- build deep features before core flows work

---

# 12. What Success Looks Like (v1)

A successful v1 allows:
- user can create/join Circle
- user can start Event
- user can take/upload photo
- group sees photo quickly
- user can save photo
- photo expires automatically

If this works cleanly → v1 is successful.

---

# 13. Final Instruction

Claude:

You are building a focused, high-quality consumer mobile app.

Do not drift.
Do not overbuild.
Do not turn this into a social platform.

Build a clean, fast, beautiful product centered around:

> private, real-time group photo sharing.

Everything else is secondary.

