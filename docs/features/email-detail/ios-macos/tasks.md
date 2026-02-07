---
title: "Email Detail — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-detail/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Email Detail — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-05: Email Detail View

- **Status**: `todo`
- **Spec ref**: Email Detail spec, FR-ED-01, FR-ED-02
- **Validation ref**: AC-U-05
- **Description**: Implement the threaded email detail view.
- **Deliverables**:
  - [ ] `EmailDetailView.swift` — scrollable thread of messages
  - [ ] `EmailDetailViewModel.swift` — fetch thread, mark read, actions
  - [ ] Expand/collapse individual messages
  - [ ] Auto-expand latest unread, collapse read messages
  - [ ] Action buttons: reply, reply-all, forward, star, archive, delete
  - [ ] VoiceOver support

### IOS-U-06: Message Bubble Component

- **Status**: `todo`
- **Spec ref**: Email Detail spec, FR-ED-01, FR-ED-04
- **Validation ref**: AC-U-06
- **Description**: Implement the individual email message display with HTML sanitization.
- **Deliverables**:
  - [ ] `MessageBubbleView.swift` — sender, recipients, timestamp, body
  - [ ] HTML email rendering (WKWebView with JS disabled for HTML, Text for plain)
  - [ ] HTML sanitization per FR-ED-04 (strip scripts, iframes, forms, event handlers)
  - [ ] Remote content blocking with "Load Images" action
  - [ ] Tracking pixel detection and stripping
  - [ ] Quoted text collapsing
  - [ ] Inline image display
  - [ ] Link handling (open in system browser)

### IOS-U-07: Attachment Handling

- **Status**: `todo`
- **Spec ref**: Email Detail spec, FR-ED-03
- **Validation ref**: AC-U-07
- **Description**: Implement attachment display, download, preview, and sharing with security warnings.
- **Deliverables**:
  - [ ] `AttachmentView.swift` — metadata display (name, type, size)
  - [ ] Download with progress indicator (explicit user tap only)
  - [ ] Security warning for dangerous file types per FR-ED-03
  - [ ] Inline preview for images and PDFs (QuickLook)
  - [ ] Share sheet integration
  - [ ] Sandboxed storage within app directory
