---
title: "Notifications — iOS/macOS Task Breakdown"
platform: iOS
plan-ref: docs/features/notifications/ios-macos/plan.md
version: "1.0.0"
status: locked
updated: 2026-02-19
---

# Notifications — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### Existing Infrastructure (Completed)

- `SettingsStore` (`Shared/Services/SettingsStore.swift`) — per-account `notificationsEnabled` toggle already exists
- `BackgroundSyncScheduler` (`Data/Sync/BackgroundSyncScheduler.swift`) — iOS-only, `#if os(iOS)`, `handleBackgroundSync(task:)` with `Task { @MainActor in }` block
- `SyncEmailsUseCase` returns `@discardableResult [Email]` from `syncAccount()` / `syncFolder()` / `syncAccountInboxFirst()`
- `IDLEMonitorUseCase` — `.newMail` events trigger `syncFolder()` in `ThreadListView`
- `MacOSMainView` — 3 sync paths (initial load, toolbar refresh, IDLE)
- `ComposeEmailUseCase.saveDraft()` — 11-parameter signature
- `MarkReadUseCase.markAllRead(in: Thread)` — takes `Thread` object
- `ManageThreadActionsUseCase` — `archiveThread(id:)`, `deleteThread(id:)`
- `AppDependencies` in `VaultMailApp.swift` — dependency assembly

---

### IOS-N-01: Core Service + Protocols + Settings Extensions + Categories

- **Status**: `todo`
- **Spec ref**: NOTIF-01, NOTIF-02, NOTIF-03, NOTIF-23
- **Validation ref**: AC-N-01, AC-N-02, AC-N-14
- **Description**: Central notification service with protocol-based DI, authorization flow, category registration, SettingsStore extensions, and test mock infrastructure.
- **Deliverables**:
  - [ ] `NotificationServiceProtocol.swift` — `@MainActor` protocol with 8 methods (requestAuthorization, authorizationStatus, processNewEmails, removeNotifications×2, updateBadgeCount, registerCategories, markFirstLaunchComplete)
  - [ ] `NotificationCenterProviding.swift` — `@MainActor` protocol wrapping UNUserNotificationCenter (8 methods)
  - [ ] `NotificationAuthStatus.swift` — Sendable enum: notDetermined, authorized, denied, provisional
  - [ ] `UNUserNotificationCenterWrapper.swift` — production conformance delegating to `UNUserNotificationCenter.current()`
  - [ ] `NotificationService.swift` — `@Observable @MainActor` class
    - Authorization request and status check
    - `registerCategories()` — EMAIL_NOTIFICATION category with 4 actions
    - `isFirstLaunch` flag (initialized to `true`, cleared by `markFirstLaunchComplete()`)
    - Recency filter (1h background, 5m foreground via `AppConstants`)
    - `deliveredNotificationIds: Set<String>` for dedup (FIFO eviction at 10K)
    - Batch limit (max 10 banners per `processNewEmails()`)
    - `processNewEmails()` orchestration: first-launch → recency → pipeline → dedup → batch → post
  - [ ] `Constants.swift` additions — 7 notification constants:
    - `notificationCategoryEmail`, `notificationActionMarkRead`, `notificationActionArchive`, `notificationActionDelete`, `notificationActionReply`
    - `maxNotificationsPerSync = 10`
    - `backgroundNotificationRecencySeconds = 3600`, `foregroundNotificationRecencySeconds = 300`
  - [ ] `SettingsStore.swift` extensions:
    - 6 new properties: `notificationCategoryPreferences`, `vipContacts`, `mutedThreadIds`, `quietHoursEnabled`, `quietHoursStart`, `quietHoursEnd`
    - 4 helpers: `notificationCategoryEnabled(for:)`, `toggleMuteThread(threadId:)`, `addVIPContact(_:)`, `removeVIPContact(_:)`
    - 6 UserDefaults keys in `Keys` enum
    - Init logic: JSON decode for collections, `object(forKey:) != nil` check for Int properties
    - `resetAll()` updates
  - [ ] `MockNotificationCenter.swift` — records `addedRequests`, `removedIdentifiers`, `registeredCategories`, `currentBadgeCount`, `authorizationGranted` (configurable)
  - [ ] Unit tests: `NotificationServiceTests` (authorization, first-launch, recency, dedup, batch limit)
  - [ ] Unit tests: `SettingsStoreNotificationTests` (VIP add/remove, muted toggle, quiet hours persistence, category prefs, defaults, resetAll)

---

### IOS-N-02: Content Builder + Thread Grouping + Deduplication

- **Status**: `todo`
- **Spec ref**: NOTIF-04, NOTIF-05, NOTIF-17
- **Validation ref**: AC-N-03, AC-N-04, AC-N-10
- **Description**: Notification content construction from Email model, OS-level thread grouping, and dedup strategy using request identifier + in-memory tracking set.
- **Deliverables**:
  - [ ] `NotificationContentBuilder.swift` — static methods to build `UNMutableNotificationContent`:
    - Title: `email.fromName ?? email.fromAddress`
    - Subtitle: `email.subject`
    - Body: `String(email.snippet?.prefix(100) ?? "")`
    - Sound: `.default`
    - Category identifier: `AppConstants.notificationCategoryEmail`
    - `threadIdentifier`: `email.threadId` (unified stream, no account prefix)
    - `userInfo`: emailId, threadId, accountId, fromAddress
    - Request identifier: `"email-\(email.id)"`
  - [ ] Dedup integration in `NotificationService` — rebuild `deliveredNotificationIds` from `center.deliveredNotifications()` on launch
  - [ ] Unit tests: `NotificationContentBuilderTests`
    - Title uses fromName when available, falls back to fromAddress
    - Subtitle is subject
    - Body truncated at 100 chars
    - threadIdentifier matches email.threadId
    - categoryIdentifier is EMAIL_NOTIFICATION
    - userInfo contains all required keys (emailId, threadId, accountId, fromAddress)
    - Request identifier format

---

### IOS-N-03: Filter Pipeline + P0 Filters

- **Status**: `todo`
- **Spec ref**: NOTIF-07, NOTIF-08, NOTIF-12, NOTIF-13
- **Validation ref**: AC-N-05, AC-N-06, AC-N-07, AC-N-08
- **Description**: Composable notification filter pipeline with VIP override, plus the three P0 filters (account, spam, folder type).
- **Deliverables**:
  - [ ] `NotificationFilterProtocol.swift` — `@MainActor` protocol: `shouldNotify(for email: Email) async -> Bool`
  - [ ] `NotificationFilterPipeline.swift`
    - VIP check runs first as override: if VIP → always notify, skip all filters
    - Remaining filters in AND logic (cheapest first): Account → Spam → FolderType → Muted → Category → QuietHours → FocusMode
    - Early termination: return `false` on first filter rejection
  - [ ] `AccountNotificationFilter.swift` — checks `settingsStore.notificationsEnabled(for: email.accountId)`
  - [ ] `SpamNotificationFilter.swift` — checks `email.isSpam == true` → suppress
  - [ ] `FolderTypeNotificationFilter.swift` — checks email's `emailFolders` relationships for `folder.folderType == FolderType.inbox.rawValue`
  - [ ] Unit tests: `NotificationFilterPipelineTests`
    - VIP override bypasses all other filters
    - Email fails when any non-VIP filter rejects
    - Empty email list returns empty
    - Pipeline with all filters passing
  - [ ] Unit tests: `NotificationFiltersTests` (account enabled/disabled/default, spam/non-spam, inbox/sent/drafts/spam/archive folders)

---

### IOS-N-04: Sync Integration + Badge Management + Coordinator

- **Status**: `todo`
- **Spec ref**: NOTIF-16, NOTIF-19, NOTIF-20, NOTIF-21, NOTIF-21a, NOTIF-18
- **Validation ref**: AC-N-09, AC-N-11, AC-N-12, AC-N-13, AC-N-15
- **Description**: NotificationSyncCoordinator bridging all sync callers to NotificationService, badge count management with platform guards, and integration into BackgroundSyncScheduler, ThreadListView, and MacOSMainView.
- **Deliverables**:
  - [ ] `NotificationSyncCoordinator.swift` — `@Observable @MainActor` class:
    - `pendingThreadNavigation: String?` for notification-tap navigation
    - `didSyncNewEmails(_:fromBackground:activeFolderType:)` → delegates to service
    - `didMarkThreadRead(threadId:)` → remove notifications + update badge
    - `didRemoveThread(threadId:)` → remove notifications + update badge
    - `markFirstLaunchComplete()` → proxies to service
  - [ ] `EmailRepositoryProtocol.swift` — add `getInboxUnreadCount() async throws -> Int`
  - [ ] `EmailRepositoryImpl.swift` — implement per-Email inbox unread count (Email where `isRead == false` AND `EmailFolder.folder.folderType == inbox`). Fallback: two-step query if nested predicates unsupported.
  - [ ] `NotificationService.updateBadgeCount()` — platform guards:
    - `#if canImport(UIKit)`: `center.setBadgeCount(count)`
    - `#if canImport(AppKit)`: `import AppKit` + `NSApplication.shared.dockTile.badgeLabel`
  - [ ] `BackgroundSyncScheduler.swift` modifications:
    - Add `notificationCoordinator: NotificationSyncCoordinator?` to init
    - Call `markFirstLaunchComplete()` after first account sync
    - Call `didSyncNewEmails(newEmails, fromBackground: true, activeFolderType: nil)` per account
  - [ ] `ThreadListView.swift` modifications:
    - After `syncAccountInboxFirst()` returns: call `markFirstLaunchComplete()` + `didSyncNewEmails(fromBackground: false, activeFolderType: selectedFolder?.folderType)`
    - After IDLE `.newMail` sync: call `didSyncNewEmails(fromBackground: false, activeFolderType: selectedFolder?.folderType)`
  - [ ] `MacOSMainView.swift` modifications:
    - Add `NotificationSyncCoordinator` parameter
    - Selected account sync: `didSyncNewEmails(activeFolderType: selectedFolder?.folderType)`
    - Non-selected account syncs: `didSyncNewEmails(activeFolderType: nil)` — **critical**: `nil` prevents cross-account suppression
    - IDLE sync: `didSyncNewEmails(activeFolderType: selectedFolder?.folderType)`
    - First sync: `markFirstLaunchComplete()`
  - [ ] `VaultMailApp.swift` modifications:
    - Create filter instances, pipeline, service, handler, coordinator in AppDependencies
    - Set `UNUserNotificationCenter.current().delegate`
    - Call `registerCategories()`
    - Pass coordinator to BackgroundSyncScheduler (iOS), MacOSMainView (macOS)
    - Inject coordinator via `.environment()`
  - [ ] Unit tests: coordinator, badge count, sync integration

---

### IOS-N-05: Response Handler + Notification Removal + Navigation

- **Status**: `todo`
- **Spec ref**: NOTIF-06, NOTIF-18
- **Validation ref**: AC-N-16, AC-N-17, AC-N-18, AC-N-19, AC-N-20
- **Description**: UNUserNotificationCenterDelegate handling all 4 actions (mark read, archive, delete, reply with full 11-param saveDraft), notification-tap navigation via `pendingThreadNavigation`, foreground presentation suppression, and state-change notification removal.
- **Deliverables**:
  - [ ] `NotificationResponseHandler.swift` — `@MainActor` class conforming to `UNUserNotificationCenterDelegate`:
    - `didReceive(response:)` — dispatch by action identifier:
      - `MARK_READ_ACTION`: fetch Thread → `markReadUseCase.markAllRead(in: thread)` → remove + badge
      - `ARCHIVE_ACTION`: `manageThreadActions.archiveThread(id:)` → remove + badge
      - `DELETE_ACTION`: `manageThreadActions.deleteThread(id:)` → remove + badge
      - `REPLY_ACTION`: fetch email → `saveDraft()` (full 11-param mapping) → `queueForSending` → `executeSend` → remove + badge
      - Default tap: set `coordinator.pendingThreadNavigation = threadId`
    - `willPresent(notification:)` — return `[.banner, .badge, .sound]`; suppress banner if viewing same thread
  - [ ] `ThreadListView` — observe `pendingThreadNavigation`:
    - `.onChange(of: coordinator.pendingThreadNavigation)` — navigate + set to `nil`
    - `.task` — read non-nil value on cold start
  - [ ] `MacOSMainView` — observe `pendingThreadNavigation` (same pattern)
  - [ ] `NotificationService` removal methods:
    - `removeNotifications(forThreadId:)` — query delivered, filter by userInfo threadId, remove
    - `removeNotifications(forEmailIds:)` — remove by `"email-\(id)"` identifiers
  - [ ] Unit tests: response handler (all 4 actions + tap), foreground presentation, removal

---

### IOS-N-06: P1/P2 Filters (Category, VIP, Muted, Quiet Hours)

- **Status**: `todo`
- **Spec ref**: NOTIF-09, NOTIF-10, NOTIF-11, NOTIF-14
- **Validation ref**: AC-N-05, AC-N-06, AC-N-07, AC-N-08
- **Description**: Remaining notification filters: per-category toggle, VIP contact override, muted thread suppression, quiet hours with overnight range support. Plus UI integration for mute thread action.
- **Deliverables**:
  - [ ] `CategoryNotificationFilter.swift`
    - `aiCategory` nil or uncategorized → pass
    - Check `settingsStore.notificationCategoryEnabled(for:)` → pass/suppress
  - [ ] `VIPContactFilter.swift`
    - Check `email.fromAddress.lowercased()` in `settingsStore.vipContacts`
    - Runs as pipeline override (before AND chain)
  - [ ] `MutedThreadFilter.swift`
    - Check `email.threadId` in `settingsStore.mutedThreadIds` → suppress
  - [ ] `QuietHoursFilter.swift`
    - `quietHoursEnabled == false` → always pass
    - Normal range (start < end): suppress if `currentMinutes >= start && currentMinutes < end`
    - Overnight range (start > end): suppress if `currentMinutes >= start || currentMinutes < end`
    - Uses `Calendar.current` for time zone correctness
  - [ ] `ThreadListView.swift` — add mute/unmute swipe action and context menu item
  - [ ] `ThreadRowView.swift` — show `bell.slash` SF Symbol for muted threads
  - [ ] Unit tests: `NotificationFiltersTests`
    - Category: enabled/disabled/uncategorized/nil states
    - VIP: VIP/non-VIP/case-insensitive matching
    - Muted: muted/non-muted states
    - Quiet hours: during/outside/overnight range/disabled/boundary states

---

### IOS-N-07: Settings UI

- **Status**: `todo`
- **Spec ref**: NOTIF-22
- **Validation ref**: AC-N-21, AC-N-22
- **Description**: Notification settings interface with shared content view for iOS and macOS, covering system permission status, per-account toggles, per-category toggles, VIP contacts, muted threads, and quiet hours. MV pattern — uses @State, @Environment, .task.
- **Deliverables**:
  - [ ] `NotificationSettingsContent.swift` — shared view with 6 sections:
    - System Permission: authorization status + "Open Settings" button if denied
    - Accounts: per-account notification toggles
    - Categories: per-category toggles (Primary, Social, Promotions, Updates)
    - VIP Contacts: list + add field + swipe-to-delete + description
    - Muted Threads: list + swipe-to-unmute + thread subjects from SwiftData
    - Quiet Hours: enable toggle + two `DatePicker` (`.hourAndMinute`)
  - [ ] `NotificationSettingsView.swift` — iOS view wrapping `NotificationSettingsContent`
  - [ ] `SettingsView.swift` — replace inline notification toggles with `NavigationLink` to `NotificationSettingsView`
  - [ ] `MacSettingsView.swift` — replace `MacNotificationsSettingsTab` with `NotificationSettingsContent`
  - [ ] Accessibility annotations: labels, hints, Dynamic Type support
  - [ ] VoiceOver: toggle descriptions, section headers, button labels

---

### IOS-N-08: Focus Mode Stub + macOS Polish

- **Status**: `todo`
- **Spec ref**: NOTIF-15, NOTIF-24
- **Validation ref**: AC-N-23
- **Description**: Focus mode filter stub (always passes, V2 implementation) and macOS-specific polish (dock badge, settings, end-to-end verification).
- **Deliverables**:
  - [ ] `FocusModeFilter.swift` — stub returning `true` always; doc comment explaining V2 plan (AppIntents `FocusFilterIntent`)
  - [ ] macOS dock badge verification: `NSApplication.shared.dockTile.badgeLabel` with `#if canImport(AppKit)` + `import AppKit`
  - [ ] Integration verification: full end-to-end flow on macOS (sync → filter → notify → action → remove → badge)
  - [ ] Verify IDLE monitoring produces real-time notifications on macOS (no background task needed)
