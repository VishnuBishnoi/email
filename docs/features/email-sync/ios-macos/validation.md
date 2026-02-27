---
title: "Email Sync — iOS/macOS Validation"
spec-ref: docs/features/email-sync/spec.md
plan-refs:
  - docs/features/email-sync/ios-macos/plan.md
  - docs/features/email-sync/ios-macos/tasks.md
version: "1.3.0"
status: locked
last-validated: 2026-02-27
---

# Email Sync — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SYNC-01 | Initial bootstrap sync + background catch-up | MUST | AC-F-06, AC-F-06c, AC-F-06f | Both | **Planned (v1.3.0 delta)** — staged first render (30 Inbox headers), background budgeted folder sync, on-scroll older-mail paging |
| FR-SYNC-02 | Dual-direction sync (forward incremental + backward catch-up) | MUST | AC-F-06b, AC-F-06f | Both | **Planned (v1.3.0 delta)** — dual cursors (`forwardCursorUID`, `backfillCursorUID`) replace single checkpoint behavior |
| FR-SYNC-03 | Real-time updates (IDLE) | MUST | AC-F-05, AC-F-06d | Both | **Partially implemented** — IDLE exists today; overlap coordination with catch-up is pending |
| FR-SYNC-05 | Conflict resolution | MUST | AC-F-06 | Both | **Implemented** — server-wins for flags; local optimistic updates via `ManageThreadActionsUseCase` |
| FR-SYNC-06 | Threading algorithm + dedup fallback key | MUST | AC-F-06, AC-F-06e | Both | **Partially implemented** — threading is implemented; fallback canonical dedup key is pending |
| FR-SYNC-07 | Email sending (SMTP) | MUST | AC-F-07 | Both | **Implemented** — SMTP transport, retry, queue transitions, and IMAP Sent APPEND path are in place |
| FR-SYNC-08 | Attachment handling | MUST | AC-F-06 | Both | **Implemented** — lazy `FETCH BODY[section]` via `DownloadAttachmentUseCase`, base64/QP decode, security warnings, cellular warnings; LRU cache TODO |
| FR-SYNC-09 | Connection management | MUST | AC-F-05 | Both | **Implemented** — `ConnectionPool` + `ConnectionProviding` protocol, TLS port 993, 30s timeout, 3 retries |
| FR-SYNC-10 | Flag synchronization | MUST | AC-F-06b, AC-F-08 | Both | **Implemented** — reads `\Seen`, `\Flagged`, `\Draft`, `\Deleted` from IMAP; local-to-server via IMAP STORE |
| G-01 | Full email CRUD | MUST | AC-F-05, AC-F-07, AC-F-08 | Both | **Partial** — read/archive/delete/star/mark-read/send implemented; v1.3 bootstrap delta pending |

---

## 2. Acceptance Criteria

---

**AC-F-05**: IMAP Client — **Implemented**

- **Given**: Valid OAuth credentials for a Gmail account
- **When**: The IMAP client connects to `imap.gmail.com:993`
- **Then**: The connection **MUST** use TLS
  AND XOAUTH2 authentication **MUST** succeed
  AND the client **MUST** list all Gmail folders (INBOX, Sent, Drafts, Trash, Spam, All Mail, Starred, plus labels)
  AND the client **MUST** fetch email UIDs within a date range
  AND the client **MUST** fetch complete email headers (From, To, CC, Subject, Date, Message-ID, References, In-Reply-To)
  AND the client **MUST** fetch email bodies (plain text and HTML parts)
  AND the client **MUST** support IMAP IDLE and receive notifications within 30 seconds of new email arrival
  AND the client **MUST** fetch individual body parts for lazy attachment download
- **Priority**: Critical
- **Implementation**: `IMAPClient.swift`, `IMAPSession.swift`, `ConnectionPool.swift`, `IMAPClientProtocol.swift`
- **Tests**: `MockIMAPClient` provides full protocol mock; `IDLEMonitorUseCaseTests` (5 tests) validates IDLE behavior

---

**AC-F-06**: Bootstrap Sync Engine — **Planned (v1.3.0 delta)**

- **Given**: A configured Gmail account
- **When**: First-login bootstrap sync is triggered
- **Then**: The first Inbox render **MUST** occur after the first 30 Inbox headers are persisted
  AND this first-render stage **MUST** be headers-only (no body prefetch requirement)
  AND remaining folder sync **MUST** continue in background without blocking interaction
  AND folder metadata (unread count, total count) **MUST** be updated incrementally as batches complete
  AND attachment metadata (bodySection, contentId, transferEncoding) **MUST** still be extracted from BODYSTRUCTURE for fetched items
- **Priority**: Critical
- **Implementation**: `SyncEmailsUseCase.syncAccount(accountId, options: .initialFast)` returning `SyncResult` (with temporary compatibility wrapper allowed during migration)

**AC-F-06b**: Dual-Cursor Incremental and Catch-Up — **Planned (v1.3.0 delta)**

- **Given**: A folder with persisted cursor state
- **When**: Forward incremental sync is triggered (pull-to-refresh or IDLE)
- **Then**: Only UIDs greater than `forwardCursorUID` **MUST** be fetched
  AND `forwardCursorUID` **MUST** advance only after committed batches
  AND UIDVALIDITY changes **MUST** reset both cursors and trigger folder re-bootstrap
  AND catch-up **MUST** resume from `backfillCursorUID` without reprocessing completed ranges
- **Priority**: Critical
- **Implementation**: `SyncEmailsUseCase.syncFolder(accountId, folderId, options: .incremental/.catchUp)`, cursor-aware directional workers with `SyncResult`

**AC-F-06c**: On-Scroll Older-Mail Paging — **Planned (v1.3.0 delta)**

- **Given**: The user has reached the end of currently loaded local messages
- **When**: The list pagination trigger fires
- **Then**: The client **MUST** fetch the next older page from IMAP immediately
  AND newly fetched headers **MUST** be persisted and appended without waiting for background catch-up completion
  AND repeated scroll pagination **MUST** continue until server history boundary or sync window boundary is reached
- **Priority**: High
- **Implementation**: `ThreadListView` pagination + `SyncEmailsUseCase` backward paging hooks

**AC-F-06d**: IDLE/Catch-Up Overlap Coordination — **Planned (v1.3.0 delta)**

- **Given**: Catch-up is running for a folder
- **When**: An IDLE new-mail event targets the same folder
- **Then**: The client **MUST NOT** run concurrent writers for that folder
  AND incremental work **MUST** be queued/preempted at a deterministic batch boundary
  AND cursor integrity **MUST** remain valid after both operations complete
- **Priority**: Critical
- **Implementation**: per-folder single-writer coordinator

**AC-F-06e**: Dedup Fallback for Missing/Duplicate Message-ID — **Planned (v1.3.0 delta)**

- **Given**: An incoming message has missing or duplicate `Message-ID`
- **When**: Dedup identity is evaluated
- **Then**: The client **MUST** use a canonical fallback key
  AND **MUST NOT** falsely merge unrelated messages
  AND **MUST NOT** create duplicate entities for the same logical message in the same folder
- **Priority**: Critical
- **Implementation**: canonical-key dedup pipeline in sync persistence path

**AC-F-06f**: macOS Pagination + Catch-Up Parity — **Planned (v1.3.0 delta)**

- **Given**: User is in a single-account folder thread list on macOS
- **When**: Local pagination is exhausted and the user scrolls further
- **Then**: The client **MUST** request the next older page via catch-up (`syncFolder(..., options: .catchUp)`)
  AND newly fetched items **MUST** be persisted and appended/reloaded in the thread list
  AND catch-up **MUST NOT** run in Unified mode (`selectedAccount == nil`)
  AND catch-up **MUST NOT** run in active search mode
  AND catch-up **MUST NOT** run for Outbox/non-syncable folders
  AND account/folder/category scope changes **MUST** reset:
  - `reachedServerHistoryBoundary = false`
  - `syncStatusText = nil`
  - `paginationError = false`
  AND pagination sentinel visibility **MUST** follow:
  - `hasMorePages == true`, OR
  - single-account folder context with `!reachedServerHistoryBoundary`
- **Priority**: High
- **Implementation**: `MacOSMainView.loadMoreThreads()` + `loadOlderFromServer()` guard matrix and `MacThreadListContentView` sentinel/status/retry contract

---

**AC-F-07**: SMTP Client — **Implemented**

- **Given**: Valid OAuth credentials and a composed email
- **When**: The email is sent
- **Then**: The SMTP connection **MUST** use TLS
  AND the email **MUST** be delivered to the recipient's inbox
  AND a copy **MUST** be appended to the Sent folder via IMAP
  AND if offline, the email **MUST** be queued and sent when connectivity resumes
- **Priority**: Critical
- **Implementation**: `SMTPClient.swift`, `SMTPSession.swift`, `ComposeEmailUseCase.executeSend()`, `MIMEEncoder.swift`

---

**AC-F-08**: Email Repository — **Implemented** (partial)

- **Given**: An `EmailRepositoryImpl` with connected IMAP and initialized SwiftData
- **When**: CRUD operations are performed
- **Then**: `fetchThreads` **MUST** return paginated threads sorted by latest date
  AND `markAsRead` **MUST** set the \Seen flag via IMAP and update local state
  AND `moveToFolder` **MUST** perform IMAP COPY + DELETE and update local state
  AND `deleteEmail` **MUST** move to Trash (or permanently delete if already in Trash)
  AND `starEmail` **MUST** set/remove the \Flagged flag via IMAP and update local state
  AND attachment download **MUST** decode Content-Transfer-Encoding (base64, quoted-printable, 7bit/8bit)
  AND dangerous file extensions **MUST** show security warnings (FR-ED-03)
  AND cellular download warnings **MUST** appear for attachments >= 25MB (FR-SYNC-08)
- **Priority**: Critical
- **Implementation**: `EmailRepositoryImpl.swift`, `ManageThreadActionsUseCase.swift`, `DownloadAttachmentUseCase.swift`
- **Tests**: `DownloadAttachmentUseCaseTests` (20+ tests)
- **Remaining**: 500MB LRU attachment cache

---

**AC-F-10**: Domain Use Cases — **Implemented**

- **Given**: Use cases with mocked repositories
- **When**: Each use case is invoked
- **Then**: `SyncEmailsUseCase` **MUST** orchestrate sync and report progress/errors
  AND `FetchThreadsUseCase` **MUST** return filtered, sorted, paginated threads
  AND send orchestration use case **MUST** queue and execute sends with retry semantics
  AND `ManageAccountsUseCase` **MUST** delegate to account repository correctly
  AND `IDLEMonitorUseCase` **MUST** emit `.newMail` events via `AsyncStream<IDLEEvent>`
  AND `DownloadAttachmentUseCase` **MUST** fetch body parts and decode transfer encoding
  AND `ManageThreadActionsUseCase` **MUST** sync flags bidirectionally with IMAP
- **Priority**: Critical
- **Implementation**: All use cases in `Domain/UseCases/`
- **Tests**: 549 tests across 38 suites, all passing

---

## 3. Edge Cases

| # | Scenario | Expected Behavior | Status |
|---|---------|-------------------|--------|
| E-01 | Network drops during initial sync | Sync pauses; resumes from persisted forward/backfill cursor checkpoints; partial data is usable | **Planned (v1.3.0 delta)** |
| E-03 | IMAP UIDVALIDITY changes | Folder cursors reset and folder bootstrap restarts; user may see delayed historical catch-up | **Planned (v1.3.0 delta)** |
| E-08 | Concurrent sync on multiple accounts | Syncs run independently; no deadlocks; UI responsive | **Handled** — `ConnectionPool` manages per-account connections |
| E-09 | Download 30MB attachment on cellular | Warning dialog shown; user can cancel or proceed (FR-SYNC-08) | **Handled** — `requiresCellularWarning(sizeBytes:)` returns true for >= 25MB |
| E-10 | OAuth token expires during long sync | Token refresh attempted; falls back to cached keychain token | **Handled** — `getAccessToken()` tries refresh, then cached |
| E-11 | IDLE connection dropped (Gmail 29-min limit) | `.disconnected` event emitted; ThreadListView can restart | **Handled** — `IDLEMonitorUseCase` yields `.disconnected`, caller decides to restart |
| E-12 | Background sync exceeds iOS budget | Sync task cancelled gracefully via expiration handler | **Handled** — `BGAppRefreshTask.expirationHandler` cancels in-flight sync |
| E-13 | Dangerous attachment file type | Security warning displayed before download | **Handled** — 18 dangerous extensions mapped with user-facing warning messages |
| E-14 | User cancels catch-up mid-run | In-flight batch completes atomically; no new catch-up batches start; state transitions to `paused` | **Planned (v1.3.0 delta)** |
| E-15 | IDLE event arrives during same-folder catch-up | No concurrent folder mutation; deterministic queue/preempt behavior | **Planned (v1.3.0 delta)** |
| E-16 | Message-ID missing/duplicate | Canonical fallback key used; no false merge/split | **Planned (v1.3.0 delta)** |
| E-17 | User scrolls at end of Unified Inbox list on macOS | No server catch-up call; local-pagination-only behavior preserved | **Planned (v1.3.0 delta)** |
| E-18 | User scrolls while search is active | No server catch-up call; search pagination remains local/filter-scoped | **Planned (v1.3.0 delta)** |
| E-19 | User scrolls in Outbox/non-syncable folder | No server catch-up call; sentinel behavior remains deterministic | **Planned (v1.3.0 delta)** |
| E-20 | Folder/account/category scope changes after history boundary reached | Boundary/status/error state resets; scrolling can trigger catch-up again in eligible contexts | **Planned (v1.3.0 delta)** |

---

## 3.1 macOS Pagination Test Cases (Planned)

| Test Case ID | Scenario | Expected Result | Planned Test File |
|---|---|---|---|
| TC-MAC-PAG-01 | `hasMorePages == true` and user reaches sentinel | Local DB pagination appends next page; no catch-up call | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-02 | `hasMorePages == false` in eligible single-account folder context | Catch-up is invoked via `syncFolder(..., .catchUp)` | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-03 | Catch-up returns empty result | `reachedServerHistoryBoundary = true`; sentinel hidden in single-account folder context | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-04 | Catch-up returns new emails | List reloads/appends with older content; boundary remains false | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-05 | Unified mode (`selectedAccount == nil`) | Catch-up not called (no-op) | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-06 | Search active | Catch-up not called (no-op) | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-07 | Outbox/non-syncable folder selected | Catch-up not called (no-op) | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-08 | Folder/account/category changes | `reachedServerHistoryBoundary`, `syncStatusText`, `paginationError` all reset | `VaultMailPackage/Tests/VaultMailFeatureTests/MacOSMainViewPaginationTests.swift` |
| TC-MAC-PAG-09 | Sentinel rendering rule | Sentinel visible only when `hasMorePages` OR eligible single-account context with `!reachedServerHistoryBoundary` | `VaultMailPackage/Tests/VaultMailFeatureTests/MacThreadListContentViewTests.swift` |
| TC-MAC-PAG-10 | Pagination failure then retry | Error row appears; Retry invokes `onLoadMore()` | `VaultMailPackage/Tests/VaultMailFeatureTests/MacThreadListContentViewTests.swift` |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Initial-window catch-up completion (1K emails) | < 60s | 120s | Wall clock time from account setup completion to 1K emails persisted (Wi-Fi) | Fails if > 120s |
| Time to first Inbox (first login) | < 3s P50, < 8s P95 | 10s | Time from account setup completion to first 30 Inbox rows visible | Fails if P95 > 10s |
| Incremental sync (10 emails) | < 5s | — | Time from foreground to updated list | Fails if > 10s on 3 runs |
| Send email | < 3s | 5s | Time from send tap to SMTP completion | Fails if > 5s |
| Background sync (all accounts) | < 30s | 30s | Must complete within iOS budget | Task cancelled by OS if exceeded |
| IDLE event response | < 2s | — | Time from server event to UI refresh | — |

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
