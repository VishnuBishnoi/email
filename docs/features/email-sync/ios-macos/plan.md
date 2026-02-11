---
title: "Email Sync — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/email-sync/spec.md
version: "1.3.0"
status: locked
assignees:
  - Core Team
target-milestone: V1.0
updated: 2026-02-11
---

# Email Sync — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the IMAP client, sync engine, SMTP client, email repository, and core domain use cases. These form the data engine that powers all email features.

**Current status (v1.2.0):** IMAP client, sync engine, IDLE monitoring, background sync, attachment download, and all domain use cases are implemented and tested (549 tests, 38 suites). SMTP client remains TODO.

---

## 2. Platform Context

Refer to Foundation plan Section 2 for OS versions, device targets, and platform guidelines.

- **Cross-platform:** All sync code compiles for both iOS and macOS. Platform-specific code (`BGAppRefreshTask`, `UIImage`-based favicons) is gated with `#if os(iOS)` / `#if canImport(UIKit)`.

---

## 3. Architecture Mapping

### Key Classes

```mermaid
classDiagram
    class SyncEmailsUseCaseProtocol {
        <<protocol>>
        +syncAccount(accountId) void
        +syncFolder(accountId, folderId) void
    }

    class SyncEmailsUseCase {
        -accountRepository: AccountRepositoryProtocol
        -emailRepository: EmailRepositoryProtocol
        -keychainManager: KeychainManagerProtocol
        -connectionProvider: ConnectionProviding
    }

    class IDLEMonitorUseCaseProtocol {
        <<protocol>>
        +monitor(accountId, folderImapPath) AsyncStream~IDLEEvent~
    }

    class DownloadAttachmentUseCaseProtocol {
        <<protocol>>
        +download(attachment) String
        +securityWarning(for filename) String?
        +requiresCellularWarning(sizeBytes) Bool
    }

    class BackgroundSyncScheduler {
        +registerTasks() void
        +scheduleNextSync() void
        -handleBackgroundSync(task) void
    }

    class ConnectionProviding {
        <<protocol>>
        +checkoutConnection(accountId, host, port, email, accessToken) IMAPClientProtocol
        +checkinConnection(client, accountId) void
    }

    class IMAPClientProtocol {
        <<protocol>>
        +connect() void
        +listFolders() [IMAPFolderInfo]
        +selectFolder(path) (UInt32, UInt32)
        +fetchHeaders(uids) [IMAPEmailHeader]
        +fetchBodies(uids) [IMAPEmailBody]
        +fetchBodyPart(uid, section) Data
        +startIDLE(onNewMail) void
        +stopIDLE() void
        +storeFlags(uids, flags, add) void
    }

    SyncEmailsUseCaseProtocol <|.. SyncEmailsUseCase
    SyncEmailsUseCase --> ConnectionProviding
    SyncEmailsUseCase --> IMAPClientProtocol
    IDLEMonitorUseCaseProtocol <|.. IDLEMonitorUseCase
    IDLEMonitorUseCase --> ConnectionProviding
    BackgroundSyncScheduler --> SyncEmailsUseCaseProtocol
    DownloadAttachmentUseCaseProtocol <|.. DownloadAttachmentUseCase
    DownloadAttachmentUseCase --> ConnectionProviding
    ConnectionPool ..|> ConnectionProviding
```

### Files

| File | Layer | Purpose | Status |
|------|-------|---------|--------|
| `IMAPClient.swift` | Data/Network | IMAP connection and commands | Done |
| `IMAPSession.swift` | Data/Network | Connection lifecycle | Done |
| `ConnectionPool.swift` | Data/Network | Multi-account connection pooling via `ConnectionProviding` | Done |
| `IMAPClientProtocol.swift` | Domain/Protocols | Protocol for IMAP operations (enables mock injection) | Done |
| `MIMEDecoder.swift` | Data/Network | Content-Transfer-Encoding decode (base64, quoted-printable) | Done |
| `BackgroundSyncScheduler.swift` | Data/Sync | `BGAppRefreshTask` registration + handler (iOS only) | Done |
| `EmailRepositoryImpl.swift` | Data/Repositories | Email CRUD bridging IMAP + SwiftData | Done |
| `SyncEmailsUseCase.swift` | Domain/UseCases | Full/incremental sync orchestration with threading + dedup | Done |
| `IDLEMonitorUseCase.swift` | Domain/UseCases | Real-time IDLE monitoring via `AsyncStream<IDLEEvent>` | Done |
| `DownloadAttachmentUseCase.swift` | Domain/UseCases | Lazy IMAP body part fetch + transfer-encoding decode | Done |
| `ManageThreadActionsUseCase.swift` | Domain/UseCases | Archive/delete/star/read with IMAP flag sync | Done |
| `FetchThreadsUseCase.swift` | Domain/UseCases | Thread fetching with AI category filters + pagination | Done |
| `ManageAccountsUseCase.swift` | Domain/UseCases | Account CRUD + re-authentication | Done |
| `SMTPClient.swift` | Data/Network | Email sending (not yet implemented) | TODO |
| `SendEmailUseCase.swift` | Domain/UseCases | Send + offline queue (SMTP stubbed) | Partial |

### Presentation Wiring

| File | Integration Point |
|------|-------------------|
| `VaultMailApp.swift` | Creates `BackgroundSyncScheduler`, calls `registerTasks()` + `scheduleNextSync()` at launch |
| `ContentView.swift` | Passes `syncEmails` dependency to `OnboardingView` |
| `OnboardingView.swift` | `completeOnboarding()` triggers background `syncAccount()` for all added accounts |
| `ThreadListView.swift` | `initialLoad()` calls `syncAccount()` + starts `IDLEMonitorUseCase`; IDLE restarts on folder change; `.refreshable` calls `syncFolder()` |
| `Config/VaultMail.entitlements` | `com.apple.developer.background-modes` = `fetch` |
| `VaultMail/Info.plist` | `BGTaskSchedulerPermittedIdentifiers` = `com.vaultmail.app.sync` |

---

## 4. Implementation Phases

| Task ID | Description | Spec FRs | Dependencies | Status |
|---------|-------------|----------|-------------|--------|
| IOS-F-05 | IMAP client (connect, authenticate, list folders, IDLE, connection management) | FR-SYNC-01, FR-SYNC-03, FR-SYNC-09 | IOS-F-04 (Account Management) | **Done** |
| IOS-F-06 | Sync engine (full sync, incremental, IDLE monitor, background sync, threading, flag sync, attachments) | FR-SYNC-01, FR-SYNC-02, FR-SYNC-04, FR-SYNC-05, FR-SYNC-06, FR-SYNC-08, FR-SYNC-10 | IOS-F-05 | **Done** |
| IOS-F-07 | SMTP client (send, queue) | FR-SYNC-07 | IOS-F-04 (Account Management) | TODO |
| IOS-F-08 | Email repository implementation | All FRs | IOS-F-02 (Foundation), IOS-F-06, IOS-F-07 | **Done** (IMAP APPEND + LRU cache remaining) |
| IOS-F-10 | Domain use cases (Sync, Fetch, Send, ManageAccounts, IDLE, Download, Actions) | Foundation Section 6 | IOS-F-08, IOS-F-09 (Account Management) | **Done** |

---

## 5. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Sync logic in `SyncEmailsUseCase` (not separate `SyncEngine.swift`) | Follows MV pattern — use cases own business logic. No need for additional indirection layer. |
| `ConnectionProviding` protocol over direct `ConnectionPool` dependency | Enables mock injection for tests. `ConnectionPool` conforms via extension. |
| `IDLEMonitorUseCase` as separate use case (not embedded in sync) | IDLE has different lifecycle — long-lived stream vs. one-shot sync. Separate use case allows clean `.task(id:)` integration. |
| `BackgroundSyncScheduler` as `@Observable @MainActor` class | Matches app-wide services pattern. `@Observable` for future UI binding (sync status). iOS-only via `#if os(iOS)`. |
| Attachment download via lazy `FETCH BODY[section]` | Avoids downloading all attachments during sync. `bodySection` (MIME part ID) stored during initial sync for deferred fetch. |
| SHA256-based stable email ID (`stableId(accountId:, messageId:)`) | Ensures cross-folder dedup. Same email in INBOX and All Mail maps to single SwiftData record. |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation | Status |
|------|-----------|--------|------------|--------|
| IMAP protocol edge cases (Gmail quirks) | Medium | Medium | Extensive integration tests with real Gmail account; handle known Gmail IMAP quirks from proposal section 3.3.1 | Mitigated — IDLE 25-min timeout handled, UIDVALIDITY change detected |
| llama.cpp Swift integration for indexing | Medium | High | Spike in Phase 3; indexing can be added incrementally | Unchanged |
| Background sync iOS limitations | High | Medium | Implemented `BGAppRefreshTask` with 15-min interval and 30-sec budget; graceful expiration handler | **Resolved** |
| OAuth token expiry during long sync | Medium | Medium | Token refresh with fallback to keychain cached token; `SyncError.tokenRefreshFailed` propagated to UI | **Resolved** |

---

## 7. Test Coverage

| Test Suite | Tests | Scope |
|-----------|-------|-------|
| `IDLEMonitorUseCaseTests` | 5 | IDLE stream emission, error handling, connection lifecycle |
| `BackgroundSyncSchedulerTests` | 4 | Task identifier, initialization, registration, scheduling |
| `DownloadAttachmentUseCaseTests` | 20+ | IMAP download, base64/QP/7bit decode, security warnings, cellular warnings, errors |
| All suites combined | 549 | 38 suites, all passing |
