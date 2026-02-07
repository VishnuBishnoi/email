---
title: "Thread List — iOS/macOS Validation"
spec-ref: docs/features/thread-list/spec.md
plan-refs:
  - docs/features/thread-list/ios-macos/plan.md
  - docs/features/thread-list/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# Thread List — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-TL-01 | Thread display | MUST | AC-U-02, AC-U-03 | Both | — |
| FR-TL-02 | Category filtering | MUST | AC-U-02 | Both | — |
| FR-TL-03 | Gestures and interactions | MUST | AC-U-04 | Both | — |
| FR-TL-04 | Account switcher | MUST | AC-U-12 | Both | — |
| FR-TL-05 | Navigation | MUST | AC-U-01 | Both | — |
| G-02 | Multiple Gmail accounts | MUST | AC-U-12 | Both | — |
| G-03 | Threaded conversation view | MUST | AC-U-02 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-01**: iOS Navigation

- **Given**: The app is launched on iOS with at least one account
- **When**: The user navigates between screens
- **Then**: Thread list **MUST** be the root view
  AND tapping a thread **MUST** push the email detail view
  AND tapping compose **MUST** present the composer as a sheet
  AND tapping search **MUST** present the search view
  AND tapping settings **MUST** push or present the settings view
  AND back navigation **MUST** work consistently
- **Priority**: Critical

---

**AC-U-02**: Thread List

- **Given**: An account with synced emails
- **When**: The thread list is displayed
- **Then**: Threads **MUST** be sorted by most recent message date (newest first)
  AND each row **MUST** display: sender name, subject, snippet, timestamp, unread indicator, star indicator, attachment indicator
  AND category tabs **MUST** filter threads by AI category
  AND the list **MUST** scroll at 60fps with no visible jank
  AND empty state **MUST** display an appropriate message
- **Priority**: Critical

---

**AC-U-03**: Thread Row

- **Given**: A thread with known properties (unread, starred, has attachment, categorized)
- **When**: The thread row is rendered
- **Then**: Unread threads **MUST** display bold sender name and a dot indicator
  AND starred threads **MUST** display a star icon
  AND threads with attachments **MUST** display a paperclip icon
  AND the category badge **MUST** show the correct category
  AND the timestamp **MUST** display relative time (e.g., "2:30 PM", "Yesterday", "Feb 5")
  AND VoiceOver **MUST** announce all visible information
- **Priority**: High

---

**AC-U-04**: Thread List Interactions

- **Given**: The thread list is displayed
- **When**: The user performs gestures
- **Then**: Pull-to-refresh **MUST** trigger an incremental sync and update the list
  AND swipe right on a thread **MUST** archive it (move to All Mail)
  AND swipe left on a thread **MUST** delete it (move to Trash)
  AND long-press **MUST** enter multi-select mode
  AND in multi-select mode, batch archive/delete **MUST** work on all selected threads
- **Priority**: High

---

**AC-U-12**: Multi-Account

- **Given**: Two Gmail accounts are configured
- **When**: The user navigates the app
- **Then**: The account switcher **MUST** list both accounts
  AND selecting an account **MUST** show that account's thread list
  AND a unified inbox option **MUST** show threads from both accounts merged by date
  AND threads in unified view **MUST** indicate which account they belong to
  AND composing a new email **MUST** default to the selected account (or the configured default)
- **Priority**: High

---

## 3. Edge Cases

No feature-specific edge cases. General edge cases (network, storage) are in Foundation validation.

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Thread list scroll FPS | 60 fps | 30 fps | Instruments Core Animation on min-spec with 500+ threads | Fails if drops below 30fps for >1s |

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
