---
title: "Email Sync — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-sync/ios-macos/plan.md
version: "1.3.0"
status: locked
updated: 2026-02-10
---

# Email Sync — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-05: IMAP Client

- **Status**: `done`
- **Spec ref**: Email Sync spec, FR-SYNC-01 through FR-SYNC-03, FR-SYNC-09
- **Validation ref**: AC-F-05
- **Description**: Implement IMAP client supporting XOAUTH2 authentication, folder listing, email fetch, IDLE, and connection management. Evaluate build vs. library decision.
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

- **Status**: `done`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, FR-SYNC-04, FR-SYNC-05, FR-SYNC-06, FR-SYNC-08, FR-SYNC-10
- **Validation ref**: AC-F-06, AC-F-06b
- **Description**: Implement the sync engine that performs initial full sync, incremental sync, real-time IDLE updates, flag sync, and attachment metadata extraction. Manage sync state per folder.
- **Deliverables**:
  - [x] `SyncEmailsUseCase.swift` — orchestrates full sync lifecycle (replaces planned `SyncEngine.swift`; logic lives in domain use case per MV pattern)
  - [x] Initial sync: fetch all emails within configurable sync window (`account.syncWindowDays`)
  - [x] Cross-folder deduplication by `messageId` via SHA256 stable ID (FR-SYNC-01)
  - [x] Incremental sync: fetch new UIDs since last `folder.lastSyncDate`
  - [x] UIDVALIDITY change detection and re-sync (resets `lastSyncDate` to force full re-fetch)
  - [x] Sync state persistence (`lastSyncDate`, `uidValidity` per Folder in SwiftData)
  - [x] Thread grouping from References/In-Reply-To headers + subject-based fallback with 30-day window
  - [x] Attachment metadata extraction from BODYSTRUCTURE (stores `bodySection` + `contentId` per FR-SYNC-08)
  - [x] Bidirectional flag sync: reads `\Seen`, `\Flagged`, `\Draft`, `\Deleted` from IMAP; local-to-server via `ManageThreadActionsUseCase`
  - [x] Archive behavior: COPY to All Mail + DELETE + local EmailFolder cleanup (via `ManageThreadActionsUseCase`)
  - [x] Contact cache population from email headers (From, To, CC)
  - [x] `IDLEMonitorUseCase.swift` — real-time push via IMAP IDLE wrapped in `AsyncStream<IDLEEvent>` (FR-SYNC-03)
  - [x] `BackgroundSyncScheduler.swift` — `BGAppRefreshTask` for periodic background sync (15-min interval, 30-sec budget) (FR-SYNC-03)
  - [x] Onboarding sync trigger: `OnboardingView.completeOnboarding()` fires background sync for all added accounts (FR-SYNC-01)
  - [x] Unit tests: `IDLEMonitorUseCaseTests` (5 tests), `BackgroundSyncSchedulerTests` (4 tests)
- **Notes**: Sync engine logic is in `SyncEmailsUseCase` (not a separate `SyncEngine.swift`), following the MV/use-case pattern. Real-time IDLE is a separate `IDLEMonitorUseCase` wired into `ThreadListView` via `.task(id:)`. Background sync registered in `VaultMailApp.init()`. Onboarding triggers sync immediately after account setup.

### IOS-F-07: SMTP Client

- **Status**: `done`
- **Spec ref**: Email Sync spec, FR-SYNC-07
- **Validation ref**: AC-F-07
- **Description**: Implement SMTP client for sending emails via Gmail SMTP with XOAUTH2. Support queuing for offline sends.
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

- **Status**: `done` (partial — IMAP APPEND and LRU cache remaining)
- **Spec ref**: Email Sync spec (all FRs including FR-SYNC-08, FR-SYNC-10), Foundation spec Section 6
- **Validation ref**: AC-F-08
- **Description**: Implement `EmailRepositoryImpl` conforming to `EmailRepositoryProtocol`. Bridges IMAP/SMTP clients with SwiftData store. Includes lazy attachment download and flag sync operations.
- **Deliverables**:
  - [x] `EmailRepositoryImpl.swift` — all protocol methods
  - [x] Fetch threads with pagination (cursor-based via `FetchThreadsUseCase`)
  - [x] Mark read/unread, star/unstar (optimistic local + IMAP STORE via `ManageThreadActionsUseCase`, FR-SYNC-10)
  - [x] Move to folder, delete, archive (COPY + DELETE + local EmailFolder cleanup via `ManageThreadActionsUseCase`, FR-SYNC-10)
  - [ ] IMAP APPEND for sent messages (blocked on SMTP — IOS-F-07)
  - [x] Lazy attachment download on user tap via `DownloadAttachmentUseCase` with real IMAP `fetchBodyPart()` (FR-SYNC-08)
  - [ ] Attachment cache management (500MB LRU per account, FR-SYNC-08)
  - [x] Cellular download warning for attachments >=25MB (FR-SYNC-08)
  - [x] Security warnings for dangerous file extensions (exe, bat, pkg, dmg, etc.) (FR-ED-03)
  - [x] Unit tests: `DownloadAttachmentUseCaseTests` (20+ tests covering IMAP download, base64/QP/7bit decoding, security warnings, cellular warnings, error cases)
- **Notes**: Attachment download is fully wired end-to-end: `bodySection` stored during sync, lazy `FETCH BODY[section]` on tap, Content-Transfer-Encoding decode (base64, quoted-printable, 7bit/8bit), local file persist. IMAP APPEND blocked on SMTP. Cache eviction (500MB LRU) still TODO.

### IOS-F-10: Domain Use Cases

- **Status**: `done`
- **Spec ref**: Foundation spec Section 6
- **Validation ref**: AC-F-10
- **Description**: Implement core domain use cases: SyncEmails, FetchThreads, SendEmail, ManageAccounts, IDLE monitoring, attachment download, background sync.
- **Deliverables**:
  - [x] `SyncEmailsUseCase.swift` — full/incremental sync with connection pooling, threading, dedup, contact extraction
  - [x] `FetchThreadsUseCase.swift` — with AI category filtering, sorting, cursor-based pagination
  - [x] `SendEmailUseCase.swift` — with outbox queue support (SMTP transport stubbed — IOS-F-07)
  - [x] `ManageAccountsUseCase.swift` — CRUD + re-authentication flow
  - [x] `IDLEMonitorUseCase.swift` — real-time folder monitoring via IMAP IDLE (`AsyncStream<IDLEEvent>`)
  - [x] `DownloadAttachmentUseCase.swift` — lazy IMAP body part fetch with transfer-encoding decode
  - [x] `ManageThreadActionsUseCase.swift` — archive, delete, star, mark read/unread with IMAP flag sync
  - [x] `MarkReadUseCase.swift` — auto-mark-read on thread open
  - [x] Unit tests for use cases with mocked repositories (627+ tests across 54 suites, all passing)
