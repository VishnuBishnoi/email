---
title: "Email Sync — iOS/macOS Validation"
spec-ref: docs/features/email-sync/spec.md
plan-refs:
  - docs/features/email-sync/ios-macos/plan.md
  - docs/features/email-sync/ios-macos/tasks.md
version: "1.4.0"
status: draft
last-validated: 2026-02-16
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
| FR-SYNC-04 | Sync state machine | MUST | AC-F-06 | Both | **Implemented** — `SyncEmailsUseCase` state flow: Idle → Connecting → Authenticating → SyncingFolders → SyncingHeaders → SyncingBodies → Indexing → Idle; error/retry paths included |
| FR-SYNC-05 | Conflict resolution | MUST | AC-F-06 | Both | **Implemented** — server-wins for flags; local optimistic updates via `ManageThreadActionsUseCase` |
| FR-SYNC-06 | Threading algorithm | MUST | AC-F-06 | Both | **Implemented** — References/In-Reply-To + subject-based fallback with 30-day window |
| FR-SYNC-07 | Email sending (SMTP) | MUST | AC-F-07 | Both | **Partial** — Gmail XOAUTH2 + implicit TLS implemented; provider-agnostic MUST behaviors (PLAIN auth, STARTTLS, conditional `requiresSentAppend`, auth-mechanism-aware errors) deferred to IOS-MP-02/03/12 and IOS-ES-04 |
| FR-SYNC-08 | Attachment handling | MUST | AC-F-06 | Both | **Implemented** — lazy `FETCH BODY[section]` via `DownloadAttachmentUseCase`, base64/QP decode, security warnings, cellular warnings; LRU cache TODO |
| FR-SYNC-09 | Connection management | MUST | AC-F-05 | Both | **Implemented** — `ConnectionPool` + `ConnectionProviding` protocol, TLS port 993, 30s timeout, 3 retries; provider-configurable limits deferred to IOS-MP-13 |
| FR-SYNC-10 | Flag synchronization | MUST | AC-F-06b, AC-F-08 | Both | **Implemented** — reads `\Seen`, `\Flagged`, `\Draft`, `\Deleted` from IMAP; local-to-server via IMAP STORE |
| FR-SYNC-11 | Concurrent multi-account sync | MUST | AC-ES-01 | Both | — (IOS-ES-01) |
| FR-SYNC-12 | Per-account IDLE monitoring | MUST/SHOULD | AC-ES-02 | Both | — (IOS-ES-02) |
| FR-SYNC-13 | Background sync (multi-account) | MUST | AC-ES-03 | Both | — (IOS-ES-03) |
| FR-SYNC-14 | Per-account offline send queue | MUST | AC-ES-04 | Both | — (IOS-ES-04) |
| FR-SYNC-15 | Unified inbox | MUST | AC-ES-05 | Both | — (IOS-ES-05) |
| FR-SYNC-16 | Global connection pool limits | MUST | AC-ES-06 | Both | — (IOS-ES-06) |
| FR-SYNC-17 | Sync status observability | MUST | AC-ES-07 | Both | — (IOS-ES-07) |
| FR-SYNC-18 | Sync debug view | MUST | AC-ES-08 | Both | — (IOS-ES-08) |
| NFR-SYNC-06 | Multi-account sync throughput | MUST | AC-ES-01 | Both | — (< 15s for 3 accounts) |
| NFR-SYNC-07 | Per-account error isolation | MUST | AC-ES-01 | Both | — (zero cross-account failure) |
| NFR-SYNC-08 | Global connection resource usage | MUST | AC-ES-06 | Both | — (≤ 30 connections, platform-specific reclaim) |
| NFR-SYNC-09 | Sync status latency | MUST | AC-ES-07 | Both | — (< 500ms state → UI) |
| G-01 | Full email CRUD | MUST | AC-F-05, AC-F-07, AC-F-08 | Both | **Partial** — read, archive, delete, star, mark-read done; send done for Gmail XOAUTH2; provider-agnostic send deferred to IOS-MP/IOS-ES |

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

**AC-F-07**: SMTP Client — **Partial** (Gmail XOAUTH2 implemented; provider-agnostic MUST behaviors deferred)

- **Given**: Valid credentials (OAuth token or app password) and a composed email
- **When**: The email is sent
- **Then**: The SMTP connection **MUST** use the account's configured security mode (implicit TLS or STARTTLS per FR-MPROV-05)
  AND the SMTP connection **MUST** authenticate using the account's configured auth mechanism (XOAUTH2 or PLAIN per FR-MPROV-02)
  AND the email **MUST** be delivered to the recipient's inbox
  AND sent-folder append **MUST** be conditional: only if `requiresSentAppend == true` in the provider registry (FR-MPROV-13); Gmail (false) skips append; non-Gmail (true) appends via IMAP
  AND SMTP auth failure handling **MUST** depend on auth mechanism: OAuth → token refresh; PLAIN → credential error (no refresh)
  AND if offline, the email **MUST** be queued and sent when connectivity resumes
- **Priority**: Critical
- **Implementation**: `SMTPClient.swift`, `SMTPSession.swift`, `MIMEEncoder.swift`, `ComposeEmailUseCase.executeSend()`. Gmail XOAUTH2 + implicit TLS (port 465) is implemented and tested.
- **Deferred MUST behaviors**: PLAIN auth (IOS-MP-02), STARTTLS transport (IOS-MP-03), conditional `requiresSentAppend` (IOS-MP-12), auth-mechanism-aware error handling (IOS-ES-04). These are spec v1.3.4 MUST requirements that block full FR-SYNC-07 compliance.

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
- **Remaining**: IMAP APPEND (deferred to IOS-MP-12 — conditional `requiresSentAppend`), 500MB LRU attachment cache

---

**AC-F-10**: Domain Use Cases — **Implemented**

- **Given**: Use cases with mocked repositories
- **When**: Each use case is invoked
- **Then**: `SyncEmailsUseCase` **MUST** orchestrate sync and report progress/errors
  AND `FetchThreadsUseCase` **MUST** return filtered, sorted, paginated threads
  AND `SendEmailUseCase` **MUST** queue the email and send via SMTP (Gmail XOAUTH2 implemented; multi-provider extensions deferred to IOS-MP/IOS-ES tasks)
  AND `ManageAccountsUseCase` **MUST** delegate to account repository correctly
  AND `IDLEMonitorUseCase` **MUST** emit `.newMail` events via `AsyncStream<IDLEEvent>`
  AND `DownloadAttachmentUseCase` **MUST** fetch body parts and decode transfer encoding
  AND `ManageThreadActionsUseCase` **MUST** sync flags bidirectionally with IMAP
- **Priority**: Critical
- **Implementation**: All use cases in `Domain/UseCases/`
- **Tests**: 627+ tests across 54 suites, all passing

---

### Multi-Account Sync Acceptance Criteria (v1.3.0+)

**AC-ES-01**: Concurrent Multi-Account Sync Orchestration — **Not started**

- **Given**: Multiple active accounts (≥ 2) with different providers
- **When**: App enters foreground or sync is triggered
- **Then**: All active accounts **MUST** sync concurrently via structured concurrency (`TaskGroup`)
  AND the currently-viewed account **MUST** sync its inbox first (priority ordering)
  AND a failure on Account A **MUST NOT** block, cancel, or affect Account B's sync
  AND token refresh failure on one account **MUST NOT** interrupt other accounts
  AND account removal **MUST** cancel in-progress sync tasks and disconnect its connection pool
  AND app backgrounding **MUST** gracefully cancel with checkpoint preservation
- **Priority**: Critical

---

**AC-ES-02**: Per-Account IDLE Monitoring — **Not started**

- **Given**: Multiple active accounts with IDLE-capable IMAP servers
- **When**: App is in foreground
- **Then**: One IDLE connection per active account **SHOULD** monitor INBOX
  AND **on iOS**, a maximum of 5 concurrent IDLE connections **MUST** be enforced; deprioritized accounts **MUST** fall back to periodic polling every 5 minutes
  AND **on macOS**, no IDLE cap applies; all accounts **MUST** have IDLE active
  AND IDLE refresh interval **MUST** use the provider-specific value from the provider registry
  AND an `EXISTS` notification on any account **MUST** trigger incremental sync for only that account's INBOX
  AND a disconnect on one account **MUST NOT** affect IDLE on other accounts
- **Priority**: Critical

---

**AC-ES-03**: Background Sync for Multiple Accounts — **Not started**

- **Given**: Multiple active accounts and the app is in background (iOS) or open (macOS)
- **When**: Background sync is triggered
- **Then**: **On iOS**, accounts **MUST** be synced in priority order (most stale first) within the 30-second budget
  AND `Task.isCancelled` **MUST** be checked before each account; remaining accounts **MUST** be skipped if < 10s budget remains
  AND a follow-up `BGAppRefreshTask` **SHOULD** be scheduled for unsynced accounts
  AND **on macOS**, a periodic `Timer` (5-min interval) **MUST** trigger full incremental sync for all stale accounts
  AND one account's failure **MUST NOT** prevent subsequent accounts from syncing
- **Priority**: Medium

---

**AC-ES-04**: Per-Account Offline Send Queue — **Not started**

- **Given**: Queued emails across multiple accounts with different providers and auth mechanisms
- **When**: Connectivity is restored
- **Then**: Each queued email **MUST** route through the correct account's SMTP server and credentials
  AND if Account A's SMTP is unreachable, Account B's queue **MUST** still be processed
  AND SMTP auth failure for OAuth accounts **MUST** trigger token refresh
  AND SMTP auth failure for PLAIN accounts **MUST** display "Check your app password" (no token refresh)
  AND the Outbox view **MUST** display which account each queued email sends from
- **Priority**: Medium

---

**AC-ES-05**: Unified Inbox Behavior — **Not started**

- **Given**: Multiple active accounts in "All Accounts" view
- **When**: The unified inbox is displayed
- **Then**: Threads from all accounts **MUST** be interleaved by `latestDate` (newest first)
  AND each thread **MUST** display an account indicator (colored dot, avatar, or email label)
  AND pull-to-refresh **MUST** trigger sync for all active accounts concurrently
  AND IDLE notifications from any account **MUST** update the unified view in real time
  AND unified unread count **MUST** be the sum of INBOX unread counts across all accounts
  AND threads **MUST NOT** span accounts (cross-account threading prohibited)
  AND errors on some accounts **MUST NOT** prevent threads from healthy accounts from displaying
- **Priority**: Critical

---

**AC-ES-06**: Global Connection Pool Limits — **Not started**

- **Given**: Many active accounts (total connections approaching limit)
- **When**: A new connection is requested
- **Then**: Total IMAP connections across all accounts **MUST NOT** exceed 30
  AND when the limit is reached, the currently-viewed account **MUST** get priority for connection checkout
  AND **on iOS**, connections idle > 5 minutes in non-active accounts **MUST** be closed proactively
  AND **on macOS**, connections idle > 15 minutes in non-active accounts **MUST** be closed proactively
  AND if the global limit prevents a sync operation, it **MUST** be queued (not failed) with 30s timeout
- **Priority**: Medium

---

**AC-ES-07**: Sync Status Observability — **Not started**

- **Given**: Accounts in various sync states (syncing, error, idle, offline)
- **When**: The user views the thread list or account switcher
- **Then**: The toolbar **MUST** show: spinner + "Syncing..." while syncing, orange warning icon on error, `wifi.slash` + "Offline" when disconnected
  AND account switcher **MUST** show: green checkmark (synced < 10 min), orange warning (error), spinner (syncing), red badge (inactive)
  AND error banners **MUST** persist until resolved or dismissed; re-appear on next failure
  AND **on macOS**, per-account sync status **MUST** appear inline in the sidebar
  AND all indicators **MUST** have `accessibilityLabel` descriptions
  AND sync state changes **MUST** update UI within 500ms (NFR-SYNC-09)
- **Priority**: Critical

---

**AC-ES-08**: Sync Debug View — **Not started**

- **Given**: App with one or more accounts (including newly added accounts with no sync history)
- **When**: The user navigates to Settings → About → "Sync Diagnostics"
- **Then**: The view **MUST** display per-account: email, provider, auth mechanism, IMAP/SMTP host:port, security mode
  AND current `SyncPhase`, `lastSyncDate`, `lastSyncError`
  AND connection pool: active/max/idle connections, queued waiters
  AND IDLE status: active/reconnecting/disconnected, IDLE folder, time since last re-issue
  AND per-folder table: name, type, uidValidity, lastSyncDate, email count, unread count
  AND send queue counts: queued/sending/failed per account
  AND sync log: scrollable list of last 100 timestamped events
  AND "Copy Log" button **MUST** copy log to clipboard
  AND "Force Sync" button **MUST** trigger immediate full sync
  AND "Reset Sync State" button **MUST** clear sync state after user confirmation
  AND the `SyncLogger` ring buffer **MUST** be in-memory only (no disk persistence per Constitution P-01)
- **Priority**: Medium

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
| E-14 | Token refresh fails on one account during multi-account sync | Other accounts continue syncing; failed account shows error indicator | — (IOS-ES-01) |
| E-15 | > 5 active accounts on iOS (IDLE cap exceeded) | Most recently viewed 5 get IDLE; remainder fall back to 5-min polling | — (IOS-ES-02) |
| E-16 | All accounts fail to sync simultaneously | Combined error state displayed; user can retry all or per-account | — (IOS-ES-01) |
| E-17 | Background sync with 10 accounts in 30s budget | Priority order (most stale first); skip remaining when < 10s budget; schedule follow-up | — (IOS-ES-03) |
| E-18 | SMTP unreachable for one account, reachable for another | Queued emails for reachable account still sent; unreachable account shows "failed" | — (IOS-ES-04) |
| E-19 | Unified inbox with mixed healthy/errored accounts | Threads from healthy accounts display; per-account error indicator shown | — (IOS-ES-05) |
| E-20 | Global connection limit (30) reached | New connection requests queued with priority; timeout after 30s | — (IOS-ES-06) |
| E-21 | Newly added account with no sync history opens debug view | Debug view shows "No sync history" gracefully; no crash | — (IOS-ES-08) |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Initial sync (1K emails) | < 60s | 120s | Wall clock time on Wi-Fi | Fails if > 120s |
| Incremental sync (10 emails) | < 5s | — | Time from foreground to updated list | Fails if > 10s on 3 runs |
| Send email | < 3s | 5s | Time from send tap to SMTP completion | Fails if > 5s |
| Background sync (all accounts) | < 30s | 30s | Must complete within iOS budget | Task cancelled by OS if exceeded |
| IDLE event response | < 2s | — | Time from server event to UI refresh | — |
| Multi-account sync (3 accts, 10 emails each) | < 15s | 30s | Active inbox < 5s, all accounts < 15s (NFR-SYNC-06) | Fails if > 30s |
| Cross-account error isolation | 0 impact | 0 impact | Failure on one account must not affect others (NFR-SYNC-07) | Any cross-account failure propagation |
| Global connections | ≤ 30 | 30 | Total IMAP connections across all accounts (NFR-SYNC-08) | Exceeds 30 at any point |
| Sync status UI latency | < 500ms | 1s | State change to indicator update (NFR-SYNC-09) | Fails if > 1s on 3 consecutive updates |

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
