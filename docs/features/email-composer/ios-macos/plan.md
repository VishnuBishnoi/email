---
title: "Email Composer — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/email-composer/spec.md
version: "1.3.0"
status: locked
assignees:
  - Core Team
target-milestone: V1.0
---

# Email Composer — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the email composition feature: composer UI with all four composition modes (new, reply, reply-all, forward), body editor with basic formatting, send validation, recipient autocomplete with privacy-preserving local contact cache, attachment handling (file picker, photo library, camera, forward attachments), draft auto-save lifecycle with IMAP sync, undo-send mechanism with complete edge case handling, and smart reply integration.

---

## 2. Platform Context

Refer to Foundation plan Section 2 for OS versions, device targets, and platform guidelines.

---

## 3. Architecture Mapping

### Email Composer Layout

```
┌──────────────────────────────────────────────────────────┐
│ Cancel             New Message               Send (⌘⇧D)  │
├──────────────────────────────────────────────────────────┤
│ From: user@example.com                          ▼         │
├──────────────────────────────────────────────────────────┤
│ To:  [alice@] [bob@] |                                    │
│      ┌──────────────────────────┐                         │
│      │ alice@example.com (12)   │ ← autocomplete dropdown │
│      │ alex@example.com (3)     │   ranked by frequency   │
│      └──────────────────────────┘                         │
├──────────────────────────────────────────────────────────┤
│ CC:  [+] (tap to expand)                                  │
│ BCC: [+] (tap to expand)                                  │
├──────────────────────────────────────────────────────────┤
│ Subject: Re: Meeting notes                                │
├──────────────────────────────────────────────────────────┤
│ [B] [I] [🔗]                    [📎 Attach] (⌘⇧A)        │
├──────────────────────────────────────────────────────────┤
│                                                           │
│ Hi Alice,                                                 │
│                                                           │
│ Thanks for the update.                                    │
│                                                           │
│ ──────────────────────────────────                        │
│ On Feb 5, 2026, Alice wrote:                              │
│ > Original message quoted here...                         │
│                                                           │
├──────────────────────────────────────────────────────────┤
│ 📎 report.pdf (2.1 MB)  [✕]                               │
│ 📎 photo.jpg (500 KB)   [✕]                               │
│ ⚠ Total: 2.6 MB / 25 MB                                  │
├──────────────────────────────────────────────────────────┤
│ [Smart Reply: "Thanks!" | "Got it" | "Will do"]          │
└──────────────────────────────────────────────────────────┘

Undo Toast (after send):
┌──────────────────────────────────────────────────────────┐
│ Sending in 5s...                              [Undo]      │
└──────────────────────────────────────────────────────────┘
```

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `ComposerView.swift` | Presentation/Views | Composition UI — sheet on iOS, window on macOS (uses @State, @Environment, .task) |
| `RecipientFieldView.swift` | Presentation/Components | Token-based recipient input with autocomplete dropdown |
| `BodyEditorView.swift` | Presentation/Components | Plain text body editor with basic formatting (bold, italic, links) |
| `AttachmentPickerView.swift` | Presentation/Components | File/photo picker + attachment list with remove |
| `UndoSendToastView.swift` | Presentation/Components | Countdown toast with undo button |
| `SmartReplyChipView.swift` | Presentation/Components | Smart reply suggestion chips |
| `ContactCacheEntry.swift` | Domain/Entities | Feature-local SwiftData entity for autocomplete cache |

**Note**: Per CLAUDE.md, this feature uses the MV (Model-View) pattern. No ViewModels — view logic uses `@State`, `@Environment`, `@Observable` services, and `.task` modifiers. Per Foundation FR-FOUND-01, views **MUST** call domain use cases only — never repositories directly.

---

## 4. Implementation Phases

| Task ID | Description | Spec FRs | Dependencies |
|---------|-------------|----------|-------------|
| IOS-U-15 | Composer view + modes + send validation + view states | FR-COMP-01 | IOS-U-01 (Navigation Router) |
| IOS-U-16 | Recipient field + contacts autocomplete | FR-COMP-04 | IOS-U-15 |
| IOS-U-17 | Draft auto-save + lifecycle + undo-send | FR-COMP-01, FR-COMP-02 | IOS-U-15 |
| IOS-U-18 | Attachment handling + smart reply integration | FR-COMP-01, FR-COMP-03 | IOS-U-15 |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Undo-send state machine complexity (app kill, background, offline) | Medium | High | Write `sendState = .queued` to SwiftData before countdown begins; build comprehensive state machine unit tests covering all Foundation sendState transitions |
| Draft sync conflicts (edited on another device) | Low | Medium | Server-side draft is overwritten on each auto-save; server version authoritative on next sync (per FR-SYNC-05); local is source of truth during active editing |
| Keyboard avoidance on iOS (body editor occluded by keyboard) | Medium | Medium | Use ScrollViewReader + .scrollDismissesKeyboard; test at all Dynamic Type sizes on iPhone SE (375pt) |
| Attachment size limits (25 MB total) | Low | Low | Validate cumulative size on each add; prevent send if over limit; clear error messaging with size breakdown |
| Multiple composer windows on macOS | Medium | Medium | Each composer window gets independent @State; ensure drafts don't conflict (use unique draft IDs in SwiftData) |
