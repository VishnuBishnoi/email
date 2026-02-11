---
title: "Email Sync — iOS/macOS Validation"
spec-ref: docs/features/email-sync/spec.md
plan-refs:
  - docs/features/email-sync/ios-macos/plan.md
  - docs/features/email-sync/ios-macos/tasks.md
version: "1.3.0"
status: locked
last-validated: 2026-02-11
---

# Email Sync — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SYNC-01 | Full sync | MUST | AC-F-06 | Both | **Implemented** — `SyncEmailsUseCase.syncAccount()` with configurable sync window, cross-folder dedup, threading |
| FR-SYNC-02 | Incremental sync | MUST | AC-F-06b | Both | **Implemented** — UID-based incremental via `folder.lastSyncDate`, UIDVALIDITY change detection |
| FR-SYNC-03 | Real-time updates (IDLE) | MUST | AC-F-05 | Both | **Implemented** — `IDLEMonitorUseCase` + `BackgroundSyncScheduler` (BGAppRefreshTask on iOS) |
| FR-SYNC-05 | Conflict resolution | MUST | AC-F-06 | Both | **Implemented** — server-wins for flags; local optimistic updates via `ManageThreadActionsUseCase` |
| FR-SYNC-06 | Threading algorithm | MUST | AC-F-06 | Both | **Implemented** — References/In-Reply-To + subject-based fallback with 30-day window |
| FR-SYNC-07 | Email sending (SMTP) | MUST | AC-F-07 | Both | **Not started** — SMTP transport not yet implemented |
| FR-SYNC-08 | Attachment handling | MUST | AC-F-06 | Both | **Implemented** — lazy `FETCH BODY[section]` via `DownloadAttachmentUseCase`, base64/QP decode, security warnings, cellular warnings; LRU cache TODO |
| FR-SYNC-09 | Connection management | MUST | AC-F-05 | Both | **Implemented** — `ConnectionPool` + `ConnectionProviding` protocol, TLS port 993, 30s timeout, 3 retries |
| FR-SYNC-10 | Flag synchronization | MUST | AC-F-06b, AC-F-08 | Both | **Implemented** — reads `\Seen`, `\Flagged`, `\Draft`, `\Deleted` from IMAP; local-to-server via IMAP STORE |
| G-01 | Full email CRUD | MUST | AC-F-05, AC-F-07, AC-F-08 | Both | **Partial** — read, archive, delete, star, mark-read done; send blocked on SMTP |

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

**AC-F-06**: Sync Engine — **Implemented**

- **Given**: A configured Gmail account
- **When**: Initial sync is triggered with a configurable sync window (default 30 days)
- **Then**: All emails within the window **MUST** be downloaded (headers + bodies)
  AND emails **MUST** be grouped into threads using References/In-Reply-To headers (with subject-based fallback)
  AND folder metadata (unread count, total count) **MUST** be accurate
  AND sync state (`lastSyncDate`, `uidValidity`) **MUST** be persisted per folder in SwiftData
  AND cross-folder deduplication **MUST** use SHA256 stable ID from `accountId + messageId`
  AND attachment metadata (bodySection, contentId, transferEncoding) **MUST** be extracted from BODYSTRUCTURE
- **Priority**: Critical
- **Implementation**: `SyncEmailsUseCase.swift` (replaces originally planned `SyncEngine.swift`)

**AC-F-06b**: Incremental Sync — **Implemented**

- **Given**: A previously synced account with sync state
- **When**: Incremental sync is triggered (pull-to-refresh or IDLE notification)
- **Then**: Only emails newer than the last synced date **MUST** be fetched
  AND UIDVALIDITY changes **MUST** trigger re-sync of affected folder
  AND flag changes (read, starred) **MUST** be synced bidirectionally
  AND the sync **MUST** complete within 5 seconds for 10 new emails on Wi-Fi
- **Priority**: Critical
- **Implementation**: `SyncEmailsUseCase.syncFolder()`, triggered by `.refreshable` and `IDLEMonitorUseCase`

---

**AC-F-07**: SMTP Client — **Not Started**

- **Given**: Valid OAuth credentials and a composed email
- **When**: The email is sent
- **Then**: The SMTP connection **MUST** use TLS
  AND the email **MUST** be delivered to the recipient's inbox
  AND a copy **MUST** be appended to the Sent folder via IMAP
  AND if offline, the email **MUST** be queued and sent when connectivity resumes
- **Priority**: Critical
- **Implementation**: `ComposeEmailUseCase` provides outbox queue; SMTP transport not yet built

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
- **Remaining**: IMAP APPEND (blocked on SMTP), 500MB LRU attachment cache

---

**AC-F-10**: Domain Use Cases — **Implemented**

- **Given**: Use cases with mocked repositories
- **When**: Each use case is invoked
- **Then**: `SyncEmailsUseCase` **MUST** orchestrate sync and report progress/errors
  AND `FetchThreadsUseCase` **MUST** return filtered, sorted, paginated threads
  AND `SendEmailUseCase` **MUST** queue the email for sending (SMTP transport pending)
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
| E-01 | Network drops during initial sync | Sync pauses; resumes from last checkpoint on reconnect; partial data is usable | **Handled** — errors propagated, `lastSyncDate` only updated on success |
| E-03 | IMAP UIDVALIDITY changes | Full re-sync of affected folder; user notified of delay | **Handled** — `lastSyncDate` reset to nil, forces full re-fetch |
| E-08 | Concurrent sync on multiple accounts | Syncs run independently; no deadlocks; UI responsive | **Handled** — `ConnectionPool` manages per-account connections |
| E-09 | Download 30MB attachment on cellular | Warning dialog shown; user can cancel or proceed (FR-SYNC-08) | **Handled** — `requiresCellularWarning(sizeBytes:)` returns true for >= 25MB |
| E-10 | OAuth token expires during long sync | Token refresh attempted; falls back to cached keychain token | **Handled** — `getAccessToken()` tries refresh, then cached |
| E-11 | IDLE connection dropped (Gmail 29-min limit) | `.disconnected` event emitted; ThreadListView can restart | **Handled** — `IDLEMonitorUseCase` yields `.disconnected`, caller decides to restart |
| E-12 | Background sync exceeds iOS budget | Sync task cancelled gracefully via expiration handler | **Handled** — `BGAppRefreshTask.expirationHandler` cancels in-flight sync |
| E-13 | Dangerous attachment file type | Security warning displayed before download | **Handled** — 18 dangerous extensions mapped with user-facing warning messages |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Initial sync (1K emails) | < 60s | 120s | Wall clock time on Wi-Fi | Fails if > 120s |
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
