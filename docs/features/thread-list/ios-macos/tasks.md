---
title: "Thread List — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/thread-list/ios-macos/plan.md
version: "2.1.0"
status: locked
updated: 2026-02-10
---

# Thread List — iOS/macOS Task Breakdown

> Each task references its plan phase, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-06: Domain Layer Extensions

- **Status**: `todo`
- **Plan phase**: Phase 1
- **Spec ref**: Thread List spec FR-TL-01, Foundation FR-FOUND-01
- **Validation ref**: AC-U-13
- **Description**: Extend the domain layer with new error types, Participant model, ThreadPage model, expanded repository protocol, and constants needed by the thread list feature.
- **Deliverables**:
  - [ ] `ThreadListError.swift` — Error enum with cases: `fetchFailed(underlying: Error)`, `actionFailed(underlying: Error)`, `threadNotFound(id: String)`, `folderNotFound(id: String)`
  - [ ] `Participant.swift` — `Codable Sendable` struct with `name: String?`, `email: String`. Static `decode(from jsonString: String?) -> [Participant]` and `encode(_ participants: [Participant]) -> String` methods for JSON parsing of `Thread.participants`
  - [ ] `ThreadPage.swift` — Struct with `threads: [Thread]`, `nextCursor: Date?`, `hasMore: Bool`
  - [ ] `EmailRepositoryProtocol.swift` — Extend with: `getThreads(folderId:category:cursor:limit:)`, `getThreadsUnified(category:cursor:limit:)`, `getOutboxEmails(accountId:)`, `getUnreadCounts(folderId:)`, `getUnreadCountsUnified()`, `archiveThread(id:)`, `deleteThread(id:)`, `moveThread(id:toFolderId:)`, `toggleReadStatus(threadId:)`, `toggleStarStatus(threadId:)`, batch variants: `archiveThreads(ids:)`, `deleteThreads(ids:)`, `markThreadsRead(ids:)`, `markThreadsUnread(ids:)`, `starThreads(ids:)`, `moveThreads(ids:toFolderId:)`
  - [ ] `Constants.swift` — Add `threadListPageSize = 25`
  - [ ] `MockEmailRepository.swift` — In-memory mock implementing full extended protocol with arrays, call counters, and controllable error injection
  - [ ] `ParticipantTests.swift` — Tests: JSON decode valid, decode nil/empty/malformed input, encode round-trip, multi-participant decode

---

### IOS-U-07: FetchThreadsUseCase

- **Status**: `todo`
- **Plan phase**: Phase 2
- **Spec ref**: Thread List spec FR-TL-01, FR-TL-02, FR-TL-04
- **Validation ref**: AC-U-14
- **Description**: Create the read-side use case for paginated thread fetching, category filtering, unread counts, folder listing, and outbox queries. Protocol + `@MainActor` implementation.
- **Deliverables**:
  - [ ] `FetchThreadsUseCaseProtocol` — Protocol with methods: `fetchThreads(accountId:folderId:category:cursor:pageSize:) async throws -> ThreadPage`, `fetchUnifiedThreads(category:cursor:pageSize:) async throws -> ThreadPage`, `fetchUnreadCounts(accountId:folderId:) async throws -> [AICategory?: Int]`, `fetchFolders(accountId:) async throws -> [Folder]`, `fetchOutboxEmails(accountId:) async throws -> [Email]`
  - [ ] `FetchThreadsUseCase` — `@MainActor` implementation delegating to `EmailRepositoryProtocol`
  - [ ] `FetchThreadsUseCaseTests.swift` — Tests: pagination (cursor, hasMore, empty page), category filtering, unified merge (multi-account sorted by latestDate), unread counts, folder fetch, outbox fetch, error propagation

---

### IOS-U-08: ManageThreadActionsUseCase

- **Status**: `todo`
- **Plan phase**: Phase 2
- **Spec ref**: Thread List spec FR-TL-03
- **Validation ref**: AC-U-15
- **Description**: Create the write-side use case for single and batch thread actions. Protocol + `@MainActor` implementation.
- **Deliverables**:
  - [ ] `ManageThreadActionsUseCaseProtocol` — Protocol with methods: `archiveThread(id:)`, `deleteThread(id:)`, `toggleReadStatus(threadId:)`, `toggleStarStatus(threadId:)`, `moveThread(id:toFolderId:)`, batch: `archiveThreads(ids:)`, `deleteThreads(ids:)`, `markThreadsRead(ids:)`, `markThreadsUnread(ids:)`, `starThreads(ids:)`, `moveThreads(ids:toFolderId:)`
  - [ ] `ManageThreadActionsUseCase` — `@MainActor` implementation delegating to `EmailRepositoryProtocol`
  - [ ] `ManageThreadActionsUseCaseTests.swift` — Tests: each single action delegates correctly, each batch action delegates, error propagation for each action type

---

### IOS-U-09: EmailRepositoryImpl (SwiftData)

- **Status**: `todo`
- **Plan phase**: Phase 3
- **Spec ref**: Foundation FR-FOUND-01
- **Validation ref**: AC-U-16
- **Description**: Implement the extended `EmailRepositoryProtocol` using SwiftData queries. Key: 3-step join strategy for Thread↔Folder resolution (Folder→EmailFolder→Email→Thread).
- **Deliverables**:
  - [ ] `EmailRepositoryImpl.swift` — `@MainActor` SwiftData implementation
    - `getThreads(folderId:...)`: 3-step join (fetch EmailFolders → collect threadIds → fetch Threads with filters)
    - `getThreadsUnified(...)`: fetch all threads across accounts with cursor/category/limit
    - `getOutboxEmails(accountId:)`: query Emails by `sendState ∈ {queued, sending, failed}`
    - `getUnreadCounts(folderId:)`: aggregate unread counts per AI category
    - Action methods: update SwiftData models directly (archive = move to Trash folder, delete = move to Trash, toggleRead/Star = flip flags, move = update EmailFolder)
    - Batch variants: loop single actions (acceptable for V1)
  - [ ] `EmailRepositoryImplTests.swift` — Integration tests with in-memory `ModelContainer`: pagination (cursor, hasMore, limit), category filter, unified query, archive/delete mutations verify model state, outbox queries, unread count aggregation

---

### IOS-U-01: iOS Navigation Structure

- **Status**: `todo`
- **Plan phase**: Phase 5
- **Spec ref**: Thread List spec, FR-TL-05
- **Validation ref**: AC-U-01
- **Description**: Set up iOS navigation using NavigationStack with `navigationDestination(for:)` routing. No separate NavigationRouter needed — SwiftUI's built-in path-based navigation is sufficient. MV pattern — no ViewModels.
- **Deliverables**:
  - [ ] Root NavigationStack in `ThreadListView.swift` with thread list as landing screen
  - [ ] `navigationDestination(for:)` for: Email Detail, Folder List
  - [ ] Sheet presentations for: Composer, Account Switcher
  - [ ] Navigation to Settings via toolbar
  - [ ] Placeholder views for Email Detail, Composer, Search (future features)

---

### IOS-U-02: Thread List View

- **Status**: `todo`
- **Plan phase**: Phase 5
- **Spec ref**: Thread List spec, FR-TL-01, FR-TL-02
- **Validation ref**: AC-U-02
- **Description**: Implement the main thread list screen with MV pattern (@State, @Environment, .task). Integrates with FetchThreadsUseCase for data loading.
- **Deliverables**:
  - [ ] `ThreadListView.swift` — List of thread rows with cursor-based pagination (25/page, FR-TL-01)
  - [ ] `CategoryTabBar.swift` — horizontal tab bar (All, Primary, Social, Promotions, Updates) with unread badges (FR-TL-02)
  - [ ] View states: loading, loaded, empty (no threads), empty (filtered), error, offline (FR-TL-01)
  - [ ] AI unavailability fallback: hide category tabs entirely (FR-TL-02)
  - [ ] Automatic next-page loading via `.onAppear` on sentinel row near bottom (FR-TL-01)
  - [ ] Inline error banner with retry for sync/pagination failures
  - [ ] Category tab persistence per folder: in-memory `@State` dictionary `[String: AICategory?]` (not persisted across launches)
  - [ ] Toolbar: compose (trailing), folders (leading), search, account switcher, settings
  - [ ] Wire `ContentView.swift` — replace placeholder with ThreadListView
  - [ ] Wire `VaultMailApp.swift` — create and inject EmailRepositoryImpl + use cases
  - [ ] SwiftUI previews for all view states

---

### IOS-U-03: Thread Row Component

- **Status**: `todo`
- **Plan phase**: Phase 4
- **Spec ref**: Thread List spec, FR-TL-01, NFR-TL-03
- **Validation ref**: AC-U-03
- **Description**: Implement the thread row UI component with full accessibility. Pure view component with no data fetching.
- **Deliverables**:
  - [ ] `ThreadRowView.swift` — sender name(s) with count, subject, snippet, timestamp (FR-TL-01)
  - [ ] `AvatarView.swift` — initials + deterministic color from email hash, stack up to 2 for multi-participant (FR-TL-01). Optional account dot overlay for unified mode
  - [ ] `CategoryBadgeView.swift` — colored pill badge with text label, hidden for uncategorized (FR-TL-01)
  - [ ] `Date+RelativeFormat.swift` — Relative timestamp: "3:42 PM" (today), "Yesterday" (yesterday), "Tue" (this week), "Jan 15" (this year), "1/15/24" (older)
  - [ ] Unread indicator: bold sender + bold subject + blue dot (FR-TL-01)
  - [ ] Star indicator: filled star icon when starred (FR-TL-01)
  - [ ] Attachment indicator: paperclip icon (FR-TL-01)
  - [ ] Dynamic Type support: all text scales, layout adapts at all sizes (NFR-TL-03)
  - [ ] VoiceOver: single coherent accessibilityLabel per row: "From [sender], [subject], [snippet], [time], [unread/read], [starred/not starred]" (NFR-TL-03)
  - [ ] Color independence: unread=bold+dot, star=filled shape, category=text label (NFR-TL-03)
  - [ ] `DateRelativeFormatTests.swift` — Tests: all 5 timestamp buckets, edge cases (midnight, year boundary)
  - [ ] SwiftUI previews for all variant combinations

---

### IOS-U-04: Thread List Interactions

- **Status**: `todo`
- **Plan phase**: Phase 6
- **Spec ref**: Thread List spec, FR-TL-03
- **Validation ref**: AC-U-04
- **Description**: Implement pull-to-refresh, swipe gestures, undo toast, and multi-select with batch actions.
- **Deliverables**:
  - [ ] `UndoToastView.swift` — floating bottom toast: action message + "Undo" button, auto-dismiss after 5s
  - [ ] `MultiSelectToolbar.swift` — bottom toolbar: selected count, Archive, Delete, Mark Read/Unread, Star, Move, Select All/Deselect All
  - [ ] `MoveToFolderSheet.swift` — sheet with folder picker for Move action
  - [ ] Pull-to-refresh via `.refreshable {}` triggering incremental sync (PARTIAL SCOPE: Email Sync FR-SYNC-02 not yet implemented)
  - [ ] Swipe right: archive with optimistic update + 5s undo toast (FR-TL-03 / FR-SYNC-10)
  - [ ] Swipe left: delete with optimistic update + 5s undo toast (FR-TL-03 / FR-SYNC-10)
  - [ ] Swipe left partial: reveal delete + "more" button (Mark Read/Unread, Star, Move)
  - [ ] Undo toast flow: optimistic remove → 5s timer → on expiry: call use case → on undo: re-insert → on failure: re-insert + error toast
  - [ ] Server sync failure → revert UI + error toast with retry (FR-TL-03)
  - [ ] Long-press for multi-select mode with checkboxes (FR-TL-03)
  - [ ] Batch action toolbar with all actions (FR-TL-03)
  - [ ] Select All / Deselect All toggle (FR-TL-03)
  - [ ] Batch partial failure handling: report count, keep failed selected (FR-TL-03)
  - [ ] Reduce Motion: `@Environment(\.accessibilityReduceMotion)` for cross-dissolve swipe animations (NFR-TL-03)

---

### IOS-U-05: Folder Navigation + Outbox

- **Status**: `todo`
- **Plan phase**: Phase 7
- **Spec ref**: Thread List spec, FR-TL-04
- **Validation ref**: AC-U-05
- **Description**: Implement folder list (navigated from toolbar button, not persistent sidebar on iPhone), system folders, custom labels, and virtual Outbox view.
- **Deliverables**:
  - [ ] `FolderListView.swift` — system folders (Inbox, Starred, Sent, Drafts, Spam, Trash, Outbox) with badges (FR-TL-04)
  - [ ] Custom Gmail labels below system folders, sorted alphabetically (FR-TL-04)
  - [ ] `OutboxRowView.swift` — queued/sending/failed emails with send state display (FR-TL-04 / FR-SYNC-07)
  - [ ] Outbox is virtual: computed filter on emails where `sendState ∈ {queued, sending, failed}` (not a FolderType enum value)
  - [ ] Outbox: retry action for failed, cancel for queued (FR-TL-04)
  - [ ] Folder selection updates thread list filter (FR-TL-04)
  - [ ] When Outbox selected: hide category tabs, show OutboxRowView instead of ThreadRowView (FR-TL-04)
  - [ ] Badge shows "—" when count unavailable (FR-TL-04 error handling)

---

### IOS-U-12: Account Switcher

- **Status**: `todo`
- **Plan phase**: Phase 8
- **Spec ref**: Thread List spec, FR-TL-04
- **Validation ref**: AC-U-12
- **Description**: Multi-account navigation and unified inbox. Account indicator uses colored dot from deterministic hash of account id.
- **Deliverables**:
  - [ ] `AccountSwitcherSheet.swift` — sheet with "All Accounts" (unified) row + per-account rows (email, avatar, unread count, checkmark for selected)
  - [ ] Per-account thread list: selecting account switches to that account's Inbox
  - [ ] Unified inbox: all accounts merged, sorted by `latestDate` (uses `fetchUnifiedThreads` from FetchThreadsUseCase)
  - [ ] `AccountIndicatorView.swift` — colored dot per thread in unified view, color derived from deterministic hash of account id
  - [ ] In unified mode: title shows "All Inboxes", folder list hidden (system folders are per-account per spec)
  - [ ] Compose defaults to selected account (or configured default)

---

## Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2026-02-07 | Core Team | Initial task breakdown from plan v1.1.0 |
| 1.1.0 | 2026-02-07 | Core Team | Added deliverable checklists, spec refs, validation refs |
| 2.0.0 | 2026-02-08 | Core Team | Major revision: Added 4 new domain/data layer tasks (IOS-U-06 through IOS-U-09). Removed NavigationRouter.swift from IOS-U-01 (using built-in NavigationStack). Added Participant model, ThreadPage, ThreadListError to IOS-U-06. Added FetchThreadsUseCase (IOS-U-07) and ManageThreadActionsUseCase (IOS-U-08) replacing individual use cases. Added EmailRepositoryImpl (IOS-U-09). Updated IOS-U-02 with category tab persistence detail and ContentView/VaultMailApp wiring. Updated IOS-U-03 with Date+RelativeFormat, DateRelativeFormatTests. Updated IOS-U-04 with UndoToastView, MultiSelectToolbar, MoveToFolderSheet, undo toast flow. Updated IOS-U-05 with FolderListView (toolbar button, not sidebar), virtual outbox detail. Updated IOS-U-12 with AccountIndicatorView, deterministic color dot, unified mode constraints. Status → approved |
