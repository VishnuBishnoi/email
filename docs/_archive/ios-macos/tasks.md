---
title: "iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

## Phase 1: Foundation

### IOS-F-01: Xcode Project Setup

- **Status**: `todo`
- **Spec ref**: Section 6 (Platform-Specific Considerations)
- **Validation ref**: AC-F-01
- **Description**: Create Xcode project with shared framework, iOS target, and macOS target. Configure build settings, deployment targets (iOS 17, macOS 14), and Swift 5.9. Set up folder structure per plan section 3.1.
- **Deliverables**:
  - [ ] Xcode project with three targets (Shared, iOS, macOS)
  - [ ] Build settings configured for both platforms
  - [ ] Project compiles and runs empty app on both targets
  - [ ] `.gitignore` for Xcode artifacts

### IOS-F-02: SwiftData Model Definitions

- **Status**: `todo`
- **Spec ref**: Section 4 (Data Model)
- **Validation ref**: AC-F-02
- **Description**: Define all SwiftData `@Model` classes matching the spec ERD: Account, Folder, Email, Thread, Attachment, SearchIndex.
- **Deliverables**:
  - [ ] `AccountEntity.swift` — Account model with all spec fields
  - [ ] `FolderEntity.swift` — Folder model with folder type enum
  - [ ] `EmailEntity.swift` — Email model with all spec fields
  - [ ] `ThreadEntity.swift` — Thread model with computed properties
  - [ ] `AttachmentEntity.swift` — Attachment model
  - [ ] SwiftData `ModelContainer` configuration
  - [ ] Unit tests for model relationships and constraints

### IOS-F-03: Keychain Manager

- **Status**: `todo`
- **Spec ref**: Section 7.1 (Authentication)
- **Validation ref**: AC-F-03
- **Description**: Implement a `KeychainManager` that stores and retrieves OAuth tokens with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.
- **Deliverables**:
  - [ ] `KeychainManager.swift` — save, read, delete, update operations
  - [ ] Scoped by account ID
  - [ ] Unit tests for CRUD operations
  - [ ] Error handling for Keychain failures

### IOS-F-04: OAuth 2.0 Manager

- **Status**: `todo`
- **Spec ref**: Section 5.1.3 (Gmail OAuth Flow)
- **Validation ref**: AC-F-04
- **Description**: Implement Gmail OAuth 2.0 with PKCE using `ASWebAuthenticationSession`. Support token exchange, storage, and refresh.
- **Deliverables**:
  - [ ] `OAuthManager.swift` — authorization flow, token exchange, refresh
  - [ ] PKCE code verifier/challenge generation
  - [ ] Integration with KeychainManager for token storage
  - [ ] Automatic token refresh before expiry
  - [ ] Error handling for auth failures, user cancellation
  - [ ] Integration test with real Gmail OAuth

### IOS-F-05: IMAP Client

- **Status**: `todo`
- **Spec ref**: Section 5.2 (Email Synchronization)
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
- **Spec ref**: Section 5.2.1, 5.2.2 (Sync Behavior, Sync State Machine)
- **Validation ref**: AC-F-06
- **Description**: Implement the sync engine that performs initial full sync, incremental sync, and real-time IDLE updates. Manage sync state per folder.
- **Deliverables**:
  - [ ] `SyncEngine.swift` — orchestrates sync lifecycle
  - [ ] Initial sync: fetch all emails within sync window
  - [ ] Incremental sync: fetch new emails since last UID
  - [ ] UIDVALIDITY change detection and re-sync
  - [ ] Sync state persistence (last UID, UIDVALIDITY per folder)
  - [ ] Thread grouping from References/In-Reply-To headers
  - [ ] Conflict resolution per spec 5.2.3
  - [ ] Unit tests for sync state machine transitions
  - [ ] Integration tests for initial + incremental sync

### IOS-F-07: SMTP Client

- **Status**: `todo`
- **Spec ref**: Section 5.5.2 (Send Behavior)
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
- **Spec ref**: Section 3 (Architecture)
- **Validation ref**: AC-F-08
- **Description**: Implement `EmailRepositoryImpl` conforming to `EmailRepositoryProtocol`. Bridges IMAP/SMTP clients with SwiftData store.
- **Deliverables**:
  - [ ] `EmailRepositoryImpl.swift` — all protocol methods
  - [ ] Fetch threads with pagination
  - [ ] Mark read/unread, star/unstar
  - [ ] Move to folder, delete, archive
  - [ ] IMAP APPEND for sent messages
  - [ ] Unit tests with mocked dependencies

### IOS-F-09: Account Repository

- **Status**: `todo`
- **Spec ref**: Section 5.1 (Account Management)
- **Validation ref**: AC-F-09
- **Description**: Implement `AccountRepositoryImpl` for account CRUD, token management, and configuration storage.
- **Deliverables**:
  - [ ] `AccountRepositoryImpl.swift` — all protocol methods
  - [ ] Add account (OAuth + IMAP validation)
  - [ ] Remove account (cascade delete all data)
  - [ ] Update account configuration
  - [ ] Token refresh delegation
  - [ ] Unit tests with mocked Keychain

### IOS-F-10: Domain Use Cases

- **Status**: `todo`
- **Spec ref**: Section 3 (Architecture)
- **Validation ref**: AC-F-10
- **Description**: Implement core domain use cases: SyncEmails, FetchThreads, SendEmail, ManageAccounts.
- **Deliverables**:
  - [ ] `SyncEmailsUseCase.swift`
  - [ ] `FetchThreadsUseCase.swift` — with filtering, sorting, pagination
  - [ ] `SendEmailUseCase.swift` — with queue support
  - [ ] `ManageAccountsUseCase.swift`
  - [ ] Unit tests for each use case with mocked repositories

---

## Phase 2: Core UI

### IOS-U-01: iOS Navigation Structure

- **Status**: `todo`
- **Spec ref**: Section 5.3.2 (Thread List Navigation)
- **Validation ref**: AC-U-01
- **Description**: Set up iOS navigation using NavigationStack with programmatic routing.
- **Deliverables**:
  - [ ] `iOSNavigationRouter.swift` — route definitions, navigation state
  - [ ] Tab bar or root navigation structure
  - [ ] Deep link support structure (for future use)

### IOS-U-02: Thread List View

- **Status**: `todo`
- **Spec ref**: Section 5.3 (Thread List Screen)
- **Validation ref**: AC-U-02
- **Description**: Implement the main thread list screen with ViewModel.
- **Deliverables**:
  - [ ] `ThreadListView.swift` — LazyVStack of thread rows
  - [ ] `ThreadListViewModel.swift` — fetch, filter, sort, pagination
  - [ ] Category tab bar (All, Primary, Social, Promotions, Updates)
  - [ ] Empty state views
  - [ ] Loading states

### IOS-U-03: Thread Row Component

- **Status**: `todo`
- **Spec ref**: Section 5.3.1 (Display Requirements)
- **Validation ref**: AC-U-03
- **Description**: Implement the thread row UI component.
- **Deliverables**:
  - [ ] `ThreadRowView.swift` — avatar, sender, subject, snippet, timestamp
  - [ ] Unread indicator (bold text + dot)
  - [ ] Star indicator
  - [ ] Attachment indicator
  - [ ] Category badge
  - [ ] Dynamic Type support
  - [ ] VoiceOver labels

### IOS-U-04: Thread List Interactions

- **Status**: `todo`
- **Spec ref**: Section 5.3.1 (Display Requirements)
- **Validation ref**: AC-U-04
- **Description**: Implement pull-to-refresh, swipe gestures, and multi-select.
- **Deliverables**:
  - [ ] Pull-to-refresh triggering sync
  - [ ] Swipe right to archive
  - [ ] Swipe left to delete
  - [ ] Long-press for multi-select mode
  - [ ] Batch actions toolbar (archive, delete, mark read/unread)

### IOS-U-05: Email Detail View

- **Status**: `todo`
- **Spec ref**: Section 5.4 (Email Detail Screen)
- **Validation ref**: AC-U-05
- **Description**: Implement the threaded email detail view.
- **Deliverables**:
  - [ ] `EmailDetailView.swift` — scrollable thread of messages
  - [ ] `EmailDetailViewModel.swift` — fetch thread, mark read, actions
  - [ ] Expand/collapse individual messages
  - [ ] Auto-expand latest unread, collapse read messages
  - [ ] Action buttons: reply, reply-all, forward, star, archive, delete
  - [ ] VoiceOver support

### IOS-U-06: Message Bubble Component

- **Status**: `todo`
- **Spec ref**: Section 5.4.1 (Display Requirements)
- **Validation ref**: AC-U-06
- **Description**: Implement the individual email message display.
- **Deliverables**:
  - [ ] `MessageBubbleView.swift` — sender, recipients, timestamp, body
  - [ ] HTML email rendering (WKWebView for HTML, Text for plain)
  - [ ] Quoted text collapsing
  - [ ] Inline image display
  - [ ] Link handling (open in system browser)

### IOS-U-07: Attachment Handling

- **Status**: `todo`
- **Spec ref**: Section 5.4.2 (Attachment Handling)
- **Validation ref**: AC-U-07
- **Description**: Implement attachment display, download, preview, and sharing.
- **Deliverables**:
  - [ ] `AttachmentView.swift` — metadata display (name, type, size)
  - [ ] Download with progress indicator
  - [ ] Inline preview for images and PDFs (QuickLook)
  - [ ] Share sheet integration
  - [ ] Auto-download gate for attachments > 5MB

### IOS-U-08: Composer View

- **Status**: `todo`
- **Spec ref**: Section 5.5 (Email Composer)
- **Validation ref**: AC-U-08
- **Description**: Implement the email composition screen.
- **Deliverables**:
  - [ ] `ComposerView.swift` — presented as sheet on iOS
  - [ ] `ComposerViewModel.swift` — compose, reply, reply-all, forward modes
  - [ ] To, CC, BCC recipient fields
  - [ ] Subject field (pre-filled for replies/forwards)
  - [ ] Body editor with basic formatting (bold, italic, links)
  - [ ] Send button with validation
  - [ ] Discard confirmation dialog

### IOS-U-09: Recipient Auto-Complete

- **Status**: `todo`
- **Spec ref**: Section 5.5.1 (Composition)
- **Validation ref**: AC-U-09
- **Description**: Implement recipient field with auto-complete from previously seen addresses.
- **Deliverables**:
  - [ ] `RecipientFieldView.swift` — token-based input with suggestions
  - [ ] Query previously seen sender/recipient addresses
  - [ ] Dropdown suggestion list
  - [ ] Email validation

### IOS-U-10: Draft Auto-Save

- **Status**: `todo`
- **Spec ref**: Section 5.5.1 (Composition)
- **Validation ref**: AC-U-10
- **Description**: Auto-save drafts locally every 30 seconds and sync to server.
- **Deliverables**:
  - [ ] Timer-based local save (SwiftData)
  - [ ] IMAP draft sync (APPEND to Drafts folder)
  - [ ] Resume draft from thread list or drafts folder
  - [ ] Delete draft on send

### IOS-U-11: Undo Send

- **Status**: `todo`
- **Spec ref**: Section 5.5.2 (Send Behavior)
- **Validation ref**: AC-U-11
- **Description**: Implement configurable undo-send delay.
- **Deliverables**:
  - [ ] Delay timer before actual SMTP send (default 5s)
  - [ ] Toast/snackbar with undo button
  - [ ] Cancel send during delay window
  - [ ] Configurable delay in settings

### IOS-U-12: Account Switcher

- **Status**: `todo`
- **Spec ref**: Section 5.3.1 (Display Requirements)
- **Validation ref**: AC-U-12
- **Description**: Multi-account navigation and unified inbox.
- **Deliverables**:
  - [ ] Account switcher sheet/popover
  - [ ] Per-account thread list
  - [ ] Unified inbox (all accounts merged, sorted by date)
  - [ ] Account indicator per thread in unified view

### IOS-U-13: Onboarding Flow

- **Status**: `todo`
- **Spec ref**: Section 5.9 (Onboarding)
- **Validation ref**: AC-U-13
- **Description**: First-launch onboarding experience.
- **Deliverables**:
  - [ ] Welcome screen with privacy value proposition
  - [ ] Account addition step (OAuth flow)
  - [ ] AI model download step (with skip option)
  - [ ] Feature tour (swipe gestures, AI features)
  - [ ] Completion and transition to thread list
  - [ ] Max 5 screens

### IOS-U-14: Settings Screen

- **Status**: `todo`
- **Spec ref**: Section 5.8 (Settings)
- **Validation ref**: AC-U-14
- **Description**: Implement settings screen with all V1 options.
- **Deliverables**:
  - [ ] `SettingsView.swift` — grouped list of settings
  - [ ] Sync window picker (per account)
  - [ ] Default account picker
  - [ ] Undo send delay picker
  - [ ] AI model management section
  - [ ] Theme picker (System/Light/Dark)
  - [ ] App lock toggle
  - [ ] Data management (clear cache, storage usage)
  - [ ] About section (version, licenses)

---

## Phase 3: AI Integration

### IOS-A-01: llama.cpp Integration

- **Status**: `todo`
- **Spec ref**: Section 5.6.1 (Engine Requirements)
- **Validation ref**: AC-A-01
- **Description**: Integrate llama.cpp as SPM dependency. Verify compilation on iOS and macOS.
- **Deliverables**:
  - [ ] SPM package dependency added
  - [ ] Swift bridging configured
  - [ ] Build succeeds on both iOS and macOS targets
  - [ ] Basic smoke test (load model, run simple inference)

### IOS-A-02: Llama Engine Wrapper

- **Status**: `todo`
- **Spec ref**: Section 5.6.1 (Engine Requirements)
- **Validation ref**: AC-A-02
- **Description**: Swift wrapper around llama.cpp C API exposing protocol-based interface.
- **Deliverables**:
  - [ ] `LlamaEngine.swift` — load model, run inference, unload model
  - [ ] Protocol-based interface (`AIEngineProtocol`)
  - [ ] Thread-safe inference execution
  - [ ] Memory management (model loading/unloading)
  - [ ] Inference cancellation support
  - [ ] Unit tests with small test model

### IOS-A-03: Model Manager

- **Status**: `todo`
- **Spec ref**: Section 5.6.1 (Engine Requirements)
- **Validation ref**: AC-A-03
- **Description**: Download, cache, and manage GGUF model files.
- **Deliverables**:
  - [ ] `ModelManager.swift` — download, verify, cache, delete
  - [ ] Download progress reporting
  - [ ] Download cancellation
  - [ ] Storage usage reporting
  - [ ] Model integrity verification (checksum)
  - [ ] Graceful degradation when no model available

### IOS-A-04 to IOS-A-07: Categorization Pipeline

- **Status**: `todo`
- **Spec ref**: Section 5.6.2 (Email Categorization)
- **Validation ref**: AC-A-04
- **Description**: End-to-end email categorization from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for categorization
  - [ ] `CategorizeEmailUseCase.swift` — single and batch
  - [ ] `AIProcessingQueue.swift` — background batch processing
  - [ ] Category badge in thread row
  - [ ] Category tab filtering in thread list
  - [ ] Manual re-categorization override
  - [ ] Unit tests for prompt parsing and categorization logic

### IOS-A-08 to IOS-A-10: Smart Reply Pipeline

- **Status**: `todo`
- **Spec ref**: Section 5.6.3 (Smart Reply)
- **Validation ref**: AC-A-05
- **Description**: End-to-end smart reply from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for smart reply generation
  - [ ] `SmartReplyUseCase.swift` — generate up to 3 suggestions
  - [ ] Smart reply chip UI in email detail
  - [ ] Tap to insert into composer
  - [ ] Async generation (non-blocking UI)
  - [ ] Unit tests for prompt construction and response parsing

### IOS-A-11 to IOS-A-13: Summarization Pipeline

- **Status**: `todo`
- **Spec ref**: Section 5.6.4 (Thread Summarization)
- **Validation ref**: AC-A-06
- **Description**: End-to-end thread summarization from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for summarization
  - [ ] `SummarizeThreadUseCase.swift`
  - [ ] Summary display at top of email detail
  - [ ] On-demand trigger + auto for 3+ message threads
  - [ ] Summary caching
  - [ ] Unit tests

### IOS-A-14 to IOS-A-18: Semantic Search Pipeline

- **Status**: `todo`
- **Spec ref**: Section 5.6.5, 5.7 (Semantic Search, Search)
- **Validation ref**: AC-A-07
- **Description**: End-to-end semantic search from indexing to UI.
- **Deliverables**:
  - [ ] `EmbeddingEngine.swift` — generate embeddings from text
  - [ ] `VectorStore.swift` — store and query embeddings
  - [ ] `SearchIndexManager.swift` — build and incrementally update index
  - [ ] `SearchEmailsUseCase.swift` — semantic + exact combined search
  - [ ] `SearchView.swift` — search bar, results, filters
  - [ ] `SearchViewModel.swift`
  - [ ] Recent searches persistence
  - [ ] Unit and integration tests

### IOS-A-19: AI Model Download in Onboarding

- **Status**: `todo`
- **Spec ref**: Section 5.9 (Onboarding)
- **Validation ref**: AC-A-08
- **Description**: Integrate model download step into onboarding flow.
- **Deliverables**:
  - [ ] Model download screen with progress
  - [ ] Skip option
  - [ ] Resume download if interrupted
  - [ ] Size disclosure before download

---

## Phase 4: macOS

### IOS-M-01 to IOS-M-10: macOS UI

- **Status**: `todo`
- **Spec ref**: Section 6.2 (macOS)
- **Validation ref**: AC-M-01 through AC-M-05
- **Description**: macOS-specific UI implementation using shared domain/data layer.
- **Deliverables**:
  - [ ] macOS target build configuration
  - [ ] `MainWindowView.swift` — NavigationSplitView three-pane
  - [ ] `SidebarView.swift` — accounts and folder tree
  - [ ] macOS thread list adaptation
  - [ ] macOS email detail adaptation
  - [ ] `MacComposerWindow.swift` — separate window
  - [ ] `AppCommands.swift` — keyboard shortcuts (Cmd+N, Cmd+R, Cmd+Delete, Cmd+F)
  - [ ] macOS toolbar
  - [ ] Drag-and-drop for attachments
  - [ ] macOS Settings scene

---

## Phase 5: Polish and Validation

### IOS-P-01: Accessibility Audit

- **Status**: `todo`
- **Spec ref**: Constitution TC-05
- **Validation ref**: AC-P-01
- **Deliverables**:
  - [ ] VoiceOver audit on all screens (iOS + macOS)
  - [ ] Dynamic Type validation (all text scales correctly)
  - [ ] Color contrast audit (WCAG 2.1 AA)
  - [ ] Fix all accessibility issues found

### IOS-P-02: Performance Profiling

- **Status**: `todo`
- **Spec ref**: Section 8 (Performance Requirements), Constitution TC-04
- **Validation ref**: AC-P-02
- **Deliverables**:
  - [ ] Instruments profiling: CPU, memory, energy
  - [ ] Cold start time measurement
  - [ ] Thread list scroll frame rate measurement
  - [ ] AI inference time measurement
  - [ ] Fix any metrics exceeding targets

### IOS-P-03: Memory Optimization

- **Status**: `todo`
- **Spec ref**: Section 8 (Performance Requirements)
- **Validation ref**: AC-P-03
- **Deliverables**:
  - [ ] AI model unloading after inference completes
  - [ ] Memory pressure handling (unload model, reduce cache)
  - [ ] Lazy image loading in email detail
  - [ ] Pagination for large threads

### IOS-P-04 to IOS-P-07: Edge Cases and Features

- **Status**: `todo`
- **Spec ref**: Various
- **Validation ref**: AC-P-04 through AC-P-07
- **Deliverables**:
  - [ ] Offline mode: read cached emails, queue sends, surface sync errors on reconnect
  - [ ] Error handling audit: all error paths have user-facing messages
  - [ ] App lock (biometric/passcode) implementation
  - [ ] Background app refresh for periodic sync

### IOS-P-08: Full Validation Suite

- **Status**: `todo`
- **Spec ref**: All
- **Validation ref**: All AC items
- **Deliverables**:
  - [ ] Run all acceptance criteria from `validation.md`
  - [ ] All critical and high priority ACs pass
  - [ ] Performance metrics within targets
  - [ ] Zero critical bugs remaining
