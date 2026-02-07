---
title: "Email Composer — Specification"
version: "1.0.0"
status: draft
created: 2025-02-07
updated: 2025-02-07
authors:
  - Core Team
reviewers: []
tags: [composer, send, undo-send, drafts, autocomplete]
depends-on:
  - docs/constitution.md
  - docs/features/foundation/spec.md
  - docs/features/email-sync/spec.md
---

# Specification: Email Composer

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in RFC 2119.

## 1. Summary

This specification defines the email composition experience: composing new emails, replies, reply-all, and forwards. It covers the undo-send mechanism with all edge cases, draft auto-save, contacts autocomplete privacy, and smart reply integration.

---

## 2. Goals and Non-Goals

### Goals

- Support all composition modes (new, reply, reply-all, forward)
- Client-side undo-send with configurable delay
- Auto-save drafts locally and sync to server
- Privacy-preserving contacts autocomplete (local data only)

### Non-Goals

- Rich text / HTML email composition (V1: plain text + basic formatting)
- Template or canned response library
- Schedule send

---

## 3. Functional Requirements

### FR-COMP-01: Composition

- The client **MUST** support composing new emails, replies, reply-all, and forwards.
- The client **MUST** provide To, CC, and BCC fields with contact auto-complete from previously seen addresses.
- The client **MUST** provide a subject field (pre-filled for replies/forwards with Re:/Fwd: prefix).
- The client **MUST** provide a body editor with basic formatting (bold, italic, links).
- The client **MUST** support attaching files via the system file picker.
- The client **MUST** support attaching images from the photo library or camera.
- The client **MUST** auto-save drafts locally at regular intervals (every 30 seconds).
- The client **MUST** sync drafts to the server's drafts folder.
- The client **SHOULD** support inline image insertion.

### FR-COMP-02: Undo-Send Mechanism

Undo-send is a purely client-side delay. The email **MUST NOT** be transmitted to the SMTP server during the undo window.

- The undo window is configurable: 0 (disabled), 5, 10, 15, or 30 seconds. Default: 5 seconds.
- When the user taps Send:
  1. The message transitions to `pendingSend` state in the local outbox.
  2. A countdown toast/snackbar appears with an "Undo" button.
  3. No SMTP transmission occurs during this window.

**Undo-Send Edge Cases**

| Scenario | Behavior |
|----------|----------|
| User taps Undo | Send cancelled. Message returns to composer for editing. |
| Timer expires (app foregrounded) | SMTP send proceeds immediately. Message moves to Sent on success. |
| App enters background during undo window | Timer **pauses**. Resumes when app returns to foreground. |
| App terminated by OS during undo window | Message **MUST** be persisted as a draft (saved locally + synced to Drafts folder). It is **NOT** sent automatically on next launch. User must explicitly re-send. |
| App killed by user during undo window | Same as OS termination: saved as draft, not auto-sent. |
| Device loses network during undo window | Timer continues normally. On expiry, message enters the offline send queue (see Proposal 3.5). |
| Undo window set to 0 (disabled) | SMTP send proceeds immediately on tap with no undo option. |

**Persistence guarantee**: The message **MUST** be written to local storage (SwiftData) as `pendingSend` **before** the undo countdown begins. This ensures no data loss if the app is terminated at any point.

### FR-COMP-03: Smart Reply Integration

- When composing a reply, the client **SHOULD** pre-populate up to 3 smart reply suggestions.
- The user **MUST** be able to select a suggestion to insert it into the body, then edit freely.
- Smart reply generation **MUST** happen asynchronously and **MUST NOT** block the composer UI.
- Smart reply generation is handled by the AI Features spec.

### FR-COMP-04: Contacts Autocomplete Privacy

The recipient autocomplete feature **MUST** operate entirely from locally synced data, with no external contact lookups.

- Autocomplete data **MUST** be sourced exclusively from email headers (`From`, `To`, `CC`) of locally synced emails.
- The client **MUST NOT** access the system Contacts framework (`CNContact`, `ABAddressBook`). No contact permissions are requested.
- The client **MUST NOT** perform external contact directory lookups (LDAP, CardDAV, Google People API, etc.).
- The contact cache **MUST** be stored locally in SwiftData, scoped per account.
- Each contact entry stores: email address, display name (from email header), last seen date, frequency of appearance.
- Autocomplete results **SHOULD** be ranked by frequency of correspondence (most frequent first).
- When an account is removed, all associated contact cache entries **MUST** be deleted (cascade).
- Contact data **MUST NOT** be shared, exported, or transmitted to any external service.
- The unified inbox view **SHOULD** merge autocomplete suggestions across all accounts, deduplicating by email address.

---

## 4. Non-Functional Requirements

### NFR-COMP-01: Draft Save Latency

- **Metric**: Time for auto-save to persist draft
- **Target**: < 200ms
- **Hard Limit**: 500ms

### NFR-COMP-02: Autocomplete Response Time

- **Metric**: Time from keystroke to suggestion list update
- **Target**: < 100ms
- **Hard Limit**: 300ms

---

## 5. Data Model

Refer to Foundation spec Section 5. This feature creates/updates Email entities (draft state) and reads contact cache entries from SwiftData.

---

## 6. Architecture Overview

Refer to Foundation spec Section 6. This feature uses:
- `SendEmailUseCase` → `EmailRepositoryProtocol` for sending
- Contact cache queried from SwiftData directly

---

## 7. Platform-Specific Considerations

### iOS
- Composer presented as a sheet (modal)
- Camera and photo library access for image attachments

### macOS
- Composer opens in a separate window
- Multiple composer windows may be open simultaneously
- Drag-and-drop for file attachments

---

## 8. Alternatives Considered

| Alternative | Pros | Cons | Rejected Because |
|-------------|------|------|-----------------|
| Server-side undo (Gmail API) | Truly unsends | Requires proprietary API | Violates P-02 |
| System Contacts integration | Richer autocomplete | Privacy violation | Violates P-01 (no external data access) |

---

## 9. Open Questions

| # | Question | Owner | Target Date |
|---|----------|-------|-------------|
| — | — | — | — |

---

## 10. Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2025-02-07 | Core Team | Extracted from monolithic spec v1.2.0 section 5.5. Includes undo-send edge cases (5.5.2) and contacts autocomplete privacy (5.5.4). |
