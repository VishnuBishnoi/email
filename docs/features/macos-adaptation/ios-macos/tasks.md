---
title: "macOS Adaptation — iOS/macOS Task Breakdown"
platform: macOS
plan-ref: docs/features/macos-adaptation/ios-macos/plan.md
version: "2.0.0"
status: locked
updated: 2026-02-12
---

# macOS Adaptation — iOS/macOS Task Breakdown

> Each task references its plan phase, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.
> **Note**: All domain/data layer code is cross-platform and already implemented via thread-list and other feature tasks. These tasks cover macOS presentation-layer only.

---

### IOS-M-01: macOS Target Configuration & Window Setup

- **Status**: `todo`
- **Plan phase**: Phase 1
- **Spec ref**: FR-MAC-10 (Window Configuration)
- **Validation ref**: AC-M-01
- **Description**: Configure the macOS target with correct window sizing, resizability, and scene setup. Add platform fork at the app entry point to route macOS to `MacOSMainView` and iOS to the existing `ContentView`.
- **Deliverables**:
  - [ ] `VaultMailApp.swift` — Add `#if os(macOS)` / `#if os(iOS)` platform conditional at the root `WindowGroup` to route to `MacOSMainView` on macOS and existing `ContentView` on iOS
  - [ ] macOS `WindowGroup` scene with `.defaultSize(width: 1200, height: 800)` and `.windowResizability(.contentMinSize)` for 800×600 minimum
  - [ ] macOS `Settings` scene wiring (ensure existing settings view renders in ⌘, window)
  - [ ] Verify iOS target is unaffected — existing `ContentView` / `NavigationStack` / `BottomTabBar` unchanged
  - [ ] `MacOSMainView.swift` — Stub `NavigationSplitView` placeholder (full implementation in IOS-M-02)

---

### IOS-M-02: Three-Pane Main Window Layout

- **Status**: `todo`
- **Plan phase**: Phase 2
- **Spec ref**: FR-MAC-01 (Three-Pane Layout)
- **Validation ref**: AC-M-02
- **Dependencies**: IOS-M-01
- **Description**: Implement the `NavigationSplitView` three-column layout as the root navigation container on macOS, replacing the iOS `NavigationStack` pattern. Includes column widths, visibility management, empty states, and platform guards.
- **Deliverables**:
  - [ ] `MacOSMainView.swift` — `NavigationSplitView` with three columns: sidebar (min 180pt, ideal 220pt), content (min 280pt, ideal 340pt), detail (min 400pt, remaining)
  - [ ] Column visibility management via `@State` or `@SceneStorage` for sidebar toggle persistence across launches
  - [ ] `@State private var selectedAccount: Account?` — sidebar → content state binding
  - [ ] `@State private var selectedFolder: Folder?` — sidebar → content state binding
  - [ ] `@State private var selectedThreadID: String?` — content → detail state binding via `NavigationSplitView` `selection` parameter
  - [ ] Empty states: "Select a folder" (no folder selected), `ContentUnavailableView` with "No Conversation Selected" (no thread selected), full-window onboarding (no account), "No emails in [Folder Name]" (empty folder)
  - [ ] `#if os(iOS)` guard on `BottomTabBar` — **MUST NOT** render on macOS
  - [ ] `#if os(macOS)` / `#if os(iOS)` at root container in `ContentView` or app entry point
  - [ ] `.automaticColumnVisibility` behavior for standard macOS pane management
  - [ ] Graceful fallback if state restoration fails (default column visibility, no crash)
  - [ ] SwiftUI previews for: three-column, sidebar-collapsed, no-selection, no-account states

---

### IOS-M-03: Sidebar — Accounts and Folder Tree

- **Status**: `todo`
- **Plan phase**: Phase 3
- **Spec ref**: FR-MAC-02 (Sidebar — Folder and Account Navigation)
- **Validation ref**: AC-M-03
- **Dependencies**: IOS-M-02
- **Description**: Implement the persistent sidebar with account selector, expandable folder trees, unread badges, Unified Inbox entry, and native macOS `.listStyle(.sidebar)` styling.
- **Deliverables**:
  - [ ] `SidebarView.swift` — Sidebar content with `.listStyle(.sidebar)` for native macOS appearance
  - [ ] Account sections: each account as expandable `DisclosureGroup` or `Section` with email address header
  - [ ] `@State` or `@SceneStorage` for `sidebarExpandedAccounts: Set<String>` to track which accounts are expanded
  - [ ] System folders in fixed order per account: Inbox, Starred, Sent, Drafts, Spam, Trash, Archive
  - [ ] Outbox virtual folder after Archive (per FR-TL-04 / FR-SYNC-07)
  - [ ] Custom Gmail labels in "Labels" section below system folders, sorted alphabetically
  - [ ] Unread badge counts per folder (unread for Inbox/Spam, draft count for Drafts, queued+failed for Outbox)
  - [ ] Badge shows "—" when count unavailable (error state)
  - [ ] "Unified Inbox" entry — selecting merges all accounts' threads sorted by `latestDate`
  - [ ] Currently active account visually distinguished (bold text or highlight)
  - [ ] Clicking account header expands/collapses folder tree
  - [ ] Folder selection highlights with standard macOS sidebar selection style
  - [ ] Selecting folder resets thread list to page 1 and "All" category tab
  - [ ] In Unified Inbox mode: per-account folder trees greyed out; user must select specific account for non-Inbox folders
  - [ ] Error state: "Unable to load folders" with "Retry" button per account section
  - [ ] **MUST NOT** use `.listStyle(.insetGrouped)` or `.listStyle(.plain)` — iOS patterns
  - [ ] SwiftUI previews for: multi-account expanded, single account, unified selected, error state, empty labels

---

### IOS-M-04: macOS Thread List Adaptation

- **Status**: `todo`
- **Plan phase**: Phase 4
- **Spec ref**: FR-MAC-04 (Thread List), FR-MAC-05 (Thread Interactions)
- **Validation ref**: AC-M-04, AC-M-05
- **Dependencies**: IOS-M-02, Thread List feature tasks (IOS-U-02, IOS-U-03 shared views)
- **Description**: Adapt the thread list for the macOS content column. Reuse shared `ThreadRowView` with macOS-specific selection model (single-click select, ⌘-click multi-select, ⇧-click range), context menus, and category segmented control.
- **Deliverables**:
  - [ ] `MacThreadListView.swift` — Thread list in content column using `List` with `selection` binding to `selectedThreadID`
  - [ ] Single-click selects thread and shows detail in detail column — **MUST NOT** push a new navigation view
  - [ ] Selection via `@State` / `@Binding` bound to `NavigationSplitView` `selection` parameter — not `NavigationPath`
  - [ ] `⌘`-click toggles individual thread selection (add/remove)
  - [ ] `⇧`-click selects contiguous range from last selected to clicked thread
  - [ ] Multi-select detail: detail column shows "[N] conversations selected" with batch action buttons
  - [ ] `Escape` key clears all selection in multi-select mode
  - [ ] Category segmented control or horizontal pill bar above thread list (All, Primary, Social, Promotions, Updates) — within content column, not sidebar
  - [ ] Category tab behavior matches Thread List FR-TL-02 (local filter, instant switch, AI fallback hides tabs)
  - [ ] Reuse shared `ThreadRowView` (sender avatar, name, subject, snippet, timestamp, unread indicator, star, attachment icon, AI category badge)
  - [ ] Thread rows **MAY** show wider snippet preview than iOS due to column width
  - [ ] Pagination: cursor-based, 25/page, infinite scroll with sentinel row `.onAppear` (per FR-TL-01)
  - [ ] View states: Loading, Loaded, Empty, Empty Filtered, Error, Offline (per FR-TL-01)
  - [ ] Context menu (right-click) on thread row: Reply, Reply All, Forward, separator, Archive, Delete, Move to Folder…, separator, Mark as Read/Unread, Star/Unstar
  - [ ] Context menu on multi-selected threads applies batch actions to all selected
  - [ ] Trackpad swipe gestures **OPTIONAL** for V1 (archive swipe right, delete swipe left)
  - [ ] Batch action errors: report failure count, keep failed threads selected for retry (per FR-TL-03)
  - [ ] SwiftUI previews for: loaded, empty, multi-select, context menu

---

### IOS-M-05: macOS Email Detail Adaptation

- **Status**: `todo`
- **Plan phase**: Phase 5
- **Spec ref**: FR-MAC-06 (Email Detail)
- **Validation ref**: AC-M-06
- **Dependencies**: IOS-M-02, Email Detail feature tasks (shared views)
- **Description**: Adapt the email detail for the macOS detail column. Implement `NSViewRepresentable` WKWebView for HTML rendering, macOS Quick Look for attachments, `NSSharingServicePicker` for sharing, hover states for links, and keyboard navigation within thread.
- **Deliverables**:
  - [ ] `MacEmailDetailView.swift` — Email detail in detail column of `NavigationSplitView`
  - [ ] `HTMLEmailView_macOS.swift` — `NSViewRepresentable` wrapper for `WKWebView` on macOS (separate file from iOS `UIViewRepresentable` wrapper)
  - [ ] `#if os(macOS)` / `#if os(iOS)` guards for HTML rendering wrappers
  - [ ] Shared `HTMLSanitizer`, `TrackingBlocklist`, `HTMLRenderConfiguration` — sanitization logic **MUST NOT** be duplicated between platforms
  - [ ] HTML rendering: disabled JavaScript, non-persistent data store, blocked remote content, tracking pixel stripping, link safety (per FR-ED-04)
  - [ ] Attachment preview via macOS Quick Look (`.quickLookPreview()` or `QLPreviewPanel`)
  - [ ] Attachment sharing via `NSSharingServicePicker` (not `UIActivityViewController`)
  - [ ] `#if os(iOS)` guard on `UIActivityViewController` and `PhotosUI.PhotosPicker`
  - [ ] Link hover states: display destination URL via tooltip or macOS status bar
  - [ ] Reply, Reply All, Forward buttons in detail column header or toolbar
  - [ ] After archive/delete: show next thread in list or "No Conversation Selected" placeholder
  - [ ] Keyboard navigation within thread: `↑`/`↓` navigate messages, `⏎` expand/collapse, `⌘R` reply, `⌘⇧R` reply all, `⌘⇧E` forward
  - [ ] Error handling matches Email Detail FR-ED-01 (view states, mark-as-read revert, action revert with toast)
  - [ ] SwiftUI previews for: loaded email, multi-message thread, no selection placeholder

---

### IOS-M-06: macOS Composer Window

- **Status**: `todo`
- **Plan phase**: Phase 6
- **Spec ref**: FR-MAC-08 (Multi-Window Support)
- **Validation ref**: AC-M-07
- **Dependencies**: IOS-M-01, Email Composer feature tasks (shared composer view)
- **Description**: Implement compose in both sheet and separate window modes on macOS. Default to sheet (consistent with iOS) with "Open in Window" option. Support multiple simultaneous compose windows and unsaved content draft prompt.
- **Deliverables**:
  - [ ] `MacComposerWindow.swift` — Composer presented as `WindowGroup` or `Window` scene with unique identifier
  - [ ] Default compose mode: sheet within main window (consistent with iOS)
  - [ ] "Open in Window" button in composer toolbar to open in separate macOS window
  - [ ] Compose window default size: 600×500pt, resizable
  - [ ] Multiple compose windows **MAY** be open simultaneously (one reply + one new email)
  - [ ] Unsaved content prompt on close: "Save as Draft?" with Save, Discard, Cancel options
  - [ ] Full composer functionality: recipients, subject, body, attachments (identical to iOS composer)
  - [ ] Compose defaults to selected account (or configured default)
  - [ ] Fallback: if compose window fails to open, present as sheet within main window
  - [ ] `⌘N` triggers compose (wired in IOS-M-07)
  - [ ] SwiftUI previews for: new email, reply mode, window mode

---

### IOS-M-07: Menu Bar Commands + Keyboard Shortcuts

- **Status**: `todo`
- **Plan phase**: Phase 7
- **Spec ref**: FR-MAC-07 (Keyboard Shortcuts)
- **Validation ref**: AC-M-08
- **Dependencies**: IOS-M-01
- **Description**: Implement comprehensive keyboard shortcuts and menu bar structure via SwiftUI `.commands` modifier on `WindowGroup`. All common email actions must be accessible via keyboard.
- **Deliverables**:
  - [ ] `AppCommands.swift` — SwiftUI `Commands` conformance with `.commands` modifier on `WindowGroup`
  - [ ] **File menu**: New Email (`⌘N`)
  - [ ] **Edit menu**: Find (`⌘F`), Select All (`⌘A`)
  - [ ] **Message menu**: Reply (`⌘R`), Reply All (`⌘⇧R`), Forward (`⌘⇧E`), Archive (`⌘⇧A`), Delete (`⌘⌫`), Mark Read/Unread (`⌘⇧U`), Star/Unstar (`⌘⇧L`), Move to Folder… (`⌘⇧M`)
  - [ ] **View menu**: Sidebar Toggle (`⌘⌥S`), Refresh (`⌃⇧R`)
  - [ ] List navigation shortcuts: `↑`/`↓` navigate threads, `⏎` open selected thread, `⌥⌘N` next unread, `Space` scroll detail
  - [ ] Context-aware enable/disable: thread-dependent actions disabled when no thread selected
  - [ ] `.keyboardShortcut()` on individual toolbar controls matching menu shortcuts
  - [ ] Error handling: keyboard-triggered action failures follow same toast-with-retry pattern as toolbar/menu actions
  - [ ] `AppCommandsTests.swift` — Tests: verify menu items enable/disable based on selection state, shortcut bindings match spec table

---

### IOS-M-08: macOS Toolbar Integration

- **Status**: `todo`
- **Plan phase**: Phase 8
- **Spec ref**: FR-MAC-03 (macOS Toolbar)
- **Validation ref**: AC-M-09
- **Dependencies**: IOS-M-02
- **Description**: Implement the native macOS toolbar using SwiftUI `.toolbar` modifier with macOS-appropriate placements. Includes action buttons, search field, and state-dependent enable/disable.
- **Deliverables**:
  - [ ] macOS `.toolbar` modifier on `MacOSMainView` with correct placements
  - [ ] Compose button (`.primaryAction`, `square.and.pencil`, `⌘N`) — always enabled
  - [ ] Delete button (`.secondaryAction`, `trash`, `⌘⌫`) — enabled when thread(s) selected
  - [ ] Archive button (`.secondaryAction`, `archivebox`, `⌘⇧A`) — enabled when thread(s) selected
  - [ ] Move button (`.secondaryAction`, `folder`, `⌘⇧M`) — presents "Move to Folder" sheet
  - [ ] Flag/Star toggle (`.secondaryAction`, `star`/`star.fill`, `⌘⇧L`) — icon toggles based on thread state
  - [ ] Mark Read/Unread toggle (`.secondaryAction`, `envelope`/`envelope.open`, `⌘⇧U`) — icon toggles based on thread state
  - [ ] Sync button (`.secondaryAction`, `arrow.clockwise`, `⌃⇧R`) — always enabled
  - [ ] Sidebar toggle (`.navigation`, `sidebar.leading`, `⌘⌥S`) — always enabled
  - [ ] Inline search field via `.searchable` with `.toolbar` placement, 300ms debounce, same `SearchEmailsUseCase` as iOS
  - [ ] Search results replace thread list in content column; `Escape` dismisses search and restores folder view
  - [ ] Action buttons disabled (greyed out) when no thread selected; enabled when thread(s) selected
  - [ ] In multi-select mode: toolbar actions apply to all selected threads as batch
  - [ ] Optimistic update with revert on failure + error toast: "Couldn't [action]. Click to retry." (per FR-TL-03 / FR-SYNC-05)
  - [ ] SwiftUI previews for: no selection (buttons disabled), single selection, multi-selection

---

### IOS-M-09: Drag-and-Drop for Attachments

- **Status**: `todo`
- **Plan phase**: Phase 9
- **Spec ref**: FR-MAC-09 (macOS Attachment Handling)
- **Validation ref**: AC-M-10
- **Dependencies**: IOS-M-06
- **Description**: Implement macOS-native file picking, drag-and-drop attachments into composer, and drag-out from email detail to Finder. Replace iOS-only `UIDocumentPickerViewController` and `PhotosUI.PhotosPicker` with `fileImporter` / `NSOpenPanel`.
- **Deliverables**:
  - [ ] `MacAttachmentPickerView.swift` — File selection via `fileImporter` (SwiftUI native) or `NSOpenPanel` on macOS
  - [ ] Multiple file selection support in file picker
  - [ ] `#if os(iOS)` guard on `UIDocumentPickerViewController` and `PhotosUI.PhotosPicker`
  - [ ] Drag-and-drop onto composer: accept files dropped on attachment area or message body via `dropDestination` modifier
  - [ ] Drag-out from email detail: downloaded attachments draggable to Finder/other apps via `draggable` modifier or `NSItemProvider`
  - [ ] Attachment sharing via `NSSharingServicePicker` on macOS (not `UIActivityViewController`)
  - [ ] `#if os(iOS)` guard on `UIActivityViewController`
  - [ ] SwiftUI previews for: file picker, drop target indicator

---

### IOS-M-10: macOS Settings (Settings Scene)

- **Status**: `todo`
- **Plan phase**: Phase 10
- **Spec ref**: Existing settings (no new FR)
- **Validation ref**: AC-M-11
- **Dependencies**: IOS-M-01
- **Description**: Ensure the existing settings view renders correctly in the macOS `Settings` scene (⌘,). Adapt layout if needed for macOS settings window conventions (tab-based layout for multiple sections).
- **Deliverables**:
  - [ ] `MacSettingsView.swift` — Settings scene wrapper, adapt existing settings for macOS window conventions
  - [ ] `Settings` scene in `VaultMailApp.swift` rendering the settings view
  - [ ] Tab-based layout for settings sections if multiple sections exist (macOS convention)
  - [ ] Verify all settings fields render correctly in macOS settings window
  - [ ] Verify `⌘,` shortcut opens settings (built-in macOS behavior)
  - [ ] SwiftUI preview for macOS settings layout

---

## Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2026-02-10 | Core Team | Initial task breakdown — single deferred block |
| 1.1.0 | 2026-02-10 | Core Team | Added platform guards context, current state description |
| 2.0.0 | 2026-02-12 | Core Team | Full rewrite to match locked spec v1.2.0 and plan v1.3.0. Expanded single deferred block into 10 individual task breakdowns (IOS-M-01 through IOS-M-10) with per-task deliverable checklists, spec refs (FR-MAC-01 through FR-MAC-10), validation refs (AC-M-01 through AC-M-11), dependencies, descriptions, test deliverables, and SwiftUI preview requirements. All tasks set to `todo`. Status → locked. |
