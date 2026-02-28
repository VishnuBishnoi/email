---
title: "Email Sync — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-sync/ios-macos/plan.md
version: "1.3.0"
status: locked
updated: 2026-02-27
---

# Email Sync — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-05: IMAP Client

- **Status**: `done`
- **Spec ref**: Email Sync spec, FR-SYNC-01 through FR-SYNC-03, FR-SYNC-09
- **Validation ref**: AC-F-05
- **Description**: IMAP client (connect, authenticate, list folders, IDLE, connection management).
- **Deliverables**:
  - [x] `IMAPClient.swift` — connect, authenticate (XOAUTH2), disconnect
  - [x] `IMAPSession.swift` — connection lifecycle management
  - [x] List folders with attributes
  - [x] Fetch email headers (envelope, flags, UID)
  - [x] Fetch email body (BODYSTRUCTURE + body parts)
  - [x] IMAP IDLE for push notifications (`startIDLE(onNewMail:)`, `stopIDLE()`)
  - [x] TLS enforcement (port 993, FR-SYNC-09)
  - [x] Connection pooling for multi-account via `ConnectionPool` + `ConnectionProviding` protocol (FR-SYNC-09)
  - [x] Connection timeout (30s) and retry logic (3 retries: 5s/15s/45s, FR-SYNC-09)
  - [x] `fetchBodyPart(uid:section:)` for lazy attachment download (FR-SYNC-08)
  - [x] Unit tests with `MockIMAPClient` (comprehensive protocol mock)
- **Notes**: Built custom IMAP client (not a library). `ConnectionProviding` protocol abstracts pool for testability. `IMAPClientProtocol` defines all operations; `MockIMAPClient` provides full test double.

### IOS-F-06: Sync Engine

- **Status**: `in-progress` (baseline done, v1.3.0 delta pending)
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, FR-SYNC-04, FR-SYNC-05, FR-SYNC-06, FR-SYNC-08, FR-SYNC-10
- **Validation ref**: AC-F-06, AC-F-06b, AC-F-06c, AC-F-06d, AC-F-06e
- **Description**: Existing sync engine baseline (full sync, incremental, IDLE monitor, background sync, threading, flag sync, attachments), plus v1.3.0 delta implementation.
- **Deliverables**:
  - [x] `SyncEmailsUseCase.swift` — baseline orchestration lifecycle (logic lives in domain use case per MV pattern)
  - [x] Baseline initial sync implementation (pre-v1.3 behavior)
  - [x] Cross-folder deduplication by `messageId` via SHA256 stable ID (FR-SYNC-01)
  - [x] Baseline incremental sync implementation
  - [x] UIDVALIDITY change detection and re-sync (baseline behavior)
  - [x] Baseline sync state persistence (`lastSyncDate`, `uidValidity` per Folder in SwiftData)
  - [x] Thread grouping from References/In-Reply-To headers + subject-based fallback with 30-day window
  - [x] Attachment metadata extraction from BODYSTRUCTURE (stores `bodySection` + `contentId` per FR-SYNC-08)
  - [x] Bidirectional flag sync: reads `\Seen`, `\Flagged`, `\Draft`, `\Deleted` from IMAP; local-to-server via `ManageThreadActionsUseCase`
  - [x] Archive behavior: COPY to All Mail + DELETE + local EmailFolder cleanup (via `ManageThreadActionsUseCase`)
  - [x] Contact cache population from email headers (From, To, CC)
  - [x] `IDLEMonitorUseCase.swift` — real-time push via IMAP IDLE wrapped in `AsyncStream<IDLEEvent>` (FR-SYNC-03)
  - [x] `BackgroundSyncScheduler.swift` — `BGAppRefreshTask` for periodic background sync (15-min interval, 30-sec budget) (FR-SYNC-03)
  - [ ] Stage-B bootstrap render gate: first 30 Inbox headers (headers-only)
  - [ ] Stage-C budgeted background sync (default 500 headers total cap with folder floor)
  - [ ] Stage-D historical catch-up with pause/resume state
  - [ ] On-scroll older-mail paging trigger to fetch beyond local bootstrap data
  - [ ] Per-folder single-writer coordination between catch-up and IDLE incremental
  - [ ] Dedup fallback canonical key for missing/duplicate Message-ID
  - [x] Unit tests: `IDLEMonitorUseCaseTests` (5 tests), `BackgroundSyncSchedulerTests` (4 tests)
- **Notes**: Sync engine logic remains in `SyncEmailsUseCase` (not a separate `SyncEngine.swift`). v1.3.0 introduces directional cursor model and non-blocking bootstrap UX; baseline tests pass, new delta tests are pending.

### IOS-F-07: SMTP Client

- **Status**: `done`
- **Spec ref**: Email Sync spec, FR-SYNC-07
- **Validation ref**: AC-F-07
- **Description**: SMTP client (send, queue).
- **Deliverables**:
  - [x] `SMTPClient.swift` — actor with connect, authenticate (XOAUTH2), send; connection retry with exponential backoff (5s/15s/45s)
  - [x] `SMTPSession.swift` — 395 lines; Network.framework, port 465 implicit TLS, SASL base64 encoding, dot-stuffing, multi-line response parsing, timeout guards
  - [x] MIME message construction via `MIMEEncoder.swift` (headers, body, attachments)
  - [x] TLS enforcement (port 465 implicit TLS)
  - [x] Send queue via `ComposeEmailUseCase.executeSend()` — full pipeline: `.queued` → `.sending` → `.sent`/`.failed`, OAuth token refresh, real `smtpClient.sendMessage()`
  - [x] Retry logic with exponential backoff (3 retries)
  - [x] `SMTPClientProtocol` + `MockSMTPClient` for testability
- **Notes**: Full production SMTP implementation. `ComposeEmailUseCase.executeSend()` orchestrates the complete send pipeline including OAuth refresh and MIME encoding.

### IOS-F-08: Email Repository

- **Status**: `done` (partial — LRU cache remaining)
- **Spec ref**: Email Sync spec (all FRs including FR-SYNC-08, FR-SYNC-10), Foundation spec Section 6
- **Validation ref**: AC-F-08
- **Description**: Email repository implementation.
- **Deliverables**:
  - [x] `EmailRepositoryImpl.swift` — all protocol methods
  - [x] Fetch threads with pagination (cursor-based via `FetchThreadsUseCase`)
  - [x] Mark read/unread, star/unstar (optimistic local + IMAP STORE via `ManageThreadActionsUseCase`, FR-SYNC-10)
  - [x] Move to folder, delete, archive (COPY + DELETE + local EmailFolder cleanup via `ManageThreadActionsUseCase`, FR-SYNC-10)
  - [x] IMAP APPEND path for sent messages implemented in send orchestration (`ComposeEmailUseCase`, provider-aware best effort)
  - [x] Lazy attachment download on user tap via `DownloadAttachmentUseCase` with real IMAP `fetchBodyPart()` (FR-SYNC-08)
  - [ ] Attachment cache management (500MB LRU per account, FR-SYNC-08)
  - [x] Cellular download warning for attachments >=25MB (FR-SYNC-08)
  - [x] Security warnings for dangerous file extensions (exe, bat, pkg, dmg, etc.) (FR-ED-03)
  - [x] Unit tests: `DownloadAttachmentUseCaseTests` (20+ tests covering IMAP download, base64/QP/7bit decoding, security warnings, cellular warnings, error cases)
- **Notes**: Attachment download is fully wired end-to-end: `bodySection` stored during sync, lazy `FETCH BODY[section]` on tap, Content-Transfer-Encoding decode (base64, quoted-printable, 7bit/8bit), local file persist. Cache eviction (500MB LRU) still TODO.

### IOS-F-10: Domain Use Cases

- **Status**: `done`
- **Spec ref**: Foundation spec Section 6
- **Validation ref**: AC-F-10
- **Description**: Domain use cases (Sync, Fetch, Send, ManageAccounts, IDLE, Download, Actions).
- **Deliverables**:
  - [x] `SyncEmailsUseCase.swift` — full/incremental sync with connection pooling, threading, dedup, contact extraction
  - [x] `FetchThreadsUseCase.swift` — with AI category filtering, sorting, cursor-based pagination
  - [x] `ComposeEmailUseCase.swift` — outbox queue support + SMTP send execution path
  - [x] `ManageAccountsUseCase.swift` — CRUD + re-authentication flow
  - [x] `IDLEMonitorUseCase.swift` — real-time folder monitoring via IMAP IDLE (`AsyncStream<IDLEEvent>`)
  - [x] `DownloadAttachmentUseCase.swift` — lazy IMAP body part fetch with transfer-encoding decode
  - [x] `ManageThreadActionsUseCase.swift` — archive, delete, star, mark read/unread with IMAP flag sync
  - [x] `MarkReadUseCase.swift` — auto-mark-read on thread open
  - [x] Unit tests for use cases with mocked repositories (549 tests across 38 suites, all passing baseline)

### IOS-F-11: Staged Bootstrap + On-Scroll Paging (v1.3.0 Delta)

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, NFR-SYNC-06
- **Validation ref**: AC-F-06, AC-F-06c
- **Description**: Staged first-login bootstrap (30 Inbox headers), non-blocking background catch-up, on-scroll older-mail paging.
- **Deliverables**:
  - [ ] Unified sync contract: `syncAccount(accountId, options: .initialFast)` returns structured `SyncResult`
  - [ ] Keep `syncAccountInboxFirst()` as compatibility wrapper during migration; mark deprecated in docs once options path lands
  - [ ] Bootstrap budget allocator (default 500 total headers, 60/20/20 split)
  - [ ] Per-folder bootstrap floor (minimum 20 headers when budget allows)
  - [ ] `ThreadListView` pagination hook to fetch older server pages on demand
  - [ ] UI state text updates: "Inbox ready", "Syncing older mail...", "Catch-up paused"
  - [ ] Tests: bootstrap render timing and on-scroll paging behavior
- **Notes**: Bootstrap cap is a background budget, not a blocking wait threshold.

### IOS-F-12: Dual Cursor Checkpoint Model (v1.3.0 Delta)

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-02, FR-SYNC-04
- **Validation ref**: AC-F-06b
- **Description**: Dual-cursor checkpoint model (`forwardCursorUID`, `backfillCursorUID`) and resumable pause/resume semantics.
- **Deliverables**:
  - [ ] Add `forwardCursorUID` and `backfillCursorUID` to `Folder` model (migration-safe defaults)
  - [ ] Add `initialFastCompleted` and `catchUpStatus` (`idle|running|paused|completed|error`)
  - [ ] Persist cursor updates after each committed batch
  - [ ] Resume behavior: forward uses `forwardCursorUID`, catch-up uses `backfillCursorUID`
  - [ ] UIDVALIDITY reset logic clears both cursors
  - [ ] Tests: cursor progression, resume after interruption, UIDVALIDITY reset handling
- **Notes**: Keep legacy `lastSyncDate` for compatibility/telemetry until full cutover.

### IOS-F-13: IDLE/Catch-Up Coordination (v1.3.0 Delta)

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-03, FR-SYNC-04
- **Validation ref**: AC-F-06d
- **Description**: IDLE/catch-up overlap control with per-folder single-writer coordination.
- **Deliverables**:
  - [ ] Add `FolderSyncCoordinator` (or equivalent) with folder-level lock/queue
  - [ ] Define deterministic queue/preempt policy at batch boundaries
  - [ ] Ensure cancellation/retry paths always release folder lock
  - [ ] Tests: overlapping triggers, lock release on error/cancel, cursor integrity under contention
- **Notes**: This is required for correctness once catch-up is long-lived and non-blocking.

### IOS-F-14: Dedup Fallback Canonical Key (v1.3.0 Delta)

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-06
- **Validation ref**: AC-F-06e
- **Description**: Dedup fallback canonical key for missing/duplicate Message-ID.
- **Deliverables**:
  - [ ] Canonical key generation utility from normalized headers
  - [ ] Repository lookup path: `messageId` first, canonical key second
  - [ ] Collision safeguards to prevent false merges
  - [ ] Tests: missing Message-ID, duplicate Message-ID, collision edge cases
- **Notes**: Canonical fallback complements existing stable ID logic; it does not replace folder-scoped IMAP UID storage.

### IOS-F-15: macOS Pagination + Catch-Up Parity with iOS (v1.3.0 Delta)

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, FR-SYNC-03 (interaction consistency)
- **Validation ref**: AC-F-06f
- **Description**: Align macOS infinite-scroll behavior with iOS ThreadList paging contract.
- **Deliverables**:
  - [ ] `MacOSMainView.loadMoreThreads()` two-stage flow: local DB pagination first, then IMAP catch-up fallback
  - [ ] `MacOSMainView.loadOlderFromServer()` with explicit no-op guards for Unified mode, active search mode, and Outbox/non-syncable folders
  - [ ] Shared reset helper that clears `reachedServerHistoryBoundary`, `syncStatusText`, and `paginationError` on account/folder/category scope changes
  - [ ] `MacThreadListContentView` sentinel/status/retry wiring with parity rule:
    - sentinel visible when `hasMorePages == true`
    - OR single-account folder context with `!reachedServerHistoryBoundary`
  - [ ] Maintain Unified Inbox behavior as local-pagination-only (no server catch-up)
  - [ ] Preserve existing initial inbox-first sync and manual sync behavior
- **Test Deliverables**:
  - [ ] `TC-MAC-PAG-01`: local pagination appends next DB page when `hasMorePages == true`
  - [ ] `TC-MAC-PAG-02`: fallback to catch-up when `hasMorePages == false` in eligible single-account folder context
  - [ ] `TC-MAC-PAG-03`: empty catch-up result sets boundary reached and hides sentinel
  - [ ] `TC-MAC-PAG-04`: non-empty catch-up result reloads/appends older threads
  - [ ] `TC-MAC-PAG-05`: Unified mode does not trigger catch-up
  - [ ] `TC-MAC-PAG-06`: active search mode does not trigger catch-up
  - [ ] `TC-MAC-PAG-07`: Outbox/non-syncable folders do not trigger catch-up
  - [ ] `TC-MAC-PAG-08`: folder/account/category changes reset boundary/status/error state
  - [ ] `TC-MAC-PAG-09`: sentinel rule matches parity contract
  - [ ] `TC-MAC-PAG-10`: pagination error renders retry and retry triggers `onLoadMore()`
- **Notes**: This task is docs-first and test-first scoped in this phase; implementation lands in follow-up code change.
