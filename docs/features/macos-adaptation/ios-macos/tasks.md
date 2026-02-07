---
title: "macOS Adaptation — iOS/macOS Task Breakdown"
platform: macOS
plan-ref: docs/features/macos-adaptation/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# macOS Adaptation — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-M-01 to IOS-M-10: macOS UI

- **Status**: `todo`
- **Spec ref**: Foundation spec, Section 7.2 (macOS)
- **Validation ref**: AC-M-01 through AC-M-05
- **Description**: macOS-specific UI implementation using shared domain/data layer.
- **Deliverables**:
  - [ ] macOS target build configuration
  - [ ] `MainWindowView.swift` — NavigationSplitView three-pane
  - [ ] `SidebarView.swift` — accounts and folder tree
  - [ ] macOS thread list adaptation
  - [ ] macOS email detail adaptation
  - [ ] `MacComposerWindow.swift` — separate window
  - [ ] `AppCommands.swift` — keyboard shortcuts (Cmd+N, Cmd+R, Cmd+Delete, Cmd+F)
  - [ ] macOS toolbar
  - [ ] Drag-and-drop for attachments
  - [ ] macOS Settings scene
