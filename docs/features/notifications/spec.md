---
title: "Notifications — Specification"
version: "0.4.0"
status: draft
created: 2026-02-19
updated: 2026-02-19
authors:
  - Core Team
reviewers:
  - Claude (automated review)
tags: [notifications, local-notifications, filtering, badges, actions]
depends-on:
  - docs/constitution.md
  - docs/features/foundation/spec.md
  - docs/features/email-sync/spec.md
  - docs/features/settings-onboarding/spec.md
  - docs/features/thread-list/spec.md
---

# Specification: Notifications

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

## 1. Summary

This specification defines the local notification system for VaultMail. All notifications are triggered on-device in response to new emails discovered during background sync (`BackgroundSyncScheduler`), IMAP IDLE real-time monitoring (`IDLEMonitorUseCase`), or foreground sync (`SyncEmailsUseCase`). No remote push notification server (APNs) is required.

Notifications are presented as a unified stream across all accounts. Each notification supports inline actions (Mark Read, Archive, Delete, Reply). A comprehensive filtering pipeline governs which emails trigger notifications, including per-account toggles, per-category filters, VIP contacts, muted threads, spam suppression, quiet hours, and Focus mode integration.

---

## 2. Goals and Non-Goals

### Goals

- **G-01**: Deliver local notifications for new emails received via background sync, IMAP IDLE, and foreground sync
- **G-02**: Provide full inline notification actions (Mark Read, Archive, Delete, Reply)
- **G-03**: Implement a composable, testable filtering pipeline with VIP overrides, muted threads, per-category toggles, quiet hours, and spam suppression
- **G-04**: Manage app icon badge count reflecting total unread emails
- **G-05**: Support both iOS 17+ and macOS 14+ with platform-appropriate behavior
- **G-06**: Deduplicate notifications for the same email across folders and sync cycles
- **G-07**: Remove notifications when email state changes in-app (read, archived, deleted)

### Non-Goals

- **NG-01**: APNs remote push notifications (requires server infrastructure; deferred to V2)
- **NG-02**: Rich notification extensions with email body preview (deferred; standard banner is sufficient for V1)
- **NG-03**: Notification sound customization beyond system default (V2)
- **NG-04**: Siri Suggestions integration (V2)
- **NG-05**: Communication notifications with sender avatars (requires INSendMessageIntent; V2)

---

## 3. Functional Requirements

### 3.1 Notification Service (NOTIF-01)

**Description**

The app **MUST** provide a central `NotificationService` that coordinates all notification lifecycle operations: authorization, content creation, delivery, filtering, removal, and badge management.

**Architecture**

The `NotificationService` **MUST** be an `@Observable @MainActor` class, consistent with the project's MV pattern. It **MUST** be injectable via `.environment()` and backed by a protocol (`NotificationServiceProtocol`) for testability.

```swift
@MainActor
public protocol NotificationServiceProtocol {
    func requestAuthorization() async -> Bool
    func authorizationStatus() async -> NotificationAuthStatus
    func processNewEmails(_ emails: [Email], fromBackground: Bool, activeFolderType: String?) async
    func removeNotifications(forEmailIds emailIds: [String]) async
    func removeNotifications(forThreadId threadId: String) async
    func updateBadgeCount() async
    func registerCategories()
    /// Marks the first-launch suppression phase as complete.
    /// Called after the first successful sync in the current app session.
    func markFirstLaunchComplete()
}
```

The service **MUST** wrap `UNUserNotificationCenter` behind a `NotificationCenterProviding` protocol to enable unit testing without hitting the real notification system:

```swift
@MainActor
public protocol NotificationCenterProviding {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
    func add(_ request: UNNotificationRequest) async throws
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func setBadgeCount(_ count: Int) async throws
    func deliveredNotifications() async -> [UNNotification]
}
```

**Dependencies**

The `NotificationService` **MUST** receive:
- `NotificationCenterProviding` — production wrapper or test mock
- `SettingsStore` — for notification preferences and filter settings
- `EmailRepositoryProtocol` — for unread count queries (badge management)
- `NotificationFilterPipeline` — for filtering decisions

**Initialization**

The service **MUST** be created in `AppDependencies.init()` and wired into the dependency graph. `registerCategories()` **MUST** be called during app initialization.

---

### 3.2 Authorization (NOTIF-02)

**Description**

The app **MUST** request notification authorization from the operating system before delivering any notifications.

**Permission Request Flow**

1. **During onboarding**: After the first account is successfully added, the app **MUST** call `notificationService.requestAuthorization()`. This occurs in the onboarding ready step.

2. **When enabling per-account toggle**: If the user enables notifications for an account and authorization has not been granted, the app **MUST** request permission before enabling the toggle. If the user denies, the toggle **MUST** remain off.

3. **Settings fallback**: If authorization is `.denied`, the notification settings UI **MUST** show an "Open Settings" button that navigates to `UIApplication.openSettingsURLString` (iOS) or System Settings > Notifications (macOS).

**Authorization Options**

The app **MUST** request: `.alert`, `.badge`, `.sound`.

**Authorization Status Enum**

```swift
public enum NotificationAuthStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
}
```

**Platform Notes**

`UNUserNotificationCenter` authorization works identically on iOS 17+ and macOS 14+. No platform guards are needed for the authorization flow.

---

### 3.3 Category Registration (NOTIF-03)

**Description**

The app **MUST** register a single `UNNotificationCategory` with four actions for email notifications.

**Category Definition**

| Identifier | Value |
|------------|-------|
| Category | `EMAIL_NOTIFICATION` |
| Mark Read Action | `MARK_READ_ACTION` |
| Archive Action | `ARCHIVE_ACTION` |
| Delete Action | `DELETE_ACTION` |
| Reply Action | `REPLY_ACTION` |

**Action Details**

| Action | Type | Options | Notes |
|--------|------|---------|-------|
| Mark Read | `UNNotificationAction` | None | Marks all unread emails in thread as read |
| Archive | `UNNotificationAction` | None | Archives thread (provider-specific: Gmail label vs IMAP move) |
| Delete | `UNNotificationAction` | `.destructive` | Moves thread to trash |
| Reply | `UNTextInputNotificationAction` | None | Button title: "Send", placeholder: "Type your reply..." |

The `.customDismissAction` option is deferred to V2 (notification dismiss analytics). V1 categories **MUST NOT** include it.

**Registration Timing**

`registerCategories()` **MUST** be called in `AppDependencies.init()`, which runs during `VaultMailApp.init()`.

**Constants**

These identifiers **MUST** be added to `AppConstants` in `Constants.swift`:

```swift
// MARK: - Notification Identifiers (NOTIF-03)
public static let notificationCategoryEmail = "EMAIL_NOTIFICATION"
public static let notificationActionMarkRead = "MARK_READ_ACTION"
public static let notificationActionArchive = "ARCHIVE_ACTION"
public static let notificationActionDelete = "DELETE_ACTION"
public static let notificationActionReply = "REPLY_ACTION"
public static let maxNotificationsPerSync = 10
public static let backgroundNotificationRecencySeconds = 3600
public static let foregroundNotificationRecencySeconds = 300
```

---

### 3.4 Notification Content (NOTIF-04)

**Description**

The app **MUST** build notification content from `Email` model data using a `NotificationContentBuilder`.

**Content Format**

| Field | Value | Source |
|-------|-------|--------|
| Title | Sender display name | `email.fromName ?? email.fromAddress` |
| Subtitle | Email subject | `email.subject` |
| Body | First 100 characters of snippet | `String(email.snippet?.prefix(100) ?? "")` |
| Sound | System default | `.default` |
| Category Identifier | `EMAIL_NOTIFICATION` | Constant |
| Interruption Level | `.active` | Default for email; VIP could use `.timeSensitive` in V2 |

**User Info Payload**

Every notification **MUST** include `userInfo` with:

```swift
[
    "emailId": email.id,          // SHA256 stable ID
    "threadId": email.threadId,   // For thread-level actions
    "accountId": email.accountId, // For provider-specific action handling
    "fromAddress": email.fromAddress  // For reply construction
]
```

**Request Identifier**

The notification request identifier **MUST** be `"email-\(email.id)"` where `email.id` is the SHA256 stable ID. This enables deduplication (NOTIF-17) and targeted removal (NOTIF-18).

---

### 3.5 Thread Grouping (NOTIF-05)

**Description**

Notifications **MUST** use `threadIdentifier` for OS-level grouping.

**Grouping Strategy**

- `content.threadIdentifier` **MUST** be set to `email.threadId`
- This produces a **unified stream** across all accounts (per user requirement)
- Within the unified stream, notifications from the same email thread automatically collapse into a group
- No per-account prefix is applied to `threadIdentifier`

**Behavior**

When multiple emails arrive in the same thread, iOS/macOS will show a grouped notification with the latest email on top and a count of additional notifications in the group.

---

### 3.6 Response Handling (NOTIF-06)

**Description**

The app **MUST** implement `UNUserNotificationCenterDelegate` to handle notification actions and foreground presentation.

**Implementation**

A `NotificationResponseHandler` class **MUST** conform to `UNUserNotificationCenterDelegate` and be set as the delegate in `AppDependencies.init()`:

```swift
UNUserNotificationCenter.current().delegate = notificationResponseHandler
```

The handler **MUST** be retained for the app's lifetime via the `AppDependencies` struct stored on `VaultMailApp`.

#### NOTIF-06a: Mark Read Action

When the user taps "Mark Read":
1. Extract `threadId` from `userInfo`
2. Fetch the `Thread` entity from `emailRepository.getThread(id: threadId)`
3. Call `markReadUseCase.markAllRead(in: thread)` to mark all unread emails in the thread (note: parameter is a `Thread` object, not a String ID)
4. Call `notificationService.removeNotifications(forThreadId:)` to clear the notification
5. Call `notificationService.updateBadgeCount()` to decrement the badge

#### NOTIF-06b: Archive Action

When the user taps "Archive":
1. Extract `threadId` from `userInfo`
2. Call `manageThreadActions.archiveThread(id:)` — this handles provider-specific behavior (Gmail: remove inbox label; others: IMAP COPY to Archive + EXPUNGE from Inbox)
3. Remove notification and update badge

#### NOTIF-06c: Delete Action

When the user taps "Delete":
1. Extract `threadId` from `userInfo`
2. Call `manageThreadActions.deleteThread(id:)` — moves to Trash folder
3. Remove notification and update badge

#### NOTIF-06d: Reply Action

When the user taps "Reply" and enters text (`replyText` from `UNTextInputNotificationResponse.userText`):
1. Extract `emailId`, `threadId`, and `accountId` from `userInfo`
2. Fetch the original email via `emailRepository.getEmail(id: emailId)` to obtain `subject`, `messageId`, `references`, and `fromAddress`
3. Create a reply draft with full parameter mapping:
   ```swift
   let draftId = try await composeEmail.saveDraft(
       draftId: nil,
       accountId: accountId,
       threadId: threadId,
       toAddresses: [originalEmail.fromAddress],
       ccAddresses: [],
       bccAddresses: [],
       subject: originalEmail.subject.hasPrefix("Re: ") ? originalEmail.subject : "Re: \(originalEmail.subject)",
       bodyPlain: replyText,
       inReplyTo: originalEmail.messageId,
       references: [originalEmail.references, originalEmail.messageId].compactMap { $0 }.joined(separator: " "),
       attachments: []
   )
   ```
4. Queue for immediate sending: `composeEmail.queueForSending(emailId: draftId)`
5. Execute send: `composeEmail.executeSend(emailId: draftId)`
6. Remove notification and update badge

**Note**: Notification replies bypass the undo-send delay because there is no UI to show an undo button. The user has already confirmed by tapping "Send" in the notification input. The `userInfo` **MUST** include `emailId`, `threadId`, and `accountId` (set in NOTIF-04).

#### NOTIF-06e: Tap Navigation

When the user taps the notification body (default action):
1. Extract `threadId` from `userInfo`
2. Set `notificationSyncCoordinator.pendingThreadNavigation = threadId`
3. `ThreadListView` **MUST** observe this property via `.onChange(of: notificationSyncCoordinator.pendingThreadNavigation)` and, when non-nil, append the `threadId` to its `navigationPath`, then set the property back to `nil`
4. The existing `.navigationDestination(for: String.self) { threadId in EmailDetailView(...) }` at line 275 handles the navigation

**Cold Start Handling**: When the app launches from a terminated state via notification tap, the `pendingThreadNavigation` property is set before any view subscribes. `ThreadListView` reads the non-nil value in its `.task` modifier on first appear and navigates immediately. This is more reliable than `Notification.Name` posting (which can fire before the view subscribes) and more SwiftUI-native than Foundation notification observers.

**Note**: Navigation is owned by `ThreadListView`, not `ContentView`. `ContentView` has no `NavigationStack` or `NavigationPath` — it merely hosts `ThreadListView`.

#### NOTIF-06f: Foreground Presentation

The `willPresent` delegate method **MUST** return `[.banner, .badge, .sound]` by default. However, if the user is currently viewing the same thread that triggered the notification, the method **SHOULD** return `[]` (suppress the banner) to avoid redundant alerts.

---

### 3.7 Notification Filtering Pipeline (NOTIF-07)

**Description**

The app **MUST** implement a composable filtering pipeline that determines whether an email should trigger a notification.

**Filter Protocol**

```swift
@MainActor
public protocol NotificationFilter {
    func shouldNotify(for email: Email) async -> Bool
}
```

**Pipeline Behavior**

The `NotificationFilterPipeline` **MUST** execute filters in the following order:

1. **VIP Check (override)**: If the sender is a VIP contact, the email **MUST** bypass ALL subsequent filters and always trigger a notification.
2. **Remaining filters (AND logic)**: ALL remaining filters **MUST** return `true` for the notification to proceed. If any filter returns `false`, the notification is suppressed.

**Design Note — VIP Precedence**: VIP senders bypass ALL filters, including spam and muted-thread. The user's explicit VIP designation takes precedence over automated spam classification or thread-level muting. This is intentional: if the user has marked a sender as VIP, they want to hear from them regardless of other signals. To stop notifications from a VIP contact, the user must remove them from the VIP list.

**Non-VIP Filter Ordering** (cheapest first for early termination):

1. `AccountNotificationFilter` (NOTIF-08) — O(1) dictionary lookup
2. `SpamNotificationFilter` (NOTIF-12) — O(1) boolean check
3. `FolderTypeNotificationFilter` (NOTIF-13) — O(n) where n = email's folder count (usually 1–2)
4. `MutedThreadFilter` (NOTIF-11) — O(1) set lookup
5. `CategoryNotificationFilter` (NOTIF-09) — O(1) dictionary lookup
6. `QuietHoursFilter` (NOTIF-14) — O(1) time comparison
7. `FocusModeFilter` (NOTIF-15) — O(1) status check

---

### 3.8 Account Notification Filter (NOTIF-08)

**Description**

The filter **MUST** check the per-account notification toggle from `SettingsStore.notificationPreferences`.

**Behavior**

- If `settingsStore.notificationsEnabled(for: email.accountId)` returns `true` → pass
- If `false` → suppress
- Default for new accounts: `true` (existing behavior in `SettingsStore`)

---

### 3.9 Category Notification Filter (NOTIF-09)

**Description**

The filter **MUST** check per-category notification toggles for AI-classified categories.

**Behavior**

- If `email.aiCategory` is `nil` or `"uncategorized"` → always pass (AI hasn't processed yet)
- Otherwise, check `settingsStore.notificationCategoryEnabled(for: email.aiCategory)` → pass or suppress

**New SettingsStore Property**

```swift
public var notificationCategoryPreferences: [String: Bool]
```

Default: all categories enabled (`[:]` empty dictionary; `notificationCategoryEnabled(for:)` returns `true` when key is absent).

**Categories**: Primary, Social, Promotions, Updates (matching existing `AICategory` enum values).

---

### 3.10 VIP Contact Filter (NOTIF-10)

**Description**

VIP contacts **MUST** always trigger notifications regardless of all other filters.

**Behavior**

The VIP filter runs **before** the main filter chain as an override:
- If `email.fromAddress.lowercased()` is in `settingsStore.vipContacts` → **always notify** (skip all other filters)
- If not VIP → fall through to remaining filter chain

**New SettingsStore Property**

```swift
public var vipContacts: Set<String>  // lowercased email addresses
```

**Helper Methods**

```swift
public func addVIPContact(_ email: String)
public func removeVIPContact(_ email: String)
```

**Storage**: Persisted as `[String]` array in UserDefaults, loaded as `Set<String>`.

---

### 3.11 Muted Thread Filter (NOTIF-11)

**Description**

Muted threads **MUST** never trigger notifications.

**Behavior**

- If `email.threadId` is in `settingsStore.mutedThreadIds` → suppress
- Otherwise → pass

**New SettingsStore Property**

```swift
public var mutedThreadIds: Set<String>
```

**Helper Method**

```swift
public func toggleMuteThread(threadId: String)
```

**UI Integration**

- A "Mute Thread" action **MUST** be added to the swipe actions and long-press context menu in `ThreadListView`
- Muted threads **MUST** display a `bell.slash` SF Symbol indicator in `ThreadRowView`
- `NotificationSettingsView` **MUST** show a list of muted threads with an "Unmute" option

**Cleanup**

On app launch, the service **SHOULD** remove thread IDs from `mutedThreadIds` that no longer exist in SwiftData to prevent unbounded growth.

---

### 3.12 Spam Notification Filter (NOTIF-12)

**Description**

Emails flagged as spam **MUST** never trigger notifications.

**Behavior**

- If `email.isSpam == true` → suppress
- Otherwise → pass

---

### 3.13 Folder Type Notification Filter (NOTIF-13)

**Description**

Only emails in inbox-type folders **MUST** trigger notifications.

**Behavior**

The filter **MUST** check the email's `emailFolders` relationships:
- If any associated `folder.folderType` is `FolderType.inbox.rawValue` → pass
- If the email exists only in Sent, Drafts, Trash, Spam, Archive, or Custom folders → suppress

**Rationale**: Users should not receive notifications for sent emails, drafts, or spam. Custom folder notifications may be added in V2.

---

### 3.14 Quiet Hours Filter (NOTIF-14)

**Description**

The app **MUST** support time-based notification suppression ("quiet hours" / "Do Not Disturb" schedule).

**Behavior**

- If `settingsStore.quietHoursEnabled == false` → always pass
- If enabled, compare current time against `quietHoursStart` and `quietHoursEnd`:
  - Both stored as **minutes since midnight** (e.g., 22:00 = 1320, 07:00 = 420)
  - **Normal range** (start < end): suppress if `currentMinutes >= start && currentMinutes < end`
  - **Overnight range** (start > end, e.g., 22:00–07:00): suppress if `currentMinutes >= start || currentMinutes < end`

**New SettingsStore Properties**

```swift
public var quietHoursEnabled: Bool     // default: false
public var quietHoursStart: Int        // default: 1320 (22:00)
public var quietHoursEnd: Int          // default: 420 (07:00)
```

**Initialization Note**: Use `defaults.object(forKey:) != nil` check before `.integer(forKey:)` per project convention, to distinguish "not set" (nil → use default) from "set to 0" (midnight).

**UI**: Two time pickers (`.hourAndMinute` display) in `NotificationSettingsView`.

---

### 3.15 Focus Mode Filter (NOTIF-15)

**Description**

The app **MAY** integrate with iOS 16+ Focus Filters to suppress notifications based on the active Focus mode.

**V1 Behavior**

The filter **MUST** be a stub that always returns `true` (pass). The implementation is deferred to V2.

**V2 Design Direction**

V2 will use the `AppIntents` framework to define a `FocusFilterIntent` that allows users to configure which accounts and categories are allowed during each Focus mode. The filter will query `INFocusStatusCenter` to determine the active Focus state.

---

### 3.16 Badge Management (NOTIF-16)

**Description**

The app **MUST** manage the app icon badge count to reflect the total unread email count.

**Badge Value**

Badge count = total unread emails across all active accounts, constrained to inbox-type folders. This requires a **new** repository method since the existing `getUnreadCountsUnified()` aggregates all threads across all folders without inbox filtering.

**New Repository Method**

Add to `EmailRepositoryProtocol` (`Domain/Protocols/EmailRepositoryProtocol.swift`):

```swift
/// Returns total unread count across all accounts, filtered to inbox-type folders only.
func getInboxUnreadCount() async throws -> Int
```

Implementation in `EmailRepositoryImpl` (`Data/Repositories/EmailRepositoryImpl.swift`): count individual `Email` entities where `isRead == false` AND the email has at least one `EmailFolder` association where `folder.folderType == FolderType.inbox.rawValue`. This is a per-email count, NOT a sum of `thread.unreadCount` — because `thread.unreadCount` counts unread emails across ALL folders in the thread (including archive, spam), not just inbox (see `SyncEmailsUseCase.swift` line 694: `thread.unreadCount = threadEmails.filter { !$0.isRead }.count`).

**Query Notes**: This query traverses `Email` → `EmailFolder` → `Folder` relationships with a `folderType` predicate. If SwiftData's `#Predicate` macro does not support direct relationship traversal across three levels, an alternative approach is: (1) fetch all `Folder` entities where `folderType == FolderType.inbox.rawValue`, (2) collect their IDs, (3) count `Email` entities where `isRead == false` that have an `EmailFolder` linking to one of those folder IDs. For large mailboxes (>10,000 unread), consider maintaining a cached inbox unread count in `SettingsStore`, updated incrementally on sync and read-state changes.

**Update Triggers**

The badge **MUST** be updated after:
- `processNewEmails()` completes
- Any notification action (mark read, archive, delete)
- Any in-app action that changes unread state (mark read, archive, delete)
- App launch (in case badge is stale from background sync)

**Platform Implementation**

| Platform | API |
|----------|-----|
| iOS 17+ | `UNUserNotificationCenter.setBadgeCount(_:)` (UserNotifications framework, already imported) |
| macOS 14+ | `import AppKit` under `#if canImport(AppKit)`; `NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil` |

The service **MUST** use `#if canImport(UIKit)` / `#if canImport(AppKit)` guards for badge updates, consistent with the project's existing platform guard pattern (e.g., `PlatformImage.swift`). The macOS path requires an explicit `import AppKit` since SPM packages do not implicitly import it.

---

### 3.17 Deduplication (NOTIF-17)

**Description**

The app **MUST** prevent duplicate notifications for the same email.

**Dedup Strategy**

1. **By request identifier**: Each notification request uses `"email-\(email.id)"` as its identifier. If the same email is synced again (e.g., after restart or from another folder), `UNUserNotificationCenter` will replace the existing notification.

2. **By tracking set**: `NotificationService` **MUST** maintain a `deliveredNotificationIds: Set<String>` in memory. Before posting, check if `email.id` is already in the set. Skip if present.

3. **Cross-folder dedup**: Since `email.id` is a SHA256 hash of `accountId + messageId` (per Email Sync spec), the same email appearing in multiple IMAP folders (e.g., Inbox + Starred in Gmail) will have the same ID and produce only one notification.

**Set Cleanup**

On app launch, the set **SHOULD** be rebuilt from `center.deliveredNotifications()` to recover state after app termination.

---

### 3.18 Notification Removal on State Change (NOTIF-18)

**Description**

The app **MUST** remove delivered notifications when the corresponding email's state changes.

**State Changes That Trigger Removal**

| Action | Scope | Trigger |
|--------|-------|---------|
| Mark as read (in-app) | Thread | `removeNotifications(forThreadId:)` |
| Archive (in-app) | Thread | `removeNotifications(forThreadId:)` |
| Delete (in-app) | Thread | `removeNotifications(forThreadId:)` |
| Mark as read (notification action) | Thread | Handled inline in response handler |
| Archive (notification action) | Thread | Handled inline in response handler |
| Delete (notification action) | Thread | Handled inline in response handler |

**Coordination**

A `NotificationSyncCoordinator` **MUST** bridge between use cases and the notification service:

```swift
@MainActor @Observable
public final class NotificationSyncCoordinator {
    /// Set by NotificationResponseHandler when the user taps a notification.
    /// ThreadListView/MacOSMainView observes this and navigates, then sets it back to nil.
    var pendingThreadNavigation: String?

    func didMarkThreadRead(threadId: String) async
    func didRemoveThread(threadId: String) async
    func didSyncNewEmails(_ emails: [Email], fromBackground: Bool, activeFolderType: String?) async
    func markFirstLaunchComplete()
}
```

**Rationale**: The coordinator exists as a thin facade rather than having callers invoke `NotificationService` directly because: (1) it provides a single integration point for all sync callers (ThreadListView, MacOSMainView, BackgroundSyncScheduler, IDLEMonitor), reducing the API surface each caller must know; (2) it encapsulates `activeFolderType` parameter logic — callers pass their local context and the coordinator determines the correct suppression behavior; (3) it proxies `markFirstLaunchComplete()` so callers do not need a direct reference to `NotificationService`; (4) it holds the `pendingThreadNavigation` observable for notification-tap navigation; (5) it enables future batch-level logic (e.g., rate limiting) without modifying every caller.

The `activeFolderType` parameter allows the service to suppress banners for emails the user is already viewing. Callers pass `selectedFolder?.folderType` from `ThreadListView`/`MacOSMainView` (only for the actively viewed account), or `nil` from `BackgroundSyncScheduler` and non-selected account syncs on macOS. Using `folderType` instead of folder ID ensures correct suppression in unified inbox mode, where a single representative folder ID would not match emails from other accounts' inboxes of the same type.

**Removal API**

- `removeNotifications(forThreadId:)`: Queries `center.deliveredNotifications()`, filters by `userInfo["threadId"]`, and removes matching identifiers.
- `removeNotifications(forEmailIds:)`: Removes notifications with identifiers matching `"email-\(id)"` for each provided email ID.

---

### 3.19 Sync Integration — SyncEmailsUseCase (NOTIF-19)

**Description**

Notifications **MUST** be triggered after new emails are persisted during sync.

**Integration Point**

`SyncEmailsUseCase.syncAccount()` and `syncFolder()` return `[Email]` representing newly synced emails. The **callers** of these methods (not the use case itself) **MUST** pass the returned emails to `NotificationSyncCoordinator.didSyncNewEmails()`.

**Foreground Sync**

In `ThreadListView` (iOS) or `MacOSMainView` (macOS), after foreground sync:

```swift
let newEmails = try await syncEmails.syncAccountInboxFirst(
    accountId: accountId,
    onInboxSynced: { inboxEmails in
        // Refresh UI immediately with inbox data
        await loadThreadsAndCounts()
    }
)
// After ALL folders synced, trigger notifications with the complete set
await notificationSyncCoordinator.markFirstLaunchComplete()
await notificationSyncCoordinator.didSyncNewEmails(newEmails, fromBackground: false, activeFolderType: selectedFolder?.folderType)
```

**Timing**: `markFirstLaunchComplete()` and `didSyncNewEmails()` are called after `syncAccountInboxFirst` returns (all folders complete), NOT in the `onInboxSynced` callback. The `onInboxSynced` callback fires mid-sync (after inbox but before other folders) and is used only for UI refresh. Calling notification methods after full return ensures the service receives the complete set of new emails and avoids double-processing inbox emails.

When `activeFolderType` is non-nil, the service **SHOULD** suppress notification banners for emails whose `emailFolders` include any folder with that `folderType` (the user is already viewing that folder type). This works correctly in unified inbox mode where the user views all accounts' inboxes simultaneously but `selectedFolder` is only one representative folder. Badge count is still updated.

**Anti-Flood Strategy**

The spec uses a two-layer approach to prevent notification flooding on first sync and bulk operations. Neither layer depends on `folder.lastSyncDate` (which is set inside `syncFolderEmails()` before the `[Email]` array is returned to callers).

1. **First-launch suppression**: `NotificationService` **MUST** maintain an `isFirstLaunch: Bool` flag, initialized to `true`. While `isFirstLaunch == true`, ALL notifications are suppressed (the user just opened the app and will see emails in the UI). Callers **MUST** call `notificationService.markFirstLaunchComplete()` after the first successful sync completes in the current app session. Two callers are responsible:
   - **Foreground**: `ThreadListView` (iOS) or `MacOSMainView` (macOS) calls this after `syncAccountInboxFirst()` returns.
   - **Background**: `BackgroundSyncScheduler` calls `notificationCoordinator?.markFirstLaunchComplete()` after the first account sync completes in `handleBackgroundSync()`. This ensures background-only app launches (where no foreground view is loaded) still clear the flag and deliver notifications for subsequent syncs in the same BGTask session.

2. **Recency filter**: After first-launch suppression is lifted, the service **MUST** apply a recency check based on `email.dateReceived`:
   - When `fromBackground == true`: only notify for emails received within the last **1 hour** (`AppConstants.backgroundNotificationRecencySeconds = 3600`)
   - When `fromBackground == false`: only notify for emails received within the last **5 minutes** (`AppConstants.foregroundNotificationRecencySeconds = 300`)
   - This naturally suppresses historical emails synced during initial setup or large sync windows without requiring any folder metadata.

3. **Batch limit**: The service **MUST NOT** post more than `AppConstants.maxNotificationsPerSync` (10) notification banners per `processNewEmails()` invocation. If more than 10 emails qualify after all filters, only the 10 most recent (by `dateReceived`) produce banners; remaining emails update the badge count silently. This prevents notification center flooding during large sync windows.

---

### 3.20 Sync Integration — BackgroundSyncScheduler (NOTIF-20)

**Description**

Background sync **MUST** trigger notifications for newly discovered emails.

**Integration Point**

`BackgroundSyncScheduler.handleBackgroundSync(task:)` is `private func handleBackgroundSync(task: BGAppRefreshTask) async`. The sync loop runs inside an existing `Task { @MainActor in }` child. The notification coordinator calls **MUST** be added inside this existing structure:

```swift
// Inside existing handleBackgroundSync(task: BGAppRefreshTask) async
// Within the existing Task { @MainActor in } block:
let accounts = try await manageAccounts.getAccounts()
let activeAccounts = accounts.filter { $0.isActive }
var isFirstAccount = true
for account in activeAccounts {
    guard !Task.isCancelled else { break }
    let newEmails = try await syncEmails.syncAccount(accountId: account.id)
    if isFirstAccount {
        await notificationCoordinator?.markFirstLaunchComplete()
        isFirstAccount = false
    }
    await notificationCoordinator?.didSyncNewEmails(newEmails, fromBackground: true, activeFolderType: nil)
}
```

**Note**: This code replaces the existing sync loop inside `handleBackgroundSync(task:)`. The method signature `private func handleBackgroundSync(task: BGAppRefreshTask) async` and the outer `Task { @MainActor in }` wrapper (with expiration handler and task completion callbacks) remain unchanged.

**Modifications Required**

- `BackgroundSyncScheduler.init()` **MUST** accept an optional `NotificationSyncCoordinator?` parameter
- The sync loop inside the existing `Task { @MainActor in }` block **MUST** capture sync return values and pass them to the coordinator
- `markFirstLaunchComplete()` **MUST** be called after the first account sync completes, ensuring background-only app launches clear the `isFirstLaunch` flag before processing notifications for subsequent accounts
- This integration is iOS-only (existing `#if os(iOS)` guard)

**Performance Note**

Notification posting via `UNUserNotificationCenter.add()` takes <10ms per notification. With the 30-second background budget, this is well within limits even for dozens of new emails.

---

### 3.21 Sync Integration — IDLEMonitorUseCase (NOTIF-21)

**Description**

IMAP IDLE `.newMail` events that trigger folder sync **MUST** also trigger notifications.

**Integration Point**

In `ThreadListView.startIDLEMonitor()`, after receiving `.newMail` and calling `syncEmails.syncFolder()`:

```swift
case .newMail:
    let syncedEmails = try await syncEmails.syncFolder(accountId:, folderId:)
    await loadThreadsAndCounts()
    runAIClassification(for: syncedEmails)
    await notificationSyncCoordinator.didSyncNewEmails(syncedEmails, fromBackground: false, activeFolderType: selectedFolder?.folderType)
```

**Behavior**

Since IDLE monitoring runs while the app is in the foreground, `fromBackground` is `false`. The `activeFolderType` is passed so the notification service can suppress banners for emails arriving in folders of the same type the user is currently viewing, while still updating the badge. Using `folderType` ensures correct suppression in unified inbox mode.

---

### 3.21a Sync Integration — MacOSMainView (NOTIF-21a)

**Description**

On macOS, `MacOSMainView` (`Presentation/macOS/MacOSMainView.swift`) owns foreground sync and IDLE monitoring. The notification coordinator **MUST** be integrated into all macOS sync paths, mirroring the iOS `ThreadListView` integration.

**Integration Points**

`MacOSMainView` performs sync in three locations, all of which **MUST** pass results to the coordinator:

1. **Initial load / account change sync** — `syncSingleAccount()` (line 609) calls `syncAccountInboxFirst()`. The `activeFolderType` **MUST** only be passed for the currently selected account. Non-selected account syncs **MUST** pass `nil`:
   ```swift
   // Selected account — user is viewing this account's folder
   let selectedEmails = try await syncEmails.syncAccountInboxFirst(
       accountId: selectedId,
       onInboxSynced: { _ in await refreshUI() }
   )
   await notificationSyncCoordinator.markFirstLaunchComplete()
   await notificationSyncCoordinator.didSyncNewEmails(selectedEmails, fromBackground: false, activeFolderType: selectedFolder?.folderType)

   // Non-selected accounts — user is NOT viewing these
   for accountId in allAccountIDs where accountId != selectedId {
       guard !Task.isCancelled else { return }
       let otherEmails = try await syncEmails.syncAccountInboxFirst(
           accountId: accountId,
           onInboxSynced: { _ in /* no UI refresh for non-selected */ }
       )
       await notificationSyncCoordinator.didSyncNewEmails(otherEmails, fromBackground: false, activeFolderType: nil)
   }
   ```

   **Critical**: Non-selected account syncs pass `activeFolderType: nil` because the user is NOT viewing those accounts' folders. Passing `selectedFolder?.folderType` for all accounts would incorrectly suppress notifications for other accounts' inboxes during the macOS multi-account background sync loop (MacOSMainView.swift lines 578-595).

2. **Toolbar manual refresh** — Toolbar sync button (line 417-432) triggers `syncSingleAccount()`. Same integration as above — only the selected account passes `activeFolderType`.

3. **IDLE monitor** — `startIDLEMonitor()` (line 888-912) handles `.newMail` events and calls `syncFolder()` (line 902). IDLE only monitors the selected account, so `activeFolderType` is correct here:
   ```swift
   case .newMail:
       let syncedEmails = try await syncEmails.syncFolder(accountId:, folderId:)
       await notificationSyncCoordinator.didSyncNewEmails(syncedEmails, fromBackground: false, activeFolderType: selectedFolder?.folderType)
   ```

**Modifications Required**

- `MacOSMainView` **MUST** receive `NotificationSyncCoordinator` as a parameter (currently not passed)
- `VaultMailApp.swift` line 66 **MUST** pass the coordinator when creating `MacOSMainView`
- Selected account sync paths **MUST** call `didSyncNewEmails()` with `activeFolderType: selectedFolder?.folderType`
- Non-selected account sync paths **MUST** call `didSyncNewEmails()` with `activeFolderType: nil`
- The first foreground sync **MUST** call `markFirstLaunchComplete()` to clear the first-launch suppression flag

**Note**: On macOS, `BackgroundSyncScheduler` is not used (`#if os(iOS)` guard). IDLE monitoring runs continuously since the app is not suspended, so all sync-to-notification integration happens in `MacOSMainView`.

---

### 3.22 Notification Settings UI (NOTIF-22)

**Description**

The app **MUST** provide a dedicated notification settings interface.

**Navigation**

The existing notification section in `SettingsView` **MUST** be replaced with a `NavigationLink` to `NotificationSettingsView`:

```swift
Section("Notifications") {
    NavigationLink("Notification Settings") {
        NotificationSettingsView()
    }
}
```

**Sections**

The `NotificationSettingsView` **MUST** contain:

1. **System Permission** — Shows current authorization status. If denied, shows "Open Settings" button.

2. **Accounts** — Per-account notification toggles (migrated from existing `SettingsView`). Each toggle shows the account email address and a `Toggle`.

3. **Categories** — Per-category toggles:
   - Primary (default: on)
   - Social (default: on)
   - Promotions (default: on)
   - Updates (default: on)

4. **VIP Contacts** — List of VIP email addresses with:
   - Add button (text field for email input)
   - Swipe-to-delete for removal
   - Description: "VIP contacts always trigger notifications, even during quiet hours or when their category is disabled."

5. **Muted Threads** — List of muted thread subjects with:
   - Swipe-to-unmute
   - Description: "Muted threads never trigger notifications."
   - Thread subjects fetched from SwiftData

6. **Quiet Hours** — Enable toggle + two `DatePicker` controls:
   - "From" time picker (`.hourAndMinute` display)
   - "To" time picker (`.hourAndMinute` display)
   - Description: "Notifications are silenced during quiet hours, except for VIP contacts."

**macOS Settings**

On macOS, the app uses `MacSettingsView` (`Presentation/macOS/MacSettingsView.swift`) with a dedicated Notifications tab hosting `MacNotificationsSettingsTab` (line 71/719). This existing tab has per-account toggles but **MUST** be extended with the same sections as the iOS `NotificationSettingsView` (categories, VIP contacts, muted threads, quiet hours, system permission).

To avoid duplication, a shared `NotificationSettingsContent` view **SHOULD** be extracted containing the reusable form sections. Both iOS `NotificationSettingsView` and macOS `MacNotificationsSettingsTab` **MUST** compose this shared content:

```swift
// Presentation/Settings/NotificationSettingsContent.swift (new shared view)
struct NotificationSettingsContent: View {
    // Contains: accounts section, categories section, VIP contacts,
    // muted threads, quiet hours, system permission
    // Used by both iOS NotificationSettingsView and macOS MacNotificationsSettingsTab
}
```

---

### 3.23 SettingsStore Extensions (NOTIF-23)

**Description**

`SettingsStore` **MUST** be extended with properties and helpers for notification filtering.

**New Properties**

| Property | Type | Default | UserDefaults Key | Storage |
|----------|------|---------|------------------|---------|
| `notificationCategoryPreferences` | `[String: Bool]` | `[:]` (all enabled) | `notifCategoryPreferences` | JSON |
| `vipContacts` | `Set<String>` | `[]` | `vipContacts` | JSON array |
| `mutedThreadIds` | `Set<String>` | `[]` | `mutedThreadIds` | JSON array |
| `quietHoursEnabled` | `Bool` | `false` | `quietHoursEnabled` | Bool |
| `quietHoursStart` | `Int` | `1320` (22:00) | `quietHoursStart` | Int |
| `quietHoursEnd` | `Int` | `420` (07:00) | `quietHoursEnd` | Int |

**New Helper Methods**

```swift
public func notificationCategoryEnabled(for categoryRaw: String) -> Bool
public func toggleMuteThread(threadId: String)
public func addVIPContact(_ email: String)
public func removeVIPContact(_ email: String)
```

**Initialization**

- `notificationCategoryPreferences`: Load via `defaults.json(forKey:) ?? [:]`
- `vipContacts`: Load JSON array, wrap in `Set`
- `mutedThreadIds`: Load JSON array, wrap in `Set`
- `quietHoursStart/End`: Use `defaults.object(forKey:) != nil` check before `.integer(forKey:)` per project convention
- All new properties **MUST** be reset in `resetAll()`

**Persistence Pattern**

Uses existing `defaults.setJSON()` / `defaults.json(forKey:)` extension methods. `didSet` observers write immediately, matching the existing `< 100ms save latency` requirement (NFR-SET-04).

---

### 3.24 macOS Notification Support (NOTIF-24)

**Description**

The notification system **MUST** work on macOS 14+ with platform-appropriate behavior.

**Shared Behavior**

All `UNUserNotificationCenter` APIs (authorization, content, categories, actions, delivery, removal) work identically on macOS 14+. No `#if os(iOS)` guards are needed for core notification logic.

**Platform-Specific Behavior**

| Feature | iOS | macOS |
|---------|-----|-------|
| Badge | `center.setBadgeCount()` | `NSApplication.shared.dockTile.badgeLabel` |
| Background sync | `BGTaskScheduler` (NOTIF-20) | Not applicable (macOS apps run in background natively) |
| Focus Filters | iOS 16+ AppIntents framework | Not applicable in V1 |
| Notification banners | Full support | Full support |
| Notification actions | Full support | Full support (text input reply included) |

**macOS-Specific Notes**

- On macOS, `MacOSMainView` owns all sync paths (initial load, toolbar refresh, IDLE monitoring). NOTIF-21a specifies the required notification coordinator integration for all three paths.
- IDLE monitoring (NOTIF-21/21a) runs continuously on macOS since the app does not get suspended. This provides real-time notifications without any background task infrastructure.
- The existing `#if os(iOS)` guard in `BackgroundSyncScheduler` already handles the platform split for background sync integration.
- The macOS settings UI uses `MacSettingsView` → `MacNotificationsSettingsTab` (not the iOS `SettingsView`). Both platforms **MUST** share notification settings content via `NotificationSettingsContent` (see NOTIF-22).

---

## 4. Non-Functional Requirements

### NFR-NOTIF-01: Notification Delivery Latency

Notification delivery **MUST** complete within 100ms of the sync engine persisting new emails. The filtering pipeline **MUST** execute in under 50ms for a batch of 50 emails.

### NFR-NOTIF-02: Background Budget

Notification posting during background sync **MUST** not consume more than 1 second of the 30-second iOS background execution budget. Given that `UNUserNotificationCenter.add()` takes <10ms per notification, this allows for up to 100 notifications per background sync cycle.

### NFR-NOTIF-03: Memory

The `deliveredNotificationIds` tracking set **MUST** not exceed 10,000 entries. If the set exceeds this limit, the oldest entries **MUST** be evicted (FIFO). Muted thread IDs **SHOULD** be cleaned up on app launch by removing IDs for threads that no longer exist in SwiftData.

### NFR-NOTIF-04: Testability

All notification components **MUST** be testable without the real `UNUserNotificationCenter`. The `NotificationCenterProviding` protocol **MUST** enable full mock injection. Filters **MUST** be independently testable.

### NFR-NOTIF-05: Concurrency Safety

All notification types **MUST** conform to `Sendable`. The `NotificationService` and `NotificationResponseHandler` **MUST** be `@MainActor`-isolated. The filtering pipeline **MUST** be `@MainActor`-isolated since it reads from `SettingsStore` (which is `@MainActor`).

---

## 5. Architecture

### 5.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Sync Layer                            │
│                                                              │
│  BackgroundSyncScheduler  SyncEmailsUseCase  IDLEMonitor    │
│          │                      │                  │         │
│          └──────────┬───────────┘──────────────────┘         │
│                     │ [Email]                                │
│                     ▼                                        │
│         ┌──────────────────────┐                             │
│         │ NotificationSync     │                             │
│         │ Coordinator          │                             │
│         └──────────┬───────────┘                             │
│                    │                                         │
│                    ▼                                         │
│         ┌──────────────────────┐    ┌────────────────────┐  │
│         │ NotificationService  │───▶│ NotificationFilter  │  │
│         │                      │    │ Pipeline            │  │
│         │  - processNewEmails  │    │                     │  │
│         │  - removeNotifs      │    │  VIP (override)     │  │
│         │  - updateBadge       │    │  Account            │  │
│         └──────────┬───────────┘    │  Spam               │  │
│                    │                │  FolderType          │  │
│                    ▼                │  MutedThread         │  │
│         ┌──────────────────────┐    │  Category            │  │
│         │ NotificationCenter   │    │  QuietHours          │  │
│         │ Providing            │    │  FocusMode (stub)    │  │
│         │ (UNUserNotifCenter)  │    └────────────────────┘  │
│         └──────────┬───────────┘                             │
│                    │                                         │
│                    ▼                                         │
│         ┌──────────────────────┐                             │
│         │ NotificationResponse │                             │
│         │ Handler              │                             │
│         │ (Delegate)           │                             │
│         │                      │                             │
│         │  → MarkReadUseCase   │                             │
│         │  → ManageThreadActs  │                             │
│         │  → ComposeEmailUC    │                             │
│         └──────────────────────┘                             │
│                                                              │
│         ┌──────────────────────┐                             │
│         │ SettingsStore        │                             │
│         │ (existing, extended) │                             │
│         │                      │                             │
│         │  + categoryPrefs     │                             │
│         │  + vipContacts       │                             │
│         │  + mutedThreadIds    │                             │
│         │  + quietHours*       │                             │
│         └──────────────────────┘                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Dependency Wiring (AppDependencies)

Assembly order in `AppDependencies.init()`:

1. Create `SettingsStore` (already exists)
2. Create filter instances (VIP, Account, Spam, FolderType, Muted, Category, QuietHours, FocusMode)
3. Create `NotificationFilterPipeline(vipFilter:, filters:)`
4. Create `NotificationService(center:, settingsStore:, emailRepository:, filterPipeline:)`
5. Create `NotificationResponseHandler(manageThreadActions:, markRead:, composeEmail:, emailRepository:, notificationService:)`
6. Create `NotificationSyncCoordinator(notificationService:)`
7. Set `UNUserNotificationCenter.current().delegate = notificationResponseHandler`
8. Call `notificationService.registerCategories()`
9. Pass `notificationSyncCoordinator` to `BackgroundSyncScheduler` (iOS only)
10. Pass `notificationSyncCoordinator` to `MacOSMainView` (macOS only)
11. Inject `notificationSyncCoordinator` into view hierarchy via `.environment()` (for ThreadListView on iOS)

### 5.3 Data Flow — New Email Notification

```
1. Sync detects new email → persists to SwiftData
2. Sync returns [Email] to caller
3. Caller calls notificationSyncCoordinator.didSyncNewEmails(emails, fromBackground:, activeFolderType:)
4. Coordinator calls notificationService.processNewEmails(emails, fromBackground:, activeFolderType:)
5. Service checks isFirstLaunch flag → if true, suppress all and return (badge only)
6. Service applies recency filter (1h background / 5m foreground)
7. Service runs filterPipeline.filter(emails) → qualifying [Email]
8. For each qualifying email (capped at maxNotificationsPerSync = 10, most recent first):
   a. Check deliveredNotificationIds (dedup)
   b. If activeFolderType matches any of email's folder types → skip banner, badge only
   c. Build content via NotificationContentBuilder.build(from:)
   d. Create UNNotificationRequest with identifier "email-\(email.id)"
   e. Post via center.add(request)
   f. Add to deliveredNotificationIds
9. Service calls updateBadgeCount()
```

### 5.4 Data Flow — Notification Action

```
1. User taps action on notification banner
2. iOS/macOS invokes NotificationResponseHandler.didReceive(response:)
3. Handler extracts threadId/emailId from userInfo
4. For default tap action: set coordinator.pendingThreadNavigation = threadId
   (ThreadListView/MacOSMainView reads this on appear or via .onChange)
5. Handler dispatches to appropriate use case:
   - Mark Read → markReadUseCase.markAllRead(in:)
   - Archive → manageThreadActions.archiveThread(id:)
   - Delete → manageThreadActions.deleteThread(id:)
   - Reply → composeEmail pipeline (draft with full 11-param saveDraft → queue → send)
6. Handler calls notificationService.removeNotifications(forThreadId:)
7. Handler calls notificationService.updateBadgeCount()
```

---

## 6. File Manifest

### New Files

| # | File Path (relative to VaultMailPackage/Sources/VaultMailFeature/) | Spec ID |
|---|-------------------------------------------------------------------|---------|
| 1 | `Domain/Protocols/NotificationServiceProtocol.swift` | NOTIF-01 |
| 2 | `Domain/Protocols/NotificationCenterProviding.swift` | NOTIF-01 |
| 3 | `Domain/Protocols/NotificationFilterProtocol.swift` | NOTIF-07 |
| 4 | `Domain/Models/NotificationAuthStatus.swift` | NOTIF-02 |
| 5 | `Data/Notifications/NotificationService.swift` | NOTIF-01 |
| 6 | `Data/Notifications/NotificationResponseHandler.swift` | NOTIF-06 |
| 7 | `Data/Notifications/NotificationContentBuilder.swift` | NOTIF-04 |
| 8 | `Data/Notifications/NotificationFilterPipeline.swift` | NOTIF-07 |
| 9 | `Data/Notifications/NotificationSyncCoordinator.swift` | NOTIF-18 |
| 10 | `Data/Notifications/UNUserNotificationCenterWrapper.swift` | NOTIF-01 |
| 11 | `Data/Notifications/Filters/AccountNotificationFilter.swift` | NOTIF-08 |
| 12 | `Data/Notifications/Filters/CategoryNotificationFilter.swift` | NOTIF-09 |
| 13 | `Data/Notifications/Filters/VIPContactFilter.swift` | NOTIF-10 |
| 14 | `Data/Notifications/Filters/MutedThreadFilter.swift` | NOTIF-11 |
| 15 | `Data/Notifications/Filters/SpamNotificationFilter.swift` | NOTIF-12 |
| 16 | `Data/Notifications/Filters/FolderTypeNotificationFilter.swift` | NOTIF-13 |
| 17 | `Data/Notifications/Filters/QuietHoursFilter.swift` | NOTIF-14 |
| 18 | `Data/Notifications/Filters/FocusModeFilter.swift` | NOTIF-15 |
| 19 | `Presentation/Settings/NotificationSettingsView.swift` | NOTIF-22 |

### New Test Files

| # | File Path (relative to VaultMailPackage/Tests/VaultMailFeatureTests/) | Coverage |
|---|----------------------------------------------------------------------|----------|
| 1 | `NotificationFilterPipelineTests.swift` | NOTIF-07 |
| 2 | `NotificationFiltersTests.swift` | NOTIF-08 through NOTIF-14 |
| 3 | `NotificationContentBuilderTests.swift` | NOTIF-04 |
| 4 | `NotificationServiceTests.swift` | NOTIF-01, NOTIF-17, NOTIF-18 |
| 5 | `SettingsStoreNotificationTests.swift` | NOTIF-23 |
| 6 | `Mocks/MockNotificationCenter.swift` | Test infrastructure |

### New Shared View

| # | File Path (relative to VaultMailPackage/Sources/VaultMailFeature/) | Spec ID |
|---|-------------------------------------------------------------------|---------|
| 20 | `Presentation/Settings/NotificationSettingsContent.swift` | NOTIF-22 |

### Existing Files to Modify

| # | File Path (relative to VaultMailPackage/Sources/VaultMailFeature/ unless noted) | Changes | Spec ID |
|---|---------------------------------------------------------------------------------|---------|---------|
| 1 | `Shared/Services/SettingsStore.swift` | Add 6 properties, 4 helpers, 6 Keys, init logic, resetAll() | NOTIF-23 |
| 2 | `Shared/Constants.swift` | Add notification category/action identifiers, batch limit, recency constants | NOTIF-03 |
| 3 | `Data/Sync/BackgroundSyncScheduler.swift` | Add `NotificationSyncCoordinator?` dependency, call `markFirstLaunchComplete()` + `didSyncNewEmails()` after sync | NOTIF-20 |
| 4 | **`VaultMail/VaultMailApp.swift`** (app target, not in package) | Wire all notification dependencies in AppDependencies; pass coordinator to MacOSMainView | NOTIF-01, 21a |
| 5 | `Presentation/ThreadList/ThreadListView.swift` | Call coordinator after IDLE/foreground sync; observe `pendingThreadNavigation`; add mute action; call `markFirstLaunchComplete()` after first sync | NOTIF-06e, 19, 21, 11 |
| 11 | `Presentation/macOS/MacOSMainView.swift` | Add `NotificationSyncCoordinator` param; call coordinator after all 3 sync paths (initial load, toolbar refresh, IDLE); call `markFirstLaunchComplete()` after first sync | NOTIF-21a |
| 6 | `Presentation/Settings/SettingsView.swift` | Replace inline toggles with NavigationLink | NOTIF-22 |
| 7 | `Presentation/macOS/MacSettingsView.swift` | Replace `MacNotificationsSettingsTab` with `NotificationSettingsContent` | NOTIF-22, 24 |
| 8 | `Presentation/ThreadList/ThreadRowView.swift` | Show muted indicator (bell.slash) | NOTIF-11 |
| 9 | `Domain/Protocols/EmailRepositoryProtocol.swift` | Add `getInboxUnreadCount() -> Int` method | NOTIF-16 |
| 10 | `Data/Repositories/EmailRepositoryImpl.swift` | Implement `getInboxUnreadCount()` | NOTIF-16 |

---

## 7. Implementation Phases

| Phase | Spec IDs | Description | Est. Files |
|-------|----------|-------------|------------|
| 1 | NOTIF-01, 02, 03, 23 | Core service + protocols + SettingsStore extensions + categories | 8 new, 2 modified |
| 2 | NOTIF-04, 05, 17 | Content builder + thread grouping + deduplication | 1 new |
| 3 | NOTIF-07, 08, 12, 13 | Filter pipeline + P0 filters (account, spam, folder type) | 5 new |
| 4 | NOTIF-19, 20, 21, 21a, 16 | Sync integration (iOS + macOS) + badge management | 1 new, 4 modified |
| 5 | NOTIF-06, 18 | Response handler + notification removal | 1 new, 2 modified |
| 6 | NOTIF-09, 10, 11, 14 | P1/P2 filters (category, VIP, muted, quiet hours) | 4 new, 1 modified |
| 7 | NOTIF-22 | Settings UI | 1 new, 1 modified |
| 8 | NOTIF-15, 24 | Focus mode stub + macOS polish | 1 new |

---

## 8. Testing Strategy

### Test Framework

All tests **MUST** use Swift Testing (`@Test`, `#expect`, `#require`, `@Suite`) consistent with the project's existing test infrastructure.

### Mock Infrastructure

`MockNotificationCenter` implementing `NotificationCenterProviding` **MUST** record all calls for assertion:
- `addedRequests: [UNNotificationRequest]`
- `removedIdentifiers: [String]`
- `registeredCategories: Set<UNNotificationCategory>`
- `currentBadgeCount: Int`
- `authorizationGranted: Bool` (configurable)

### Test Suites

**NotificationFilterPipelineTests** (NOTIF-07)
- VIP override bypasses all other filters
- Email fails when any non-VIP filter rejects
- Empty email list returns empty
- Pipeline with all filters passing

**NotificationFiltersTests** (NOTIF-08 through NOTIF-14)
- AccountFilter: enabled/disabled/default states
- CategoryFilter: enabled/disabled/uncategorized states
- VIPFilter: VIP/non-VIP/case-insensitive matching
- MutedThreadFilter: muted/non-muted states
- SpamFilter: spam/non-spam states
- FolderTypeFilter: inbox/sent/drafts/spam/archive/custom folders
- QuietHoursFilter: during/outside/overnight range/disabled states

**NotificationContentBuilderTests** (NOTIF-04)
- Title uses fromName when available, falls back to fromAddress
- Subtitle is subject
- Body is truncated snippet (100 chars)
- threadIdentifier matches email.threadId
- categoryIdentifier is EMAIL_NOTIFICATION
- userInfo contains all required keys

**NotificationServiceTests** (NOTIF-01, NOTIF-17, NOTIF-18)
- processNewEmails posts for qualifying emails
- processNewEmails suppresses duplicates (same email.id)
- removeNotifications by email ID
- removeNotifications by thread ID
- updateBadgeCount sets correct inbox-only count
- `isFirstLaunch` suppresses all notifications before first sync completes
- `isFirstLaunch` is cleared by BackgroundSyncScheduler after first account sync (background-only launch)
- `isFirstLaunch` is cleared by ThreadListView/MacOSMainView after first foreground sync
- Recency filter suppresses emails older than threshold (1h background, 5m foreground)
- `activeFolderType` suppresses banners for actively-viewed folder type (badge still updates)
- `activeFolderType` correctly suppresses in unified inbox mode (matches across all accounts' inboxes)

**SettingsStoreNotificationTests** (NOTIF-23)
- VIP contact add/remove
- Muted thread toggle
- Quiet hours persistence (including midnight boundary)
- Category preferences persistence
- Defaults for new notification settings
- resetAll() clears notification settings

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| First sync floods user with notifications | Poor UX, user disables notifications | Two-layer approach: `isFirstLaunch` flag suppresses ALL notifications until first sync completes (cleared by both foreground views and BackgroundSyncScheduler); recency filter (1h background / 5m foreground) suppresses old emails on subsequent syncs. Does not depend on `folder.lastSyncDate` (which is set inside `syncFolderEmails()` before the `[Email]` return). |
| Background-only launch produces zero notifications | Missed notifications on iOS background wake | `BackgroundSyncScheduler` calls `markFirstLaunchComplete()` after first account sync, ensuring `isFirstLaunch` is cleared even when no foreground view is loaded |
| Unified inbox suppression misses cross-account emails | Banner shown for email user is already viewing | Suppression uses `activeFolderType` (e.g., "inbox") instead of folder ID, matching all folders of the same type across accounts |
| Background 30-second budget exceeded | Missed notifications | Posting is <10ms/notification; filters are all synchronous O(1) lookups |
| `UNUserNotificationCenterDelegate` reassigned by third-party code | Lost action handling | Set delegate in `App.init()`, store handler in `AppDependencies` (retained for app lifetime) |
| Muted thread IDs accumulate indefinitely | UserDefaults bloat | Periodic cleanup on app launch: remove IDs for threads not in SwiftData |
| Reply action sends without user review | Unintended emails | Same SMTP pipeline as in-app compose; V2 may add confirmation step |
| Too many concurrent notifications overwhelm Notification Center | Cluttered UX | Batch limit: max 10 notifications per sync cycle (NOTIF-19, Anti-Flood point 3); excess emails update badge only |
| macOS multi-account sync suppresses other-account notifications | Missed notifications for non-viewed accounts | `activeFolderType` passed only for selected account; non-selected account syncs pass `nil` (NOTIF-21a) |
| Quiet hours time zone changes | Notifications fire during intended quiet | Use `Calendar.current` which respects device time zone automatically |

---

## 10. Future Enhancements (V2)

| Feature | Description |
|---------|-------------|
| APNs remote push | Server-side IMAP IDLE → APNs relay for instant notifications when app is killed |
| Communication notifications | `INSendMessageIntent` for sender avatars in notification banners |
| Rich notification extension | Notification content extension showing email body preview |
| Focus Filters | `FocusFilterIntent` via AppIntents framework for per-Focus-mode notification rules |
| Custom sounds | Per-account or per-category notification sound selection |
| Siri Suggestions | `INSearchForMessagesIntent` for Siri-driven email search |
| Notification summary | Scheduled summary grouping for low-priority categories |
| Watch complications | Apple Watch notification forwarding with quick actions |

---

## Appendix A: Existing Code References

All file paths are relative to `VaultMailPackage/Sources/VaultMailFeature/` unless noted.

| Component | File | Reuse |
|-----------|------|-------|
| `SettingsStore` | `Shared/Services/SettingsStore.swift` | Extend with 6 properties |
| `AppConstants` | `Shared/Constants.swift` | Add notification identifiers + recency constants |
| `BackgroundSyncScheduler` | `Data/Sync/BackgroundSyncScheduler.swift` | Add coordinator parameter; call `markFirstLaunchComplete()` after first account sync |
| `MarkReadUseCase` | `Domain/UseCases/MarkReadUseCase.swift` | Called by response handler; note: `markAllRead(in: Thread)` takes a `Thread` object |
| `ManageThreadActionsUseCase` | `Domain/UseCases/ManageThreadActionsUseCase.swift` | Called by response handler |
| `ComposeEmailUseCase` | `Domain/UseCases/ComposeEmailUseCase.swift` | Called for reply action; `saveDraft()` has 11 parameters (see NOTIF-06d for full mapping) |
| `EmailRepositoryProtocol` | `Domain/Protocols/EmailRepositoryProtocol.swift` | Add new `getInboxUnreadCount()` for badge |
| `EmailRepositoryImpl` | `Data/Repositories/EmailRepositoryImpl.swift` | Implement `getInboxUnreadCount()` |
| `SyncEmailsUseCase` | `Domain/UseCases/SyncEmailsUseCase.swift` | Returns `[Email]` (`@discardableResult`); `syncAccountInboxFirst` has `onInboxSynced` callback (notification calls go after full return, not in callback) |
| `IDLEMonitorUseCase` | `Domain/UseCases/IDLEMonitorUseCase.swift` | `.newMail` events trigger sync → notifications |
| `AppDependencies` | **`VaultMail/VaultMailApp.swift`** (app target) | Wire all notification dependencies |
| `ThreadListView` | `Presentation/ThreadList/ThreadListView.swift` | Call coordinator after sync; observe `pendingThreadNavigation` via `.onChange`; owns `navigationPath`; `selectedFolder?.folderType` for active folder |
| `MacOSMainView` | `Presentation/macOS/MacOSMainView.swift` | Call coordinator after all 3 sync paths; `activeFolderType` only for selected account, `nil` for non-selected account syncs |
| `MacSettingsView` | `Presentation/macOS/MacSettingsView.swift` | Replace `MacNotificationsSettingsTab` with shared `NotificationSettingsContent` |
| `FolderType` | `Domain/Models/FolderType.swift` | `.inbox` for folder type filter |
| `AICategory` | `Domain/Models/Email.swift` or enum file | Category values for filter |
