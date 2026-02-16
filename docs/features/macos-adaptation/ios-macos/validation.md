---
title: "macOS Adaptation — Validation: Acceptance Criteria & Test Plan"
spec-ref: docs/features/macos-adaptation/spec.md
plan-refs:
  - docs/features/macos-adaptation/ios-macos/plan.md
  - docs/features/macos-adaptation/ios-macos/tasks.md
version: "2.0.0"
status: locked
last-validated: 2026-02-12
updated: 2026-02-12
---

# macOS Adaptation — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-MAC-01 | Three-pane NavigationSplitView layout | MUST | AC-M-01, AC-M-02 | macOS | — |
| FR-MAC-02 | Sidebar — folder and account navigation | MUST | AC-M-03 | macOS | — |
| FR-MAC-03 | macOS toolbar with action buttons + search | MUST | AC-M-09 | macOS | — |
| FR-MAC-04 | Thread list in content column | MUST | AC-M-04 | macOS | — |
| FR-MAC-05 | macOS thread interactions (context menu, multi-select) | MUST | AC-M-05 | macOS | — |
| FR-MAC-06 | Email detail with NSViewRepresentable HTML | MUST | AC-M-06 | macOS | — |
| FR-MAC-07 | Keyboard shortcuts + menu bar commands | MUST | AC-M-08 | macOS | — |
| FR-MAC-08 | Multi-window compose support | MUST | AC-M-07 | macOS | — |
| FR-MAC-09 | macOS attachment handling (drag-drop, fileImporter) | MUST | AC-M-10 | macOS | — |
| FR-MAC-10 | Window configuration (sizing, resizability) | MUST | AC-M-01 | macOS | — |
| NFR-MAC-01 | Window responsiveness (< 500ms) | MUST | PERF-M-01 | macOS | — |
| NFR-MAC-02 | Column resize performance (60 fps) | MUST | PERF-M-02 | macOS | — |
| NFR-MAC-03 | Keyboard shortcut latency (< 100ms local) | MUST | PERF-M-03 | macOS | — |
| NFR-MAC-04 | Accessibility (WCAG 2.1 AA, VoiceOver, Full Keyboard Access) | MUST | AC-M-12 | macOS | — |
| NFR-MAC-05 | Memory (≤ 150MB above baseline) | MUST | PERF-M-04 | macOS | — |
| G-06 | iOS and native macOS | MUST | AC-M-01 through AC-M-12 | macOS | — |

---

## 2. Acceptance Criteria

---

**AC-M-01**: macOS Build & Window Configuration (IOS-M-01)

- **Given**: The macOS target is configured with correct scene setup
- **When**: The project is built and run on macOS 15+
- **Then**: The app **MUST** launch as a native macOS application
  AND it **MUST** display in a resizable window with default size 1200×800pt
  AND the minimum window size **MUST** be 800×600pt (enforced via `.windowResizability(.contentMinSize)`)
  AND the window title **MUST** display the app name
  AND `⌘,` **MUST** open the Settings window
  AND `⌘Q` **MUST** quit the application
  AND `⌘W` **MUST** close the current window
  AND the iOS `ContentView` / `NavigationStack` / `BottomTabBar` **MUST NOT** be affected by macOS platform conditionals
- **Priority**: Critical

---

**AC-M-02**: Three-Pane Layout (IOS-M-02)

- **Given**: The macOS app is running with at least one configured account
- **When**: The main window is displayed
- **Then**: The app **MUST** use `NavigationSplitView` with three columns as the root navigation container
  AND the sidebar column **MUST** have minimum 180pt and ideal 220pt width
  AND the content column **MUST** have minimum 280pt and ideal 340pt width
  AND the detail column **MUST** have minimum 400pt width and fill remaining space
  AND all three panes **MUST** be visible simultaneously at default window size
  AND clicking the sidebar toggle **MUST** collapse/expand the sidebar
  AND when the sidebar is collapsed, content and detail columns **MUST** expand to fill available space
  AND column visibility state **SHOULD** persist across app launches via `@SceneStorage`
  AND the `BottomTabBar` **MUST NOT** render on macOS
  AND the iOS `NavigationStack` root container **MUST NOT** be used on macOS

  Empty states:
  AND with no account configured, a full-window onboarding flow **MUST** display (no split view)
  AND with no folder selected, the content column **MUST** show "Select a folder" placeholder
  AND with no thread selected, the detail column **MUST** show `ContentUnavailableView` with "No Conversation Selected"
  AND with an empty folder, the content column **MUST** show "No emails in [Folder Name]"
  AND if state restoration fails, the app **MUST** fall back to default column visibility without crashing
- **Priority**: Critical

---

**AC-M-03**: Sidebar — Folder and Account Navigation (IOS-M-03)

- **Given**: The macOS app is running with two configured accounts
- **When**: The user interacts with the sidebar
- **Then**: The sidebar **MUST** use `.listStyle(.sidebar)` for native macOS appearance
  AND the sidebar **MUST NOT** use `.listStyle(.insetGrouped)` or `.listStyle(.plain)`
  AND each account **MUST** be displayed as an expandable section with email address
  AND clicking an account header **MUST** expand/collapse its folder tree
  AND the currently active account **MUST** be visually distinguished (bold or highlight)
  AND system folders **MUST** appear in fixed order: Inbox, Starred, Sent, Drafts, Spam, Trash, Archive
  AND the Outbox virtual folder **MUST** appear after Archive
  AND custom Gmail labels **MUST** appear in a "Labels" section below system folders, sorted alphabetically
  AND each folder **MUST** display an unread badge count when `unreadCount > 0`
  AND Drafts **MUST** display draft count as badge
  AND Outbox **MUST** display queued + failed count as badge
  AND badge **MUST** show "—" when count unavailable
  AND selecting a folder **MUST** update the content column (thread list) immediately
  AND the selected folder **MUST** be highlighted with standard macOS sidebar selection style
  AND selecting a folder **MUST** reset thread list to page 1 and "All" category tab
  AND a "Unified Inbox" entry **MUST** be available
  AND selecting "Unified Inbox" **MUST** show merged threads from all accounts sorted by `latestDate`
  AND in Unified Inbox mode, per-account folder trees **SHOULD** be greyed out
  AND user **MUST** select a specific account to navigate non-Inbox folders in unified mode
  AND if folder list fails to load, the account section **MUST** show "Unable to load folders" with "Retry" button
- **Priority**: Critical

---

**AC-M-04**: Thread List in Content Column (IOS-M-04)

- **Given**: A folder is selected in the sidebar with synced threads
- **When**: The thread list is displayed in the content column
- **Then**: Threads **MUST** be sorted by most recent message date (newest first)
  AND each row **MUST** display: sender avatar, sender name, subject, snippet, timestamp, unread indicator, star indicator, attachment indicator, AI category badge (reusing shared `ThreadRowView`)
  AND single-click on a thread **MUST** select it and show email detail in the detail column
  AND single-click **MUST NOT** push a new navigation view
  AND the selected thread **MUST** be highlighted with standard macOS list selection style
  AND selection state **MUST** be managed via `@State`/`@Binding` bound to `NavigationSplitView` `selection` — not `NavigationPath`
  AND category tabs (All, Primary, Social, Promotions, Updates) **MUST** be displayed as segmented control or pill bar above the thread list within the content column
  AND category filtering **MUST** match Thread List FR-TL-02 (local filter, instant switch)
  AND if AI is unavailable, category tabs **MUST** be hidden entirely
  AND pagination **MUST** be cursor-based, 25/page, with infinite scroll via sentinel row `.onAppear`
  AND the list **MUST** display correct view states: Loading, Loaded, Empty, Empty Filtered, Error, Offline
- **Priority**: Critical

---

**AC-M-05**: Thread Interactions — macOS (IOS-M-04)

- **Given**: The thread list is displayed in the content column
- **When**: The user interacts with threads via mouse and keyboard
- **Then**: Right-click on a thread **MUST** present a context menu with: Reply, Reply All, Forward, separator, Archive, Delete, Move to Folder…, separator, Mark as Read/Unread, Star/Unstar
  AND `⌘`-click **MUST** toggle individual thread selection (add/remove from multi-selection)
  AND `⇧`-click **MUST** select a contiguous range from last selected to clicked thread
  AND when multiple threads are selected, the detail column **SHOULD** show "[N] conversations selected" with batch action buttons
  AND toolbar actions **MUST** apply to all selected threads as batch in multi-select mode
  AND right-click context menu **MUST** apply to all selected threads in multi-select mode
  AND `Escape` key **MUST** clear multi-selection
  AND batch action errors **MUST** report failure count and keep failed threads selected for retry
  AND trackpad swipe gestures for archive/delete are **OPTIONAL** in V1
- **Priority**: High

---

**AC-M-06**: Email Detail in Detail Column (IOS-M-05)

- **Given**: A thread is selected in the content column
- **When**: The email detail is displayed in the detail column
- **Then**: HTML email content **MUST** be rendered via `WKWebView` using `NSViewRepresentable` on macOS
  AND the macOS HTML renderer **MUST** be a separate file from the iOS `UIViewRepresentable` wrapper
  AND HTML sanitization (disabled JavaScript, non-persistent data store, blocked remote content, tracking pixel stripping, link safety) **MUST** use shared logic — no duplication between platforms
  AND links **MUST** display destination URL on hover (tooltip or status bar)
  AND Reply, Reply All, Forward buttons **MUST** be accessible from the detail column header or toolbar
  AND after archive/delete, the detail column **MUST** show the next thread or "No Conversation Selected" placeholder
  AND attachment preview **MUST** use macOS Quick Look (`.quickLookPreview()` or `QLPreviewPanel`)
  AND attachment sharing **MUST** use `NSSharingServicePicker` (not `UIActivityViewController`)
  AND keyboard navigation within thread: `↑`/`↓` **MUST** navigate messages, `⏎` **MUST** expand/collapse, `⌘R` **MUST** reply, `⌘⇧R` **MUST** reply all, `⌘⇧E` **MUST** forward
  AND error handling **MUST** match Email Detail FR-ED-01 (view states, mark-as-read revert, action revert with toast)
- **Priority**: Critical

---

**AC-M-07**: Multi-Window Compose (IOS-M-06)

- **Given**: The user triggers compose on macOS
- **When**: `⌘N` is pressed or the compose button is clicked
- **Then**: A composer **MUST** open as a sheet within the main window (default mode, consistent with iOS)
  AND an "Open in Window" button **MUST** be available in the composer toolbar
  AND clicking "Open in Window" **MUST** open the composer in a separate macOS window
  AND the compose window **SHOULD** have default size 600×500pt and **SHOULD** be resizable
  AND multiple compose windows **MAY** be open simultaneously
  AND the composer **MUST** have full functionality: recipients, subject, body, attachments (identical to iOS)
  AND closing a composer with unsaved content **MUST** prompt "Save as Draft?" with Save, Discard, Cancel
  AND compose **MUST** default to the selected account (or configured default)
  AND if the compose window fails to open, the composer **MUST** fall back to sheet presentation
- **Priority**: High

---

**AC-M-08**: Keyboard Shortcuts + Menu Bar (IOS-M-07)

- **Given**: The macOS app is focused
- **When**: Keyboard shortcuts are pressed
- **Then**: `⌘N` **MUST** open a new composer
  AND `⌘F` **MUST** focus the search field
  AND `⌘⌫` **MUST** delete the selected thread(s)
  AND `⌘⇧A` **MUST** archive the selected thread(s)
  AND `⌘⇧U` **MUST** toggle read/unread on selected thread(s)
  AND `⌘⇧L` **MUST** toggle star on selected thread(s)
  AND `⌘⇧M` **MUST** present Move to Folder for selected thread(s)
  AND `⌘R` **MUST** reply to the selected thread
  AND `⌘⇧R` **MUST** reply all
  AND `⌘⇧E` **MUST** forward
  AND `⌃⇧R` **MUST** trigger sync/refresh
  AND `⌘⌥S` **MUST** toggle sidebar visibility
  AND `↑`/`↓` **MUST** navigate threads in the list when thread list is focused
  AND `⏎` **MUST** open/show the selected thread in the detail column
  AND `⌥⌘N` **MUST** navigate to the next unread thread
  AND `Space` **MUST** scroll the email detail when detail is focused
  AND all shortcuts **MUST** appear in the menu bar under File, Edit, Message, and View menus
  AND thread-dependent shortcuts **MUST** be disabled when no thread is selected
  AND keyboard-triggered action failures **MUST** show toast with retry (same as toolbar/menu actions)
- **Priority**: High

---

**AC-M-09**: macOS Toolbar (IOS-M-08)

- **Given**: The macOS app is displaying the three-pane layout
- **When**: The user interacts with the toolbar
- **Then**: The toolbar **MUST** include: Compose (`.primaryAction`), Delete, Archive, Move, Star, Mark Read/Unread (`.secondaryAction`), Sync (`.secondaryAction`), Search (`.automatic`), Sidebar Toggle (`.navigation`)
  AND Compose **MUST** use `square.and.pencil` icon and always be enabled
  AND Delete **MUST** use `trash` icon, enabled only when thread(s) selected
  AND Archive **MUST** use `archivebox` icon, enabled only when thread(s) selected
  AND Move **MUST** use `folder` icon, presents folder picker sheet when clicked
  AND Star toggle **MUST** switch between `star` and `star.fill` based on thread state
  AND Read/Unread toggle **MUST** switch between `envelope` and `envelope.open` based on thread state
  AND Sync **MUST** use `arrow.clockwise` icon and always be enabled
  AND the search field **MUST** be inline via `.searchable` with 300ms debounce
  AND search results **MUST** replace thread list in content column; `Escape` restores folder view
  AND in multi-select mode, toolbar actions **MUST** apply to all selected threads as batch
  AND toolbar action failures **MUST** revert optimistic update and show "Couldn't [action]. Click to retry." error toast
- **Priority**: High

---

**AC-M-10**: macOS Attachment Handling (IOS-M-09)

- **Given**: The user is composing an email or viewing attachments on macOS
- **When**: The user picks, drops, or shares files
- **Then**: File selection **MUST** use `fileImporter` or `NSOpenPanel` — **MUST NOT** use `UIDocumentPickerViewController` or `PhotosUI.PhotosPicker`
  AND file picker **MUST** support selecting multiple files
  AND dragging files onto the composer attachment area or body **MUST** add them as attachments
  AND downloaded attachments in email detail **MUST** be draggable to Finder or other apps
  AND attachment sharing **MUST** use `NSSharingServicePicker` (not `UIActivityViewController`)
  AND `UIDocumentPickerViewController`, `PhotosUI.PhotosPicker`, and `UIActivityViewController` **MUST** be guarded with `#if os(iOS)`
- **Priority**: Medium

---

**AC-M-11**: macOS Settings (IOS-M-10)

- **Given**: The macOS app is running
- **When**: The user presses `⌘,` or selects Settings from the app menu
- **Then**: The Settings window **MUST** open as a native macOS Settings scene
  AND all existing settings fields **MUST** render correctly
  AND if multiple settings sections exist, the layout **SHOULD** use tab-based navigation (macOS convention)
  AND closing the Settings window **MUST NOT** affect the main window state
- **Priority**: Low

---

**AC-M-12**: macOS Accessibility

- **Given**: The macOS app is running with VoiceOver enabled or Full Keyboard Access active
- **When**: The user navigates the app
- **Then**: All three columns **MUST** be navigable via VoiceOver with appropriate labels
  AND sidebar folders **MUST** be individually accessible with labels including folder name and unread count
  AND thread rows **MUST** each have a coherent accessibility label (sender, subject, snippet, time, status)
  AND email messages in the detail column **MUST** be individually accessible
  AND the entire app **MUST** be operable using keyboard only (Tab moves focus between columns, arrows within columns, Enter to select)
  AND all UI elements **MUST** meet WCAG 2.1 AA contrast ratios (4.5:1 normal text, 3:1 large text/icons)
  AND text **MUST NOT** clip or break at any standard macOS font size setting
  AND column transitions and animations **SHOULD** respect "Reduce Motion" accessibility preference
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-M-01 | Window resized below 800×600 minimum | Window **MUST** not resize smaller than 800×600; `.contentMinSize` enforces this |
| E-M-02 | Window resized very narrow (near minimum) | `NavigationSplitView` may collapse to fewer columns; app **MUST NOT** crash or clip content |
| E-M-03 | Sidebar toggle while search is active | Sidebar collapses; search results remain visible in content column |
| E-M-04 | Right-click on thread during multi-select | Context menu applies to all selected threads, not just right-clicked thread |
| E-M-05 | ⌘-click deselects last selected thread in multi-select | Selection clears entirely; detail shows "No Conversation Selected" |
| E-M-06 | ⇧-click with no prior selection | Single thread selected (range of 1) |
| E-M-07 | Thread deleted while selected | Detail column shows next thread in list or "No Conversation Selected" |
| E-M-08 | All accounts removed while app running | Sidebar shows empty state; content column shows "No accounts configured" |
| E-M-09 | Compose window open when main window closes | Compose window remains open (independent window lifecycle) |
| E-M-10 | Multiple compose windows with unsaved content, ⌘Q pressed | Each compose window **MUST** individually prompt "Save as Draft?" |
| E-M-11 | Network offline while browsing folders | Cached data shown; sync button shows error state; "Offline" banner in content column |
| E-M-12 | HTML email rendering fails on macOS WKWebView | Fallback to plain text rendering; error **MUST NOT** crash the app |
| E-M-13 | Drag-and-drop file onto composer with no compose active | Drop should be ignored gracefully (no crash, no orphaned attachment) |
| E-M-14 | Unified Inbox with 0 accounts configured | "No accounts" state displayed; Unified Inbox row **SHOULD** be hidden |
| E-M-15 | Column visibility state corrupted in @SceneStorage | App **MUST** fall back to default three-column visibility without crash |
| E-M-16 | Keyboard shortcut ⌘⌫ pressed with no thread selected | Action **MUST** be disabled (no-op); menu item greyed out |
| E-M-17 | Search field focused, then Escape pressed | Search dismissed; previous folder view restored in content column |
| E-M-18 | Batch archive of 10 threads, 3 fail | Error toast: "3 actions failed"; 3 failed threads remain selected; 7 archived threads removed from list |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Window responsiveness (NFR-MAC-01) | < 500ms | 1s | Time from `WindowGroup` scene activation to first thread row visible with sidebar and detail rendered. Measured with ≥1 cached thread in SwiftData. First-launch excluded. | Fails if > 1s on 3 runs |
| Column resize FPS (NFR-MAC-02) | 60 fps | 30 fps | Instruments Core Animation profiling while resizing sidebar/content divider with 500+ threads loaded | Fails if drops below 30 fps for >1s |
| Keyboard shortcut latency (NFR-MAC-03) | < 100ms (local), < 300ms (data reload) | 500ms | Profiler from key event to UI update completion | Fails if > 500ms on any action |
| Memory (NFR-MAC-05) | ≤ 150MB above baseline | 300MB | Xcode Memory Debugger after navigating through 50 threads in detail pane with HTML rendering active | Fails if > 300MB above baseline |

---

## 5. Device Test Matrix

| Device | OS | Role |
|--------|-----|------|
| MacBook Air M1 (8GB) | macOS 15 | Min-spec Mac validation, memory constraint testing |
| MacBook Pro M3 (18GB) | macOS 15 | Reference Mac, multi-window performance |
| Mac mini M2 (16GB) with external display | macOS 15 | Large window / multi-monitor testing |

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |

---

## 7. Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2026-02-10 | Core Team | Initial validation — 5 thin acceptance criteria (AC-M-01 through AC-M-05) |
| 1.1.0 | 2026-02-11 | Core Team | Added traceability matrix, device test matrix |
| 2.0.0 | 2026-02-12 | Core Team | Full rewrite to match locked spec v1.2.0. Expanded to 12 acceptance criteria (AC-M-01 through AC-M-12) covering all 10 FRs and 5 NFRs. Full traceability matrix against FR-MAC-01–10 and NFR-MAC-01–05. Updated device matrix to macOS 15 (was macOS 14). Added 18 edge cases (E-M-01 through E-M-18). Added performance validation table with 4 metrics matching NFRs. Added Mac mini to device matrix for large window testing. Added accessibility acceptance criterion (AC-M-12) for VoiceOver, Full Keyboard Access, WCAG 2.1 AA. Status → locked. |
