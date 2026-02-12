---
title: "macOS Adaptation — iOS/macOS Implementation Plan"
platform: macOS
spec-ref: docs/features/macos-adaptation/spec.md
version: "1.3.0"
status: locked
updated: 2026-02-12
assignees:
  - Core Team
target-milestone: V1.0
---

# macOS Adaptation — iOS/macOS Implementation Plan

> This plan implements the macOS Native Experience specification (`docs/features/macos-adaptation/spec.md`). Refer to that spec for full requirements (FR-MAC-01 through FR-MAC-10) and Foundation spec Section 7.2 for cross-cutting macOS platform requirements.

---

## 1. Scope

This plan covers macOS-specific UI: three-pane layout, sidebar, composer window, keyboard shortcuts, toolbar, and drag-and-drop. All shared domain/data logic is reused from iOS implementation.

---

## 2. Platform Context

Refer to Foundation plan Section 2.

---

## 3. Architecture Mapping

### macOS Window Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ Toolbar: [Search] [Compose] [Reply] [Archive] [Delete] [Star]  │
├──────────┬──────────────────┬───────────────────────────────────┤
│ Sidebar  │ Thread List      │ Email Detail                     │
│          │                  │                                   │
│ Accounts │ ┌──────────────┐ │ From: sender@example.com         │
│ ▼ Gmail  │ │ Thread Row 1 │ │ To: me@gmail.com                │
│   Inbox  │ │ (selected)   │ │ Date: Feb 7, 2025               │
│   Sent   │ ├──────────────┤ │                                   │
│   Drafts │ │ Thread Row 2 │ │ [AI Summary]                     │
│   Trash  │ │              │ │                                   │
│   Spam   │ ├──────────────┤ │ Message body content...           │
│   Labels │ │ Thread Row 3 │ │                                   │
│          │ │              │ │ [Smart Reply] [Smart Reply]       │
│          │ ├──────────────┤ │ [Reply] [Reply All] [Forward]    │
├──────────┴──────────────────┴───────────────────────────────────┤
│ Status: Synced 2 min ago │ 3 unread │ AI: Ready                │
└─────────────────────────────────────────────────────────────────┘
```

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `MainWindowView.swift` | Mac/Views | NavigationSplitView three-pane |
| `SidebarView.swift` | Mac/Views | Accounts + folders |
| `MacThreadListView.swift` | Mac/Views/ThreadList | macOS thread list adaptation |
| `MacEmailDetailView.swift` | Mac/Views/EmailDetail | macOS email detail adaptation |
| `MacComposerWindow.swift` | Mac/Views/Composer | Separate window composer |
| `AppCommands.swift` | Mac/Commands | Keyboard shortcuts |
| `MacSettingsView.swift` | Mac/Views/Settings | macOS Settings scene |
| `MacNavigationRouter.swift` | Mac/Navigation | macOS navigation state |

---

## 4. Implementation Phases

| Task ID | Description | Spec Requirement | Dependencies |
|---------|-------------|-----------------|-------------|
| IOS-M-01 | macOS target configuration | FR-MAC-10 | Phase 1 (Foundation) |
| IOS-M-02 | Three-pane main window layout | FR-MAC-01 | IOS-M-01 |
| IOS-M-03 | Sidebar (accounts + folders) | FR-MAC-02 | IOS-M-02 |
| IOS-M-04 | macOS thread list adaptation | FR-MAC-04, FR-MAC-05 | IOS-M-02, Phase 2 (Core UI) |
| IOS-M-05 | macOS email detail adaptation | FR-MAC-06 | IOS-M-02, Phase 2 (Core UI) |
| IOS-M-06 | macOS composer window | FR-MAC-08 | IOS-M-01, Phase 2 (Core UI) |
| IOS-M-07 | Menu bar commands + keyboard shortcuts | FR-MAC-07 | IOS-M-01 |
| IOS-M-08 | macOS toolbar integration | FR-MAC-03 | IOS-M-02 |
| IOS-M-09 | Drag-and-drop for attachments | FR-MAC-09 | IOS-M-06 |
| IOS-M-10 | macOS settings (Settings scene) | — (existing) | IOS-M-01 |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| NavigationSplitView pane behavior | Medium | Medium | Test extensively on various Mac screen sizes; handle pane collapse gracefully |
