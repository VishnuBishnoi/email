---
title: "macOS Adaptation — iOS/macOS Task Breakdown"
platform: macOS
plan-ref: docs/features/macos-adaptation/ios-macos/plan.md
version: "1.1.0"
status: locked
updated: 2026-02-10
---

# macOS Adaptation — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.
> **Note**: macOS adaptation is deferred. The app compiles and runs on macOS with platform guards but lacks dedicated macOS UI. All domain/data layer code is cross-platform.

---

### IOS-M-01 to IOS-M-10: macOS UI

- **Status**: `deferred`
- **Spec ref**: Foundation spec, Section 7.2 (macOS)
- **Validation ref**: AC-M-01 through AC-M-05
- **Description**: macOS-specific UI implementation using shared domain/data layer.
- **Current state**: Platform guards (`#if os(iOS)`, `#if os(macOS)`, `#if canImport(UIKit)`) exist across presentation layer. The app compiles for macOS but uses iOS-style navigation. HTML email rendering falls back to plain text on macOS. Favicon caching unavailable on macOS (no UIImage bridge). BottomTabBar uses `#available(iOS 26.0, macOS 26.0, *)` for glass effects.
- **Deliverables**:
  - [ ] `MainWindowView.swift` — NavigationSplitView three-pane
  - [ ] `SidebarView.swift` — accounts and folder tree
  - [ ] macOS thread list adaptation
  - [ ] macOS email detail adaptation (WKWebView HTML rendering)
  - [ ] `MacComposerWindow.swift` — separate window
  - [ ] `AppCommands.swift` — keyboard shortcuts (Cmd+N, Cmd+R, Cmd+Delete, Cmd+F)
  - [ ] macOS toolbar
  - [ ] Drag-and-drop for attachments
  - [ ] macOS Settings scene
- **Notes**: All domain use cases, data layer, and AI features are cross-platform. Only presentation layer needs macOS-specific work.
