---
title: "Email Sync — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-sync/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Email Sync — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-05: IMAP Client

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01 through FR-SYNC-03
- **Validation ref**: AC-F-05
- **Description**: Implement IMAP client supporting XOAUTH2 authentication, folder listing, email fetch, and IDLE. Evaluate build vs. library decision.
- **Deliverables**:
  - [ ] `IMAPClient.swift` — connect, authenticate (XOAUTH2), disconnect
  - [ ] `IMAPSession.swift` — connection lifecycle management
  - [ ] List folders with attributes
  - [ ] Fetch email headers (envelope, flags, UID)
  - [ ] Fetch email body (BODYSTRUCTURE + body parts)
  - [ ] IMAP IDLE for push notifications
  - [ ] TLS enforcement (port 993)
  - [ ] Connection pooling for multi-account
  - [ ] Integration tests with mock IMAP server

### IOS-F-06: Sync Engine

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-01, FR-SYNC-02, FR-SYNC-04, FR-SYNC-05, FR-SYNC-06
- **Validation ref**: AC-F-06
- **Description**: Implement the sync engine that performs initial full sync, incremental sync, and real-time IDLE updates. Manage sync state per folder.
- **Deliverables**:
  - [ ] `SyncEngine.swift` — orchestrates sync lifecycle
  - [ ] Initial sync: fetch all emails within sync window
  - [ ] Incremental sync: fetch new emails since last UID
  - [ ] UIDVALIDITY change detection and re-sync
  - [ ] Sync state persistence (last UID, UIDVALIDITY per folder)
  - [ ] Thread grouping from References/In-Reply-To headers
  - [ ] Conflict resolution per spec FR-SYNC-05
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
- **Spec ref**: Email Sync spec (all FRs), Foundation spec Section 6
- **Validation ref**: AC-F-08
- **Description**: Implement `EmailRepositoryImpl` conforming to `EmailRepositoryProtocol`. Bridges IMAP/SMTP clients with SwiftData store.
- **Deliverables**:
  - [ ] `EmailRepositoryImpl.swift` — all protocol methods
  - [ ] Fetch threads with pagination
  - [ ] Mark read/unread, star/unstar
  - [ ] Move to folder, delete, archive
  - [ ] IMAP APPEND for sent messages
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
