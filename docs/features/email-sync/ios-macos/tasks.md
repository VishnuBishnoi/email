---
title: "Email Sync — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-sync/ios-macos/plan.md
version: "1.1.0"
status: draft
updated: 2026-02-07
---

# Email Sync — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-05: IMAP Client

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01 through FR-SYNC-03, FR-SYNC-09
- **Validation ref**: AC-F-05
- **Description**: Implement IMAP client supporting XOAUTH2 authentication, folder listing, email fetch, IDLE, and connection management. Evaluate build vs. library decision.
- **Deliverables**:
  - [ ] `IMAPClient.swift` — connect, authenticate (XOAUTH2), disconnect
  - [ ] `IMAPSession.swift` — connection lifecycle management
  - [ ] List folders with attributes
  - [ ] Fetch email headers (envelope, flags, UID)
  - [ ] Fetch email body (BODYSTRUCTURE + body parts)
  - [ ] IMAP IDLE for push notifications
  - [ ] TLS enforcement (port 993, FR-SYNC-09)
  - [ ] Connection pooling for multi-account (max 5 connections, FR-SYNC-09)
  - [ ] Connection timeout (30s) and retry logic (3 retries: 5s/15s/45s, FR-SYNC-09)
  - [ ] Integration tests with mock IMAP server

### IOS-F-06: Sync Engine

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, FR-SYNC-04, FR-SYNC-05, FR-SYNC-06, FR-SYNC-08, FR-SYNC-10
- **Validation ref**: AC-F-06, AC-F-06b
- **Description**: Implement the sync engine that performs initial full sync, incremental sync, real-time IDLE updates, flag sync, and attachment metadata extraction. Manage sync state per folder.
- **Deliverables**:
  - [ ] `SyncEngine.swift` — orchestrates sync lifecycle
  - [ ] Initial sync: fetch all emails within sync window
  - [ ] Cross-folder deduplication by `messageId` (FR-SYNC-01)
  - [ ] Incremental sync: fetch new emails since last UID
  - [ ] UIDVALIDITY change detection and re-sync
  - [ ] Sync state persistence (last UID, UIDVALIDITY per folder)
  - [ ] Thread grouping from References/In-Reply-To headers
  - [ ] Conflict resolution per spec FR-SYNC-05
  - [ ] Attachment metadata extraction from BODYSTRUCTURE (FR-SYNC-08)
  - [ ] Bidirectional flag sync: local↔server \Seen and \Flagged (FR-SYNC-10)
  - [ ] Archive behavior: COPY to All Mail + DELETE + local EmailFolder cleanup (FR-SYNC-10)
  - [ ] Unit tests for sync state machine transitions
  - [ ] Integration tests for initial + incremental sync

### IOS-F-07: SMTP Client

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-07
- **Validation ref**: AC-F-07
- **Description**: Implement SMTP client for sending emails via Gmail SMTP with XOAUTH2. Support queuing for offline sends.
- **Deliverables**:
  - [ ] `SMTPClient.swift` — connect, authenticate (XOAUTH2), send
  - [ ] MIME message construction (headers, body, attachments)
  - [ ] TLS enforcement (port 465 or STARTTLS 587)
  - [ ] Send queue for offline operation
  - [ ] Retry logic with exponential backoff
  - [ ] Integration tests with mock SMTP server

### IOS-F-08: Email Repository

- **Status**: `todo`
- **Spec ref**: Email Sync spec (all FRs including FR-SYNC-08, FR-SYNC-10), Foundation spec Section 6
- **Validation ref**: AC-F-08
- **Description**: Implement `EmailRepositoryImpl` conforming to `EmailRepositoryProtocol`. Bridges IMAP/SMTP clients with SwiftData store. Includes lazy attachment download and flag sync operations.
- **Deliverables**:
  - [ ] `EmailRepositoryImpl.swift` — all protocol methods
  - [ ] Fetch threads with pagination
  - [ ] Mark read/unread, star/unstar (optimistic local + IMAP STORE, FR-SYNC-10)
  - [ ] Move to folder, delete, archive (COPY + DELETE + local EmailFolder cleanup, FR-SYNC-10)
  - [ ] IMAP APPEND for sent messages
  - [ ] Lazy attachment download on user tap (FR-SYNC-08)
  - [ ] Attachment cache management (500MB LRU per account, FR-SYNC-08)
  - [ ] Cellular download warning for attachments ≥25MB (FR-SYNC-08)
  - [ ] Unit tests with mocked dependencies

### IOS-F-10: Domain Use Cases

- **Status**: `todo`
- **Spec ref**: Foundation spec Section 6
- **Validation ref**: AC-F-10
- **Description**: Implement core domain use cases: SyncEmails, FetchThreads, SendEmail, ManageAccounts.
- **Deliverables**:
  - [ ] `SyncEmailsUseCase.swift`
  - [ ] `FetchThreadsUseCase.swift` — with filtering, sorting, pagination
  - [ ] `SendEmailUseCase.swift` — with queue support
  - [ ] `ManageAccountsUseCase.swift`
  - [ ] Unit tests for each use case with mocked repositories
