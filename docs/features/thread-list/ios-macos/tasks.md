---
title: "Thread List — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/thread-list/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Thread List — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-01: iOS Navigation Structure

- **Status**: `todo`
- **Spec ref**: Thread List spec, FR-TL-05
- **Validation ref**: AC-U-01
- **Description**: Set up iOS navigation using NavigationStack with programmatic routing.
- **Deliverables**:
  - [ ] `iOSNavigationRouter.swift` — route definitions, navigation state
  - [ ] Tab bar or root navigation structure
  - [ ] Deep link support structure (for future use)

### IOS-U-02: Thread List View

- **Status**: `todo`
- **Spec ref**: Thread List spec, FR-TL-01, FR-TL-02
- **Validation ref**: AC-U-02
- **Description**: Implement the main thread list screen with ViewModel.
- **Deliverables**:
  - [ ] `ThreadListView.swift` — LazyVStack of thread rows
  - [ ] `ThreadListViewModel.swift` — fetch, filter, sort, pagination
  - [ ] Category tab bar (All, Primary, Social, Promotions, Updates)
  - [ ] Empty state views
  - [ ] Loading states

### IOS-U-03: Thread Row Component

- **Status**: `todo`
- **Spec ref**: Thread List spec, FR-TL-01
- **Validation ref**: AC-U-03
- **Description**: Implement the thread row UI component.
- **Deliverables**:
  - [ ] `ThreadRowView.swift` — avatar, sender, subject, snippet, timestamp
  - [ ] Unread indicator (bold text + dot)
  - [ ] Star indicator
  - [ ] Attachment indicator
  - [ ] Category badge
  - [ ] Dynamic Type support
  - [ ] VoiceOver labels

### IOS-U-04: Thread List Interactions

- **Status**: `todo`
- **Spec ref**: Thread List spec, FR-TL-03
- **Validation ref**: AC-U-04
- **Description**: Implement pull-to-refresh, swipe gestures, and multi-select.
- **Deliverables**:
  - [ ] Pull-to-refresh triggering sync
  - [ ] Swipe right to archive
  - [ ] Swipe left to delete
  - [ ] Long-press for multi-select mode
  - [ ] Batch actions toolbar (archive, delete, mark read/unread)

### IOS-U-12: Account Switcher

- **Status**: `todo`
- **Spec ref**: Thread List spec, FR-TL-04
- **Validation ref**: AC-U-12
- **Description**: Multi-account navigation and unified inbox.
- **Deliverables**:
  - [ ] Account switcher sheet/popover
  - [ ] Per-account thread list
  - [ ] Unified inbox (all accounts merged, sorted by date)
  - [ ] Account indicator per thread in unified view
