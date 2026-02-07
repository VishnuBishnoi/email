---
title: "Email Detail — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/email-detail/spec.md
version: "1.0.0"
status: draft
assignees:
  - Core Team
target-milestone: V1.0
---

# Email Detail — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the email detail screen: threaded message display, HTML rendering with sanitization, attachment handling with security, and AI integration points (summary + smart reply).

---

## 2. Platform Context

Refer to Foundation plan Section 2.

---

## 3. Architecture Mapping

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `EmailDetailView.swift` | iOS/Views/EmailDetail | Scrollable thread view |
| `EmailDetailViewModel.swift` | iOS/Views/EmailDetail | Thread fetching, mark read, actions |
| `MessageBubbleView.swift` | iOS/Views/EmailDetail | Individual message display |
| `AttachmentView.swift` | iOS/Views/EmailDetail | Attachment UI + download |
| `HTMLSanitizer.swift` | Shared/Utilities | HTML sanitization engine |

---

## 4. Implementation Phases

| Task ID | Description | Dependencies |
|---------|-------------|-------------|
| IOS-U-05 | Email detail view + view model | IOS-U-01 (Thread List), IOS-F-10 (Email Sync) |
| IOS-U-06 | Message bubble component (HTML render + plain text) | IOS-U-05 |
| IOS-U-07 | Attachment view + download | IOS-U-05 |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| HTML sanitization edge cases | Medium | High | Build comprehensive test suite with real-world email HTML samples |
| WKWebView memory with many messages | Medium | Medium | Lazy load WKWebViews; use single shared instance with content swapping |
