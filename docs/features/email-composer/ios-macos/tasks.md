---
title: "Email Composer — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-composer/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Email Composer — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-08: Composer View

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-01
- **Validation ref**: AC-U-08
- **Description**: Implement the email composition screen.
- **Deliverables**:
  - [ ] `ComposerView.swift` — presented as sheet on iOS
  - [ ] `ComposerViewModel.swift` — compose, reply, reply-all, forward modes
  - [ ] To, CC, BCC recipient fields
  - [ ] Subject field (pre-filled for replies/forwards)
  - [ ] Body editor with basic formatting (bold, italic, links)
  - [ ] Send button with validation
  - [ ] Discard confirmation dialog

### IOS-U-09: Recipient Auto-Complete

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-04
- **Validation ref**: AC-U-09
- **Description**: Implement recipient field with auto-complete from locally cached addresses.
- **Deliverables**:
  - [ ] `RecipientFieldView.swift` — token-based input with suggestions
  - [ ] Query locally cached sender/recipient addresses (SwiftData)
  - [ ] Dropdown suggestion list ranked by frequency
  - [ ] Email validation
  - [ ] No system Contacts access (privacy requirement)

### IOS-U-10: Draft Auto-Save

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-01
- **Validation ref**: AC-U-10
- **Description**: Auto-save drafts locally every 30 seconds and sync to server.
- **Deliverables**:
  - [ ] Timer-based local save (SwiftData)
  - [ ] IMAP draft sync (APPEND to Drafts folder)
  - [ ] Resume draft from thread list or drafts folder
  - [ ] Delete draft on send

### IOS-U-11: Undo Send

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-02
- **Validation ref**: AC-U-11
- **Description**: Implement configurable undo-send delay with all edge cases.
- **Deliverables**:
  - [ ] Delay timer before actual SMTP send (default 5s)
  - [ ] Toast/snackbar with undo button
  - [ ] Cancel send during delay window
  - [ ] Configurable delay in settings
  - [ ] Persist as pendingSend in SwiftData before countdown
  - [ ] Handle app termination (save as draft, not auto-send)
  - [ ] Handle background/foreground transitions (pause/resume timer)
