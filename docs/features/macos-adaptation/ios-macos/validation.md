---
title: "macOS Adaptation — iOS/macOS Validation"
spec-ref: docs/features/foundation/spec.md
plan-refs:
  - docs/features/macos-adaptation/ios-macos/plan.md
  - docs/features/macos-adaptation/ios-macos/tasks.md
version: "1.1.0"
status: locked
last-validated: 2026-02-11
---

# macOS Adaptation — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| G-06 | iOS and native macOS | MUST | AC-M-01 through AC-M-05 | macOS | — |

---

## 2. Acceptance Criteria

---

**AC-M-01**: macOS Build

- **Given**: The macOS target is configured
- **When**: The project is built and run on macOS
- **Then**: The app **MUST** launch as a native macOS application
  AND it **MUST** display in a resizable window (minimum 800x600)
  AND it **MUST** use a three-pane layout (sidebar, thread list, detail)
- **Priority**: Critical

---

**AC-M-02**: macOS Navigation

- **Given**: The macOS app is running with a configured account
- **When**: The user interacts with the sidebar
- **Then**: Accounts **MUST** be listed with expandable folder trees
  AND clicking a folder **MUST** update the thread list pane
  AND clicking a thread **MUST** display the email detail in the right pane
  AND all three panes **MUST** be visible simultaneously
  AND pane widths **SHOULD** be resizable via drag handles
- **Priority**: Critical

---

**AC-M-03**: macOS Composer

- **Given**: The user triggers compose on macOS
- **When**: Cmd+N is pressed or the compose button is clicked
- **Then**: A new composer window **MUST** open (separate from the main window)
  AND the composer **MUST** have the same functionality as the iOS composer
  AND multiple composer windows **MAY** be open simultaneously
  AND closing a composer window with unsaved content **MUST** prompt to save as draft
- **Priority**: High

---

**AC-M-04**: Keyboard Shortcuts

- **Given**: The macOS app is focused
- **When**: Keyboard shortcuts are pressed
- **Then**: Cmd+N **MUST** open a new composer
  AND Cmd+R **MUST** reply to the selected email
  AND Cmd+Shift+R **MUST** reply-all
  AND Cmd+Delete **MUST** delete the selected thread
  AND Cmd+F **MUST** focus the search field
  AND Delete/Backspace **MUST** archive the selected thread
  AND these shortcuts **MUST** appear in the menu bar
- **Priority**: High

---

**AC-M-05**: macOS Toolbar and Drag-Drop

- **Given**: The macOS app is displaying an email
- **When**: The user interacts with the toolbar and attachments
- **Then**: The toolbar **MUST** show Reply, Reply All, Forward, Archive, Delete, Star buttons
  AND dragging a file onto the composer **MUST** attach it
  AND dragging an attachment from the detail view to Finder **MUST** save the file
- **Priority**: Medium

---

## 3. Edge Cases

No feature-specific edge cases beyond those in foundation.

---

## 4. Performance Validation

Refer to Foundation validation Section 4 for shared performance metrics.

---

## 5. Device Test Matrix

| Device | OS | Role |
|--------|-----|------|
| MacBook Air M1 (8GB) | macOS 14 | Min-spec Mac validation |
| MacBook Pro M3 (18GB) | macOS 14 | Reference Mac, AI performance |

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
