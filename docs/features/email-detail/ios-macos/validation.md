---
title: "Email Detail — iOS/macOS Validation"
spec-ref: docs/features/email-detail/spec.md
plan-refs:
  - docs/features/email-detail/ios-macos/plan.md
  - docs/features/email-detail/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# Email Detail — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-ED-01 | Thread display | MUST | AC-U-05 | Both | — |
| FR-ED-02 | AI integration points | MUST | AC-U-05 | Both | — |
| FR-ED-03 | Attachment handling + security | MUST | AC-U-07 | Both | — |
| FR-ED-04 | HTML rendering safety | MUST | AC-U-06 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-05**: Email Detail View

- **Given**: The user taps a thread with 3 messages (2 read, 1 unread)
- **When**: The email detail view opens
- **Then**: All 3 messages **MUST** be displayed in chronological order
  AND the 2 read messages **SHOULD** be collapsed
  AND the 1 unread message **MUST** be expanded
  AND the thread **MUST** be marked as read
  AND reply, reply-all, and forward buttons **MUST** be visible
  AND tapping a collapsed message **MUST** expand it
- **Priority**: Critical

---

**AC-U-06**: Message Rendering

- **Given**: An email with HTML body content
- **When**: The message is displayed
- **Then**: HTML content **MUST** render correctly (formatting, images, links)
  AND links **MUST** open in the system browser
  AND quoted text (replies) **SHOULD** be collapsible
  AND plain-text emails **MUST** render with preserved line breaks
  AND remote images **MUST** be blocked by default
  AND tracking pixels **MUST** be stripped
  AND `<script>`, `<iframe>`, `<form>` elements **MUST** be removed
- **Priority**: High

---

**AC-U-07**: Attachment Handling

- **Given**: An email with attachments (1 image 500KB, 1 PDF 10MB)
- **When**: The email detail is displayed
- **Then**: Both attachments **MUST** show filename, type, and size
  AND no attachment **MUST** auto-download
  AND tapping download **MUST** show a progress indicator
  AND after download, tapping the attachment **MUST** show a preview (QuickLook)
  AND the share button **MUST** open the system share sheet
  AND executable file types **MUST** display a security warning before download
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-06 | Very large thread (100+ messages) | Paginate messages; no OOM; scroll performance acceptable |
| E-07 | Email with large attachment (50MB+) | Attachment metadata shown; body loads; download requires explicit user action |
| E-10 | Email with malformed HTML | Rendered safely; no crash; fallback to plain text if necessary |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Email open (cached) | < 300ms | 500ms | Measured from tap to content visible | Fails if > 500ms on 3 consecutive runs |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix.

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
