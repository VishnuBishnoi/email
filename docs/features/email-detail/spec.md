---
title: "Email Detail — Specification"
version: "1.0.0"
status: draft
created: 2025-02-07
updated: 2025-02-07
authors:
  - Core Team
reviewers: []
tags: [email-detail, attachments, html-safety, rendering]
depends-on:
  - docs/constitution.md
  - docs/features/foundation/spec.md
  - docs/features/email-sync/spec.md
---

# Specification: Email Detail

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in RFC 2119.

## 1. Summary

This specification defines the email detail screen — the threaded conversation view. It covers message display, HTML rendering safety, attachment handling and security, and integration points for AI-generated summaries and smart reply suggestions.

---

## 2. Goals and Non-Goals

### Goals

- Display full thread with all messages in chronological order
- Safely render HTML email content (sanitized, no scripts, no tracking)
- Secure attachment handling (no auto-download, no auto-execute)
- Display AI summaries and smart reply suggestions

### Non-Goals

- Email editing (only viewing)
- Inline reply composition (handled by Email Composer spec)

---

## 3. Functional Requirements

### FR-ED-01: Thread Display

- The client **MUST** display the full thread with all messages in chronological order.
- Each message **MUST** show: sender name + avatar, recipients (To, CC), timestamp, full body (HTML rendered or plain text), attachment list with download option.
- The client **MUST** mark a thread as read when opened.
- The client **MUST** support reply, reply-all, and forward actions.
- The client **MUST** support star/unstar, archive, and delete actions.
- The client **MUST** allow expanding/collapsing individual messages within the thread.
- The client **SHOULD** collapse read messages by default, expanding the latest unread message.

### FR-ED-02: AI Integration Points

- The client **MUST** display an AI-generated thread summary at the top of the thread (generated on demand or cached). See AI Features spec.
- The client **MUST** display smart reply suggestions at the bottom of the thread. See AI Features spec.

### FR-ED-03: Attachment Handling

- The client **MUST** display attachment metadata (name, type, size) inline with the message.
- The client **MUST** support downloading attachments to local storage on explicit user action (tap).
- The client **MUST** support previewing common attachment types (images, PDFs) via system QuickLook (sandboxed).
- The client **MUST** support sharing attachments via the system share sheet.

**Attachment Security**

- The client **MUST NOT** auto-download any attachment regardless of size. All attachments require explicit user tap to download.
- The client **MUST NOT** auto-open or auto-execute any attachment after download.
- Attachment previews **MUST** use the system QuickLook framework, which provides sandboxed rendering.
- The client **MUST** display a security warning before downloading executable or potentially dangerous file types:

  | File Extensions | Warning |
  |----------------|---------|
  | `.exe`, `.bat`, `.cmd`, `.com`, `.msi` | "This file is a Windows executable." |
  | `.app`, `.command`, `.sh`, `.pkg`, `.dmg` | "This file can run code on your Mac." |
  | `.js`, `.vbs`, `.wsf`, `.scr` | "This file is a script that can run code." |
  | `.zip`, `.rar`, `.7z`, `.tar.gz` | "This archive may contain executable files." |

- The client **MUST NOT** execute attachments directly. Opening an attachment **MUST** delegate to the system handler (e.g., Finder, default app).
- Downloaded attachment files **MUST** be stored within the app's sandbox directory, not in shared locations.

### FR-ED-04: HTML Rendering Safety

Email HTML is untrusted content. The client **MUST** sanitize and restrict HTML rendering to prevent privacy leaks, tracking, and code execution.

**Remote Content Blocking**

- The client **MUST** block all remote content (images, CSS, fonts, iframes) by default.
- Blocked remote images **MUST** display a placeholder with an indication that images were blocked.
- The client **MUST** provide a per-message "Load Remote Images" action.
- The client **SHOULD** provide a per-sender "Always Load Remote Images" preference (stored locally).
- When remote images are blocked, no network requests for those resources **SHALL** be made.

**Tracking Pixel Detection**

- The client **MUST** detect and strip likely tracking pixels before rendering, even when remote images are allowed:
  - Images with dimensions 1x1 or 0x0 (in `width`/`height` attributes or inline CSS)
  - Images with URLs matching known tracking domains (maintain a local blocklist)
  - Images embedded in visually hidden elements (`display:none`, `visibility:hidden`, `opacity:0`)
- Stripped tracking pixels **MUST NOT** generate any network request.
- The client **SHOULD** display a count of blocked trackers per message (e.g., "3 trackers blocked").

**HTML Sanitization**

The following elements and attributes **MUST** be stripped or neutralized before rendering:

| Removed | Reason |
|---------|--------|
| `<script>`, `<noscript>` | Code execution |
| `<iframe>`, `<frame>`, `<frameset>` | External content embedding |
| `<object>`, `<embed>`, `<applet>` | Plugin/code execution |
| `<form>`, `<input>`, `<button>`, `<select>`, `<textarea>` | Phishing form submission |
| `<meta http-equiv="refresh">` | Automatic redirect |
| `<link rel="stylesheet">` (external) | Remote resource loading |
| `@import` in CSS | Remote CSS loading |
| Event handler attributes (`onclick`, `onerror`, `onload`, `onmouseover`, etc.) | Code execution |
| `javascript:` URI scheme in `href`, `src`, `action` | Code execution |
| `data:` URI scheme (except for inline images in `<img>` tags) | Content injection |

**Rendering Constraints**

- HTML **MUST** be rendered in a `WKWebView` with JavaScript **disabled** (`javaScriptEnabled = false`).
- All hyperlinks **MUST** open in the system default browser, never navigated within the WKWebView.
- The WKWebView **MUST** have no access to the app's cookies, local storage, or network session.
- If sanitization fails or produces empty output, the client **MUST** fall back to rendering the plain text body.

---

## 4. Non-Functional Requirements

### NFR-ED-01: Email Open Time

- **Metric**: Time from tap to content visible (cached email)
- **Target**: < 300ms
- **Hard Limit**: 500ms

### NFR-ED-02: Large Thread Handling

- **Metric**: Performance with 100+ messages in a thread
- **Target**: No OOM, acceptable scroll performance
- **Hard Limit**: Must paginate if needed

---

## 5. Data Model

Refer to Foundation spec Section 5 for Email, Thread, and Attachment entities.

---

## 6. Architecture Overview

Refer to Foundation spec Section 6. This feature uses:
- Email detail reads Thread + Email entities
- `SummarizeThreadUseCase` and `SmartReplyUseCase` for AI integration (see AI Features spec)

---

## 7. Platform-Specific Considerations

### iOS
- Full-screen push from thread list via NavigationStack

### macOS
- Right pane of three-pane layout
- See macOS Adaptation plan for details

---

## 8. Alternatives Considered

| Alternative | Pros | Cons | Rejected Because |
|-------------|------|------|-----------------|
| Native HTML rendering (no sanitization) | Richer display | Security/privacy risk | Unacceptable for privacy-first client |
| Plain text only | Maximum safety | Loses formatting | Most modern emails require HTML |
| Embedded browser (full WebView) | Full fidelity | JS execution risk | Must disable JS per security requirements |

---

## 9. Open Questions

| # | Question | Owner | Target Date |
|---|----------|-------|-------------|
| — | — | — | — |

---

## 10. Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2025-02-07 | Core Team | Extracted from monolithic spec v1.2.0 section 5.4. Includes HTML Rendering Safety (5.4.3) and expanded Attachment Security (5.4.2). |
