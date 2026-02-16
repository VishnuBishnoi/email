---
title: "Email Sync — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-sync/ios-macos/plan.md
version: "1.4.0"
status: draft
updated: 2026-02-16
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

- **Status**: `done` (partial — PLAIN auth, STARTTLS, conditional sent append, multi-auth errors deferred to IOS-MP/IOS-ES)
- **Spec ref**: Email Sync spec, FR-SYNC-07
- **Validation ref**: AC-F-07
- **Description**: Implement SMTP client supporting provider-configured authentication (XOAUTH2 or PLAIN), transport security (implicit TLS or STARTTLS), and conditional sent-folder append via `requiresSentAppend`. Includes offline send queue with auth-mechanism-aware error handling.
- **Deliverables**:
  - [x] `SMTPClient.swift` — actor with connect, authenticate (XOAUTH2), send; connection retry with exponential backoff (5s/15s/45s)
  - [x] `SMTPSession.swift` — 395 lines; Network.framework, port 465 implicit TLS, SASL base64 encoding, dot-stuffing, multi-line response parsing, timeout guards
  - [x] MIME message construction via `MIMEEncoder.swift` (headers, body, attachments)
  - [x] TLS enforcement (port 465 implicit TLS)
  - [x] Send queue via `ComposeEmailUseCase.executeSend()` — full pipeline: `.queued` → `.sending` → `.sent`/`.failed`, OAuth token refresh, real `smtpClient.sendMessage()`
  - [x] Retry logic with exponential backoff (3 retries)
  - [x] `SMTPClientProtocol` + `MockSMTPClient` for testability
  - [ ] PLAIN auth support for SMTP (SASL PLAIN over TLS) — deferred to IOS-MP-02
  - [ ] STARTTLS transport for SMTP (port 587) — deferred to IOS-MP-03
  - [ ] Conditional sent-folder APPEND via `requiresSentAppend` flag — deferred to IOS-MP-12
  - [ ] Auth-mechanism-aware error handling: OAuth → token refresh; PLAIN → credential error (no refresh) — deferred to IOS-ES-04
- **Notes**: Current implementation covers Gmail XOAUTH2 + implicit TLS (port 465). Provider-agnostic extensions (PLAIN auth, STARTTLS, conditional sent append, multi-auth error handling) are tracked in Multi-Provider IMAP tasks (IOS-MP-02, IOS-MP-03, IOS-MP-12) and Email Sync multi-account tasks (IOS-ES-04). See FR-SYNC-07 spec v1.3.4 for full provider-agnostic requirements.

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
  - [ ] IMAP APPEND for sent messages — deferred to IOS-MP-12 (conditional `requiresSentAppend`)
  - [x] Lazy attachment download on user tap via `DownloadAttachmentUseCase` with real IMAP `fetchBodyPart()` (FR-SYNC-08)
  - [ ] Attachment cache management (500MB LRU per account, FR-SYNC-08)
  - [x] Cellular download warning for attachments >=25MB (FR-SYNC-08)
  - [x] Security warnings for dangerous file extensions (exe, bat, pkg, dmg, etc.) (FR-ED-03)
  - [x] Unit tests: `DownloadAttachmentUseCaseTests` (20+ tests covering IMAP download, base64/QP/7bit decoding, security warnings, cellular warnings, error cases)
- **Notes**: Attachment download is fully wired end-to-end: `bodySection` stored during sync, lazy `FETCH BODY[section]` on tap, Content-Transfer-Encoding decode (base64, quoted-printable, 7bit/8bit), local file persist. IMAP APPEND deferred to IOS-MP-12 (provider-conditional). Cache eviction (500MB LRU) still TODO.

### IOS-F-10: Domain Use Cases

- **Status**: `done`
- **Spec ref**: Foundation spec Section 6
- **Validation ref**: AC-F-10
- **Description**: Implement core domain use cases: SyncEmails, FetchThreads, SendEmail, ManageAccounts, IDLE monitoring, attachment download, background sync.
- **Deliverables**:
  - [x] `SyncEmailsUseCase.swift` — full/incremental sync with connection pooling, threading, dedup, contact extraction
  - [x] `FetchThreadsUseCase.swift` — with AI category filtering, sorting, cursor-based pagination
  - [x] `SendEmailUseCase.swift` — with outbox queue and full SMTP send pipeline via `ComposeEmailUseCase.executeSend()`
  - [x] `ManageAccountsUseCase.swift` — CRUD + re-authentication flow
  - [x] `IDLEMonitorUseCase.swift` — real-time folder monitoring via IMAP IDLE (`AsyncStream<IDLEEvent>`)
  - [x] `DownloadAttachmentUseCase.swift` — lazy IMAP body part fetch with transfer-encoding decode
  - [x] `ManageThreadActionsUseCase.swift` — archive, delete, star, mark read/unread with IMAP flag sync
  - [x] `MarkReadUseCase.swift` — auto-mark-read on thread open
  - [x] Unit tests for use cases with mocked repositories (627+ tests across 54 suites, all passing)

---

## Multi-Account Sync (v1.3.0+)

> The following tasks implement the multi-account sync requirements added in Email Sync spec v1.3.0 (FR-SYNC-11 through FR-SYNC-18). These depend on the existing sync infrastructure (IOS-F-05 through IOS-F-10) and work alongside the Multi-Provider IMAP tasks (IOS-MP-01 through IOS-MP-15).

### IOS-ES-01: Concurrent Multi-Account Sync Orchestration

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-11
- **Validation ref**: AC-ES-01
- **Plan phase**: Multi-Account Sync
- **Description**: Implement a `SyncCoordinator` that orchestrates multi-account sync via structured concurrency (`TaskGroup`). Each account syncs independently with error isolation.
- **Deliverables**:
  - [ ] `SyncCoordinator.swift` — `@Observable @MainActor` class; orchestrates sync for all active accounts
  - [ ] Foreground launch: trigger sync for all active accounts concurrently via `TaskGroup`
  - [ ] Priority ordering: currently-viewed account syncs inbox first; remaining accounts begin concurrently after
  - [ ] Independent tasks: each account's sync in an independent `Task`; failure/timeout/cancellation on one account MUST NOT affect others
  - [ ] Account switch trigger: incremental sync for switched-to account if `lastSyncDate` > 5 minutes ago
  - [ ] Per-account independent sync state machine instances (per FR-SYNC-04)
  - [ ] Token refresh failure on Account A MUST NOT interrupt Account B
  - [ ] Cancellation: account removal → cancel all sync tasks + disconnect pool + stop IDLE; app background → graceful cancel with checkpoint preservation
  - [ ] Error handling: all accounts fail → combined error state; partial failure → show threads from healthy accounts + per-account error indicators
  - [ ] Unit tests with mocked sync use cases for isolation, priority ordering, and cancellation behavior
- **Notes**: This is the central orchestration layer. Views observe the coordinator's per-account `SyncPhase` (FR-SYNC-17), not individual sync use cases.

### IOS-ES-02: Per-Account IDLE Monitoring

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-12
- **Validation ref**: AC-ES-02
- **Plan phase**: Multi-Account Sync
- **Description**: Extend IDLE monitoring to maintain concurrent IDLE connections for multiple accounts. Enforce platform-specific resource limits (iOS 5-cap, macOS uncapped).
- **Deliverables**:
  - [ ] Per-account IDLE: one IDLE connection per active account monitoring INBOX
  - [ ] Provider-specific IDLE refresh interval from provider registry (FR-MPROV-09)
  - [ ] Independent IDLE connections: disconnect/failure on one account MUST NOT affect others
  - [ ] **iOS resource limits**: global maximum 5 concurrent IDLE connections; prioritize most recently viewed accounts; deprioritized accounts fall back to periodic incremental sync every 5 minutes
  - [ ] **macOS**: no IDLE cap; one IDLE connection per active account without artificial limit
  - [ ] IDLE event routing: `EXISTS` on any account → incremental sync for that account's INBOX only
  - [ ] Background update: if user is viewing different account, update source account's unread counts + badge in account switcher
  - [ ] Unified inbox: if user is viewing "All Accounts", new threads appear inline
  - [ ] Lifecycle: start IDLE on foreground, tear down on background (iOS); start on window open, tear down on last window close (macOS)
  - [ ] Account add → start IDLE; account remove → stop IDLE
  - [ ] Per-account exponential backoff for IDLE reconnection (2s initial, doubling to 60s max)
  - [ ] Unit tests for IDLE cap enforcement, deprioritization fallback, event routing, and lifecycle
- **Notes**: Each IDLE connection counts against the account's connection pool limit (FR-SYNC-09). The iOS 5-cap is a MUST; macOS exemption is per Section 7.

### IOS-ES-03: Background Sync for Multiple Accounts

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-13
- **Validation ref**: AC-ES-03
- **Plan phase**: Multi-Account Sync
- **Description**: Adapt `BGAppRefreshTask` background sync for multi-account operation within the iOS 30-second time budget. macOS uses a periodic `Timer` instead.
- **Deliverables**:
  - [ ] Update `BackgroundSyncScheduler.swift` — multi-account prioritization within 30s budget
  - [ ] Priority order: most stale `lastSyncDate` first; ties broken by most recently viewed
  - [ ] Check `Task.isCancelled` before each account; skip remaining if < 10s budget estimated
  - [ ] Each account: headers-only, INBOX only
  - [ ] Schedule follow-up `BGAppRefreshTask` if not all accounts synced
  - [ ] One account's background sync failure MUST NOT prevent subsequent accounts
  - [ ] **macOS**: periodic `Timer` (5-min interval) for all accounts with `lastSyncDate` > 5 min; full incremental sync (headers + bodies); runs while any app window is open
  - [ ] Unit tests for multi-account prioritization, budget management, and follow-up scheduling
- **Notes**: iOS background sync already exists (IOS-F-06). This extends it from single-account to multi-account with time budget management. macOS uses Timer since `BGAppRefreshTask` is not available.

### IOS-ES-04: Per-Account Offline Send Queue

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-14
- **Validation ref**: AC-ES-04
- **Plan phase**: Multi-Account Sync
- **Description**: Extend the offline send queue to operate correctly across multiple accounts with different providers and auth mechanisms.
- **Deliverables**:
  - [ ] Account-scoped sending: each queued email associated with `Email.accountId`
  - [ ] Queue processor resolves SMTP credentials (OAuth token or app password) from correct account's Keychain entry
  - [ ] Connect to correct account's SMTP server using provider-specific settings (host, port, security, auth mechanism)
  - [ ] Independent delivery: if Account A's SMTP is unreachable, still attempt Account B's queue
  - [ ] Group queued emails by account; process each account's queue independently
  - [ ] Outbox view: display which account each queued email sends from (avatar/email label)
  - [ ] Auth-mechanism-aware error handling: PLAIN → "Check your app password" (no token refresh); OAuth → trigger token refresh
  - [ ] Unit tests for multi-account queue processing, independent delivery, and auth-specific errors
- **Notes**: Extends existing send queue (IOS-F-07). The queue processor already exists — this adds multi-account routing and auth-mechanism-aware error handling.

### IOS-ES-05: Unified Inbox Behavior

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-15
- **Validation ref**: AC-ES-05
- **Plan phase**: Multi-Account Sync
- **Description**: Implement unified "All Accounts" inbox experience that interleaves threads from all active accounts with account indicators.
- **Deliverables**:
  - [ ] Thread interleaving: threads from all active accounts sorted by `latestDate` (newest first)
  - [ ] Account indicator on each thread row (colored dot, avatar, or email label)
  - [ ] Pull-to-refresh: trigger incremental sync for all active accounts concurrently
  - [ ] Real-time updates: IDLE notification from any account updates unified view
  - [ ] Unified unread count: sum of INBOX unread counts across all active accounts
  - [ ] Category tab unread counts aggregate across all accounts
  - [ ] Error resilience: display threads from healthy accounts when some accounts have errors; per-account error indicator (banner/badge)
  - [ ] Cross-account threading: threads MUST NOT span accounts; subject-based fallback scoped to single account
  - [ ] Unit tests for thread interleaving, unread count aggregation, and error resilience
- **Notes**: Uses `FetchThreadsUseCase` extended with an "all accounts" mode. Account indicator design coordinated with Thread List feature.

### IOS-ES-06: Global Connection Pool Limits

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-16
- **Validation ref**: AC-ES-06
- **Plan phase**: Multi-Account Sync
- **Description**: Enforce global connection limit (30 max across all accounts) with priority queuing and platform-specific idle cleanup.
- **Deliverables**:
  - [ ] Global limit: total IMAP connections across all accounts MUST NOT exceed 30
  - [ ] Priority queuing: when global limit reached, currently-viewed account gets priority
  - [ ] Cross-account connection return: when any connection is returned, serve highest-priority waiter across all accounts
  - [ ] **iOS idle cleanup**: connections idle > 5 minutes in non-active accounts closed proactively
  - [ ] **macOS idle cleanup**: connections idle > 15 minutes in non-active accounts closed proactively
  - [ ] Debug logging when connections closed due to idle timeout
  - [ ] Queue timeout: 30s per FR-SYNC-09; queued (not failed) when limit prevents sync start
  - [ ] Unit tests for global limit enforcement, priority ordering, idle cleanup per platform
- **Notes**: Overlaps with IOS-MP-13 (per-provider connection pool). IOS-ES-06 handles the global cross-account limit; IOS-MP-13 handles per-provider limits. Both modify `ConnectionPool.swift`.

### IOS-ES-07: Sync Status Observability

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-17
- **Validation ref**: AC-ES-07
- **Plan phase**: Multi-Account Sync
- **Description**: Implement sync status visibility: per-account sync state tracking, home screen indicators, account switcher badges, and error banner persistence.
- **Deliverables**:
  - [ ] Per-account sync state: `syncState` (`SyncPhase`), `lastSyncDate`, `lastSyncError`, `idleStatus` (`IDLEStatus`), `syncProgress` (`SyncProgress`)
  - [ ] `SyncProgress` model: `currentFolder`, `foldersCompleted`/`foldersTotal`, `emailsFetchedInCurrentFolder`/`emailsTotalInCurrentFolder`
  - [ ] Thread list toolbar indicator: syncing (spinner + "Syncing..." / "Syncing N accounts..."), error (orange warning icon → popover with account errors), up to date (clean), offline (`wifi.slash` + "Offline"), IDLE active (subtle green "Live" dot)
  - [ ] Network state detection via `NetworkMonitor.isConnected` for offline indicator
  - [ ] Account switcher badges: green checkmark (synced < 10 min), orange warning (last sync failed → error on tap), spinner (syncing), red badge (inactive, requires re-auth)
  - [ ] Error banner persistence: persists until resolved or dismissed; re-appears on next failure; multi-account summary "Sync failed for N accounts" with "Details" button
  - [ ] **macOS sidebar**: per-account sync status inline (spinner, warning icon with tooltip, red badge, normal state); optional global sync summary in sidebar bottom bar
  - [ ] Accessibility: `accessibilityLabel` on all indicators; sync state changes announced via `AccessibilityNotification.Announcement`
  - [ ] Sync status latency < 500ms from state change to UI update (NFR-SYNC-09)
  - [ ] Unit tests for sync phase transitions, indicator state derivation, and error banner logic
- **Notes**: The `SyncCoordinator` (IOS-ES-01) exposes per-account sync state. This task builds the UI layer that observes it.

### IOS-ES-08: Sync Debug View

- **Status**: `todo`
- **Spec ref**: Email Sync spec, FR-SYNC-18
- **Validation ref**: AC-ES-08
- **Plan phase**: Multi-Account Sync
- **Description**: Implement a diagnostic view accessible from Settings for troubleshooting sync issues. Includes structured sync event logging.
- **Deliverables**:
  - [ ] `SyncLogger.swift` — `@Observable` service; in-memory ring buffer (max 500 entries, LRU eviction); `SyncEvent` entries with timestamp, accountId, eventType, detail, severity
  - [ ] Ring buffer is in-memory only — no disk persistence (Constitution P-01)
  - [ ] `SyncLogger` injected via `@Environment`
  - [ ] `SyncDebugView.swift` — accessible from Settings → About → "Sync Diagnostics"
  - [ ] Available in `#if DEBUG` builds without toggle; MAY be hidden behind long-press in production (OQ-01)
  - [ ] Per-account display: account summary (email, provider, auth, IMAP/SMTP host:port, security mode)
  - [ ] Sync state: current `SyncPhase`, `lastSyncDate`, `lastSyncError`
  - [ ] Connection pool: active/max connections, idle connections, queued waiters
  - [ ] IDLE status: active/reconnecting/disconnected, IDLE folder, time since last re-issue, provider refresh interval
  - [ ] Folder sync status: per-folder table (name, type, uidValidity, lastSyncDate, email count, unread count)
  - [ ] Send queue: queued/sending/failed email counts per account
  - [ ] Sync log: scrollable list of last 100 events (timestamped), including: sync started/completed/failed, IDLE notifications, token refresh, connection pool checkout/checkin, folder sync, errors
  - [ ] "Copy Log" button — copies sync log to clipboard for support requests (OQ-03: consider stripping email addresses)
  - [ ] "Force Sync" button per account — triggers immediate full sync regardless of `lastSyncDate`
  - [ ] "Reset Sync State" button per account — clears uidValidity, lastSyncedUID, lastSyncDate for all folders; requires confirmation dialog
  - [ ] **macOS**: accessible from Settings window (Cmd+,) → About tab → "Sync Diagnostics" (per FR-MAC-10)
  - [ ] Gracefully handles accounts with no sync history (newly added)
  - [ ] Unit tests for `SyncLogger` ring buffer, event emission, and LRU eviction
- **Notes**: The sync engine emits `SyncEvent` entries to the `SyncLogger` throughout all sync operations. The debug view is purely observational — it reads from the logger but doesn't affect sync behavior.
