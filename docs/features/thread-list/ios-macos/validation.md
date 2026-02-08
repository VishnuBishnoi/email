---
title: "Thread List — iOS/macOS Validation"
spec-ref: docs/features/thread-list/spec.md
plan-refs:
  - docs/features/thread-list/ios-macos/plan.md
  - docs/features/thread-list/ios-macos/tasks.md
version: "2.0.0"
status: approved
last-validated: null
updated: 2026-02-08
---

# Thread List — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-TL-01 | Thread display + pagination | MUST | AC-U-02, AC-U-03, AC-U-13, AC-U-14, AC-U-16 | Both | — |
| FR-TL-02 | Category filtering | MUST | AC-U-02, AC-U-14 | Both | — |
| FR-TL-03 | Gestures and interactions | MUST | AC-U-04, AC-U-15 | Both | — |
| FR-TL-04 | Folder + account navigation | MUST | AC-U-05, AC-U-12, AC-U-14 | Both | — |
| FR-TL-05 | Navigation flows | MUST | AC-U-01 | Both | — |
| FR-FOUND-01 | Views call use cases, not repos | MUST | AC-U-13, AC-U-14, AC-U-15, AC-U-16 | Both | — |
| NFR-TL-01 | Scroll performance (60 fps) | MUST | PERF-01 | Both | — |
| NFR-TL-02 | List load time (< 200ms) | MUST | PERF-02 | Both | — |
| NFR-TL-03 | Accessibility (WCAG 2.1 AA) | MUST | AC-U-06 | Both | — |
| NFR-TL-04 | Memory (≤ 50MB above baseline) | MUST | PERF-03 | Both | — |
| G-02 | Multiple Gmail accounts | MUST | AC-U-12 | Both | — |
| G-03 | Threaded conversation view | MUST | AC-U-02 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-13**: Domain Layer Extensions (IOS-U-06)

- **Given**: The domain layer needs error types, participant parsing, and repository extensions for the thread list
- **When**: Domain layer code is compiled and tested
- **Then**: `ThreadListError` **MUST** have cases: `fetchFailed(underlying:)`, `actionFailed(underlying:)`, `threadNotFound(id:)`, `folderNotFound(id:)`
  AND `Participant` **MUST** be a `Codable Sendable` struct with `name: String?` and `email: String`
  AND `Participant.decode(from:)` **MUST** parse valid JSON into `[Participant]` array
  AND `Participant.decode(from:)` **MUST** return empty array for nil, empty string, or malformed JSON
  AND `Participant.encode(_:)` **MUST** produce valid JSON round-trippable with `decode(from:)`
  AND `ThreadPage` **MUST** have `threads: [Thread]`, `nextCursor: Date?`, `hasMore: Bool`
  AND `EmailRepositoryProtocol` **MUST** include all new method signatures (paginated queries, actions, batch ops)
  AND `AppConstants.threadListPageSize` **MUST** equal `25`
  AND `MockEmailRepository` **MUST** implement the full extended protocol with controllable error injection
- **Priority**: Critical

---

**AC-U-14**: FetchThreadsUseCase (IOS-U-07)

- **Given**: A mock email repository with test data
- **When**: FetchThreadsUseCase methods are called
- **Then**: `fetchThreads(accountId:folderId:category:cursor:pageSize:)` **MUST** return a `ThreadPage` with correct threads, cursor, and hasMore flag
  AND pagination **MUST** work: first page returns threads sorted by `latestDate` DESC; subsequent pages use cursor to fetch older threads
  AND empty results **MUST** return `ThreadPage(threads: [], nextCursor: nil, hasMore: false)`
  AND category filtering **MUST** return only threads matching the specified `AICategory`
  AND `fetchUnifiedThreads(...)` **MUST** merge threads from all accounts sorted by `latestDate`
  AND `fetchUnreadCounts(...)` **MUST** return a dictionary of `[AICategory?: Int]` with correct counts
  AND `fetchFolders(...)` **MUST** return all folders for the account
  AND `fetchOutboxEmails(...)` **MUST** return only emails with `sendState ∈ {queued, sending, failed}`
  AND all methods **MUST** propagate repository errors as `ThreadListError`
- **Priority**: Critical

---

**AC-U-15**: ManageThreadActionsUseCase (IOS-U-08)

- **Given**: A mock email repository
- **When**: ManageThreadActionsUseCase methods are called
- **Then**: `archiveThread(id:)` **MUST** delegate to `repository.archiveThread(id:)`
  AND `deleteThread(id:)` **MUST** delegate to `repository.deleteThread(id:)`
  AND `toggleReadStatus(threadId:)` **MUST** delegate to `repository.toggleReadStatus(threadId:)`
  AND `toggleStarStatus(threadId:)` **MUST** delegate to `repository.toggleStarStatus(threadId:)`
  AND `moveThread(id:toFolderId:)` **MUST** delegate to `repository.moveThread(id:toFolderId:)`
  AND batch variants (`archiveThreads`, `deleteThreads`, `markThreadsRead`, `markThreadsUnread`, `starThreads`, `moveThreads`) **MUST** delegate to corresponding batch repository methods
  AND all methods **MUST** propagate repository errors as `ThreadListError`
- **Priority**: High

---

**AC-U-16**: EmailRepositoryImpl (IOS-U-09)

- **Given**: An in-memory SwiftData `ModelContainer` with test data (threads, emails, folders, email-folders)
- **When**: EmailRepositoryImpl methods are called
- **Then**: `getThreads(folderId:...)` **MUST** resolve threads via 3-step join (Folder→EmailFolder→Email→Thread)
  AND pagination **MUST** return correct pages: first 25 by `latestDate` DESC, subsequent pages via cursor
  AND `hasMore` **MUST** be `true` when more threads exist beyond the page limit
  AND category filter **MUST** exclude threads not matching the specified category
  AND `getThreadsUnified(...)` **MUST** return threads across all accounts
  AND `getOutboxEmails(...)` **MUST** return only emails with `sendState ∈ {queued, sending, failed}`
  AND `getUnreadCounts(...)` **MUST** return correct per-category unread counts
  AND `archiveThread(id:)` **MUST** update the thread's folder association to Trash
  AND `toggleReadStatus(threadId:)` **MUST** flip the unread count appropriately
  AND `toggleStarStatus(threadId:)` **MUST** flip `isStarred`
  AND `moveThread(id:toFolderId:)` **MUST** update EmailFolder entries
- **Priority**: Critical

---

**AC-U-01**: iOS Navigation

- **Given**: The app is launched on iOS with at least one account
- **When**: The user navigates between screens
- **Then**: Thread list **MUST** be the root view inside a NavigationStack
  AND tapping a thread **MUST** push the email detail view (placeholder in V1)
  AND tapping compose **MUST** present the composer as a sheet (placeholder in V1)
  AND tapping search **MUST** present the search view (placeholder in V1)
  AND tapping settings **MUST** push or present the settings view
  AND tapping the folder toolbar button **MUST** navigate to the folder list
  AND tapping a folder in the folder list **MUST** update the thread list for that folder
  AND back navigation **MUST** work consistently
  AND no separate NavigationRouter file exists — navigation uses built-in NavigationStack
- **Priority**: Critical

---

**AC-U-02**: Thread List

- **Given**: An account with synced emails
- **When**: The thread list is displayed
- **Then**: Threads **MUST** be sorted by most recent message date (newest first)
  AND each row **MUST** display: sender name, subject, snippet, timestamp, unread indicator, star indicator, attachment indicator
  AND category tabs **MUST** filter threads by AI category (hidden when AI unavailable)
  AND each category tab **MUST** show an unread badge count when > 0
  AND the list **MUST** paginate in pages of 25, auto-loading on scroll via sentinel row `.onAppear`
  AND the list **MUST** scroll at 60fps with no visible jank
  AND the view **MUST** show appropriate states: loading, empty, error, offline
  AND empty state **MUST** display an appropriate message
  AND category tab selection **MUST** persist per folder within a session (in-memory, not across launches)
  AND toolbar **MUST** include: compose (trailing), folders (leading), search, account, settings
- **Priority**: Critical

---

**AC-U-03**: Thread Row

- **Given**: A thread with known properties (unread, starred, has attachment, categorized)
- **When**: The thread row is rendered
- **Then**: Unread threads **MUST** display bold sender name, bold subject, and a blue dot indicator
  AND starred threads **MUST** display a filled star icon
  AND threads with attachments **MUST** display a paperclip icon
  AND the category badge **MUST** show the correct category text in a colored pill (hidden for uncategorized)
  AND the timestamp **MUST** display relative time: "3:42 PM" (today), "Yesterday", "Tue" (this week), "Jan 15" (this year), "1/15/24" (older)
  AND multi-participant threads **MUST** show count suffix (e.g., "John, Sarah (3)")
  AND avatar **MUST** use initials with deterministic color derived from email hash
  AND multi-participant threads **MUST** stack up to 2 avatars
  AND VoiceOver **MUST** announce all visible information as a single coherent label
  AND all text **MUST** scale correctly with Dynamic Type at all sizes
- **Priority**: High

---

**AC-U-04**: Thread List Interactions

- **Given**: The thread list is displayed
- **When**: The user performs gestures
- **Then**: Pull-to-refresh **MUST** trigger a sync operation (PARTIAL SCOPE: stubbed until Email Sync available)
  AND swipe right on a thread **MUST** archive it with a 5-second undo toast
  AND swipe left on a thread **MUST** delete it (move to Trash) with a 5-second undo toast
  AND partial swipe left **MUST** reveal delete + "more" actions (Mark Read/Unread, Star, Move)
  AND undo toast flow: optimistic remove → 5s timer → on expiry: call use case → on undo: re-insert at original index → on failure: re-insert + error toast
  AND long-press **MUST** enter multi-select mode with checkboxes
  AND in multi-select mode, batch archive/delete/mark-read/mark-unread/star/move **MUST** work on all selected threads
  AND Select All/Deselect All toggle **MUST** be available in multi-select mode
  AND if a swipe action fails on server, the UI **MUST** revert and show an error toast with retry
  AND if a batch action partially fails, the failure count **MUST** be reported and failed threads **MUST** remain selected
  AND with Reduce Motion enabled, swipe animations **SHOULD** use cross-dissolve
- **Priority**: High

---

**AC-U-05**: Folder Navigation + Outbox

- **Given**: An account with synced folders and queued outbox emails
- **When**: The user navigates folders
- **Then**: System folders **MUST** be displayed: Inbox, Starred, Sent, Drafts, Spam, Trash, Outbox
  AND each folder **MUST** show appropriate badge count (unread for Inbox/Spam, draft count for Drafts, queued+failed for Outbox)
  AND custom Gmail labels **MUST** appear below system folders, sorted alphabetically
  AND selecting a folder **MUST** update the thread list to show that folder's threads
  AND folder access on iOS **MUST** be via toolbar leading button navigating to FolderListView (not persistent sidebar)
  AND Outbox **MUST** be virtual: computed filter on `sendState ∈ {queued, sending, failed}`, not a FolderType enum
  AND Outbox **MUST** display queued/sending/failed emails with send state
  AND failed Outbox items **MUST** allow retry; queued items **MUST** allow cancel
  AND when Outbox is selected, category tabs **MUST** be hidden
  AND badge **MUST** show "—" when count unavailable
- **Priority**: High

---

**AC-U-06**: Accessibility

- **Given**: The thread list is displayed with VoiceOver enabled and/or large Dynamic Type
- **When**: The user interacts via VoiceOver or uses large text sizes
- **Then**: Every thread row **MUST** have a single, coherent accessibility label announcing: sender, subject, snippet, time, and status indicators (format: "From [sender], [subject], [snippet], [time], [unread/read], [starred/not starred]")
  AND all text **MUST** scale from extra small to accessibility 5 (xxxLarge) without clipping or layout breaks
  AND contrast ratios **MUST** meet 4.5:1 for normal text, 3:1 for large text/icons
  AND unread indicator **MUST** use bold font weight + blue dot (not color alone)
  AND star indicator **MUST** use filled star shape (not color alone)
  AND category indicator **MUST** use text label inside badge (not color alone)
  AND swipe actions **MUST** be accessible via VoiceOver custom actions
  AND if "Reduce Motion" is enabled, swipe animations **SHOULD** use cross-dissolve
- **Priority**: High

---

**AC-U-12**: Multi-Account

- **Given**: Two Gmail accounts are configured
- **When**: The user navigates the app
- **Then**: The account switcher **MUST** be presented as a sheet from the account avatar in the navigation bar
  AND the switcher **MUST** list both accounts with email, avatar, and unread count
  AND an "All Accounts" (unified) row **MUST** be available
  AND selecting an account **MUST** show that account's Inbox
  AND selecting "All Accounts" **MUST** show threads from all accounts merged by `latestDate`
  AND threads in unified view **MUST** indicate which account they belong to via colored dot (deterministic hash of account ID)
  AND in unified mode, title **MUST** show "All Inboxes" and folder list **MUST** be hidden (system folders are per-account)
  AND composing a new email **MUST** default to the selected account (or the configured default)
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-01 | Empty inbox (new account, no emails) | Empty state with illustration + "No emails" message + pull-to-refresh hint |
| E-02 | AI categorization unavailable | Category tab bar hidden; all threads in single list |
| E-03 | Thread list with 500+ threads | LazyVStack pagination; scroll at 60fps; memory ≤ 50MB above baseline |
| E-04 | Swipe archive fails (server error) | UI reverts; error toast "Couldn't archive. Tap to retry." |
| E-05 | Network offline while viewing thread list | "You're offline" banner; cached data shown; pull-to-refresh disabled |
| E-06 | Unified inbox with 3+ accounts | All threads merged by date; each shows account indicator (colored dot); no duplicates |
| E-07 | Dynamic Type at accessibility xxxLarge | Layout adapts; no text clipping; sender name and snippet truncate gracefully |
| E-08 | Outbox with mix of queued/sending/failed | Each shows correct state; failed shows retry; queued shows cancel |
| E-09 | Participant JSON malformed or nil | `Participant.decode(from:)` returns empty array; thread row shows "Unknown" sender |
| E-10 | Thread in folder resolved via 3-step join returns no threads | Thread list shows empty state for that folder |
| E-11 | Undo toast: user taps undo at exactly 5s | Timer cancelled, thread re-inserted; action not persisted |
| E-12 | Multi-select batch action: 5 of 10 threads fail | Error reports "5 actions failed"; failed threads remain selected for retry |
| E-13 | Category tab selected then folder switched | Tab selection persists per folder in memory; returning to folder restores previous tab |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Thread list scroll FPS | 60 fps | 30 fps | Instruments Core Animation on iPhone SE 3rd gen with 500+ threads | Fails if drops below 30fps for >1s |
| List load time (cached) | < 200ms | 500ms | Time from `onAppear` to first rendered frame | Fails if > 500ms on 3 runs |
| Memory (500+ threads) | ≤ 50MB | 100MB | Xcode Memory Debugger after scrolling 500 threads | Fails if > 100MB above baseline |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix.

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
| 1.0.0 | 2026-02-07 | Core Team | Initial validation from spec v1.2.0 |
| 1.1.0 | 2026-02-07 | Core Team | Added traceability matrix, acceptance criteria, edge cases, performance validation |
| 2.0.0 | 2026-02-08 | Core Team | Major revision: Added 4 new acceptance criteria (AC-U-13 through AC-U-16) for domain layer extensions, use cases, and repository implementation. Updated traceability matrix with FR-FOUND-01 cross-references. Updated AC-U-01 to specify no NavigationRouter, built-in NavigationStack. Updated AC-U-02 with category tab persistence and toolbar details. Updated AC-U-03 with relative timestamp format details and avatar deterministic color. Updated AC-U-04 with undo toast flow detail, multi-select toolbar, partial failure handling. Updated AC-U-05 with virtual outbox detail, toolbar folder access. Updated AC-U-12 with colored dot indicator, unified mode title, sheet presentation. Added 5 new edge cases (E-09 through E-13). Status → approved |
