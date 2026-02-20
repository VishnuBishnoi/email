---
title: "Notifications — iOS/macOS Validation"
spec-ref: docs/features/notifications/spec.md
plan-refs:
  - docs/features/notifications/ios-macos/plan.md
  - docs/features/notifications/ios-macos/tasks.md
version: "1.0.0"
status: locked
last-validated: null
---

# Notifications — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| NOTIF-01 | Notification service protocol + DI | MUST | AC-N-01 | iOS, macOS | — |
| NOTIF-02 | Authorization request flow | MUST | AC-N-02 | iOS, macOS | — |
| NOTIF-03 | Category registration (4 actions) | MUST | AC-N-01 | iOS, macOS | — |
| NOTIF-04 | Notification content builder | MUST | AC-N-03 | iOS, macOS | — |
| NOTIF-05 | Thread grouping via threadIdentifier | MUST | AC-N-04 | iOS, macOS | — |
| NOTIF-06 | Response handling (mark read, archive, delete, reply, tap) | MUST | AC-N-16, AC-N-17, AC-N-18, AC-N-19, AC-N-20 | iOS, macOS | — |
| NOTIF-07 | Composable filter pipeline | MUST | AC-N-05 | iOS, macOS | — |
| NOTIF-08 | Account notification filter | MUST | AC-N-06 | iOS, macOS | — |
| NOTIF-09 | Category notification filter | MUST | AC-N-07 | iOS, macOS | — |
| NOTIF-10 | VIP contact override | MUST | AC-N-05 | iOS, macOS | — |
| NOTIF-11 | Muted thread filter | MUST | AC-N-08 | iOS, macOS | — |
| NOTIF-12 | Spam notification filter | MUST | AC-N-06 | iOS, macOS | — |
| NOTIF-13 | Folder type filter (inbox only) | MUST | AC-N-06 | iOS, macOS | — |
| NOTIF-14 | Quiet hours filter | MUST | AC-N-07 | iOS, macOS | — |
| NOTIF-15 | Focus mode filter (stub) | MAY | AC-N-23 | iOS | — |
| NOTIF-16 | Badge management | MUST | AC-N-09 | iOS, macOS | — |
| NOTIF-17 | Deduplication | MUST | AC-N-10 | iOS, macOS | — |
| NOTIF-18 | Notification removal on state change | MUST | AC-N-11 | iOS, macOS | — |
| NOTIF-19 | Sync integration — foreground | MUST | AC-N-12, AC-N-13 | iOS, macOS | — |
| NOTIF-20 | Sync integration — background | MUST | AC-N-13 | iOS | — |
| NOTIF-21 | Sync integration — IDLE | MUST | AC-N-12 | iOS, macOS | — |
| NOTIF-21a | Sync integration — MacOSMainView | MUST | AC-N-15 | macOS | — |
| NOTIF-22 | Notification settings UI | MUST | AC-N-21, AC-N-22 | iOS, macOS | — |
| NOTIF-23 | SettingsStore extensions | MUST | AC-N-14 | iOS, macOS | — |
| NOTIF-24 | macOS notification support | MUST | AC-N-15, AC-N-23 | macOS | — |
| NFR-NOTIF-01 | Delivery latency (<100ms) | MUST | AC-N-24 | iOS, macOS | — |
| NFR-NOTIF-02 | Background budget (<1s) | MUST | AC-N-25 | iOS | — |
| NFR-NOTIF-03 | Memory (dedup set <10K) | MUST | AC-N-26 | iOS, macOS | — |
| NFR-NOTIF-04 | Testability (full mock injection) | MUST | AC-N-01 | iOS, macOS | — |
| NFR-NOTIF-05 | Concurrency safety (Sendable, @MainActor) | MUST | AC-N-27 | iOS, macOS | — |

---

## 2. Acceptance Criteria

---

**AC-N-01**: Core Service — Initialization and Category Registration

- **Given**: The app is launched for the first time
- **When**: `AppDependencies.init()` completes
- **Then**:
  - `NotificationService` **MUST** be created and available via `.environment()`
  - `registerCategories()` **MUST** have been called
  - One category (`EMAIL_NOTIFICATION`) **MUST** be registered with 4 actions: Mark Read, Archive, Delete, Reply
  - The Reply action **MUST** be `UNTextInputNotificationAction` with button "Send" and placeholder "Type your reply..."
  - `UNUserNotificationCenter.current().delegate` **MUST** be set to `NotificationResponseHandler`
  - All notification types **MUST** conform to `Sendable`
  - `NotificationService` and `NotificationResponseHandler` **MUST** be `@MainActor`-isolated
- **Priority**: High

---

**AC-N-02**: Authorization Flow

- **Given**: The user has just added their first account during onboarding
- **When**: The onboarding ready step is reached
- **Then**: `requestAuthorization()` **MUST** be called with options `.alert`, `.badge`, `.sound`
- **When**: The user grants permission
- **Then**: `authorizationStatus()` **MUST** return `.authorized`
- **When**: The user denies permission
- **Then**: The notification settings UI **MUST** show an "Open Settings" button
- **When**: The user enables notifications for an account and authorization is `.notDetermined`
- **Then**: Permission **MUST** be requested before enabling the toggle; if denied, the toggle **MUST** remain off
- **Priority**: High

---

**AC-N-03**: Notification Content

- **Given**: A new email from "John Doe <john@example.com>" with subject "Meeting Tomorrow" and snippet "Hi team, let's discuss the Q1 budget review next week..."
- **When**: `NotificationContentBuilder.build(from: email)` is called
- **Then**:
  - Title **MUST** be "John Doe"
  - Subtitle **MUST** be "Meeting Tomorrow"
  - Body **MUST** be the first 100 characters of the snippet
  - Sound **MUST** be `.default`
  - Category identifier **MUST** be `EMAIL_NOTIFICATION`
  - `threadIdentifier` **MUST** be `email.threadId`
  - `userInfo` **MUST** contain `emailId`, `threadId`, `accountId`, `fromAddress`
  - Request identifier **MUST** be `"email-\(email.id)"`
- **Given**: An email with `fromName == nil`
- **When**: Content is built
- **Then**: Title **MUST** fall back to `fromAddress`
- **Priority**: High

---

**AC-N-04**: Thread Grouping

- **Given**: 3 new emails in the same thread arrive during sync
- **When**: Notifications are posted for all 3 emails
- **Then**:
  - All 3 notifications **MUST** have the same `threadIdentifier` (equal to `email.threadId`)
  - iOS/macOS **MUST** group them into a single notification group
  - The most recent email **MUST** be shown on top
- **Given**: 2 emails from different threads arrive
- **When**: Notifications are posted
- **Then**: They **MUST** appear as separate notification groups
- **Priority**: Medium

---

**AC-N-05**: Filter Pipeline — VIP Override and AND Logic

- **Given**: A VIP contact sends an email during quiet hours, to a muted thread, in a disabled category
- **When**: The filter pipeline evaluates the email
- **Then**: The email **MUST** bypass ALL filters and trigger a notification (VIP override)
- **Given**: A non-VIP email passes the account filter but the sender's category is disabled
- **When**: The filter pipeline evaluates the email
- **Then**: The email **MUST NOT** trigger a notification (AND logic — any filter rejection suppresses)
- **Given**: A non-VIP email passes all filters
- **When**: The pipeline evaluates
- **Then**: The email **MUST** trigger a notification
- **Given**: An empty email list
- **When**: The pipeline processes it
- **Then**: An empty result **MUST** be returned with no errors
- **Priority**: High

---

**AC-N-06**: P0 Filters — Account, Spam, Folder Type

- **Given**: An account with notifications disabled
- **When**: A new email arrives for that account
- **Then**: The `AccountNotificationFilter` **MUST** suppress the notification
- **Given**: An email with `isSpam == true`
- **When**: The filter evaluates it
- **Then**: The `SpamNotificationFilter` **MUST** suppress the notification
- **Given**: An email only in the Sent folder (no inbox association)
- **When**: The filter evaluates it
- **Then**: The `FolderTypeNotificationFilter` **MUST** suppress the notification
- **Given**: An email in both Inbox and Starred folders
- **When**: The filter evaluates it
- **Then**: The `FolderTypeNotificationFilter` **MUST** allow the notification (inbox association present)
- **Priority**: High

---

**AC-N-07**: P1 Filters — Category, Quiet Hours

- **Given**: An email with `aiCategory == "promotions"` and promotions category notifications disabled
- **When**: The filter evaluates it
- **Then**: The `CategoryNotificationFilter` **MUST** suppress the notification
- **Given**: An email with `aiCategory == nil`
- **When**: The filter evaluates it
- **Then**: The `CategoryNotificationFilter` **MUST** allow it (uncategorized always passes)
- **Given**: Quiet hours enabled (22:00–07:00), current time is 23:30
- **When**: The filter evaluates an email
- **Then**: The `QuietHoursFilter` **MUST** suppress the notification
- **Given**: Quiet hours enabled (22:00–07:00), current time is 12:00
- **When**: The filter evaluates an email
- **Then**: The `QuietHoursFilter` **MUST** allow the notification
- **Given**: Quiet hours disabled
- **When**: The filter evaluates any email
- **Then**: The `QuietHoursFilter` **MUST** always allow the notification
- **Priority**: Medium

---

**AC-N-08**: P2 Filters — VIP Contacts, Muted Threads

- **Given**: `settingsStore.vipContacts` contains "john@example.com"
- **When**: An email from "John@Example.com" (different case) is evaluated
- **Then**: The VIP filter **MUST** match (case-insensitive) and override all other filters
- **Given**: `settingsStore.mutedThreadIds` contains thread "T-123"
- **When**: An email in thread "T-123" is evaluated
- **Then**: The `MutedThreadFilter` **MUST** suppress the notification
- **Given**: A non-muted thread
- **When**: An email is evaluated
- **Then**: The `MutedThreadFilter` **MUST** allow the notification
- **Priority**: Medium

---

**AC-N-09**: Badge Management

- **Given**: 50 unread emails in inbox folders, 20 unread in archive/spam (not inbox)
- **When**: `updateBadgeCount()` is called
- **Then**:
  - Badge count **MUST** be 50 (inbox-only, NOT 70)
  - On iOS: `UNUserNotificationCenter.setBadgeCount(50)` **MUST** be called
  - On macOS: `NSApplication.shared.dockTile.badgeLabel` **MUST** be set to "50"
- **Given**: All emails are read
- **When**: `updateBadgeCount()` is called
- **Then**: Badge **MUST** be 0 (iOS: `setBadgeCount(0)`, macOS: `badgeLabel = nil`)
- **When**: A notification action (mark read) is handled
- **Then**: Badge **MUST** be updated after the action completes
- **Priority**: High

---

**AC-N-10**: Deduplication

- **Given**: An email with `id = "abc123"` has already been notified
- **When**: The same email is synced again (e.g., from another folder)
- **Then**: A duplicate notification **MUST NOT** be posted (checked via `deliveredNotificationIds` set)
- **Given**: The app is terminated and relaunched
- **When**: `deliveredNotificationIds` is rebuilt from `center.deliveredNotifications()`
- **Then**: Previously delivered notifications **MUST** be recognized and not re-posted
- **Given**: The dedup set reaches 10,000 entries
- **When**: A new notification is posted
- **Then**: The oldest entry **MUST** be evicted (FIFO) before adding the new one
- **Priority**: High

---

**AC-N-11**: Notification Removal on State Change

- **Given**: The user marks a thread as read in-app
- **When**: `didMarkThreadRead(threadId:)` is called on the coordinator
- **Then**: All delivered notifications for that thread **MUST** be removed from the notification center
- **Given**: The user archives a thread in-app
- **When**: `didRemoveThread(threadId:)` is called
- **Then**: All delivered notifications for that thread **MUST** be removed
- **Given**: The user deletes a thread in-app
- **When**: `didRemoveThread(threadId:)` is called
- **Then**: All delivered notifications for that thread **MUST** be removed and badge **MUST** be updated
- **Priority**: High

---

**AC-N-12**: Sync Integration — Foreground + IDLE

- **Given**: The app is in the foreground and `syncAccountInboxFirst()` returns 5 new emails
- **When**: Sync completes (all folders)
- **Then**:
  - `markFirstLaunchComplete()` **MUST** be called
  - `didSyncNewEmails(emails, fromBackground: false, activeFolderType:)` **MUST** be called
  - Qualifying emails **MUST** produce notifications
  - `activeFolderType` **MUST** be `selectedFolder?.folderType`
- **Given**: IDLE monitor detects `.newMail` and `syncFolder()` returns 2 new emails
- **When**: The sync completes
- **Then**:
  - `didSyncNewEmails(emails, fromBackground: false, activeFolderType:)` **MUST** be called
  - The `activeFolderType` **MUST** suppress banners for the currently viewed folder type
- **Priority**: High

---

**AC-N-13**: Anti-Flood — First Launch + Recency + Batch Limit

- **Given**: The app just launched (fresh session, `isFirstLaunch == true`)
- **When**: The first sync returns 500 historical emails
- **Then**: ALL notifications **MUST** be suppressed (first-launch flag active)
- **When**: `markFirstLaunchComplete()` is called and the second sync returns 3 new emails (received 2 minutes ago)
- **Then**: Only those 3 emails **MUST** trigger notifications (first-launch cleared, recency passes)
- **Given**: Background sync finds emails received 2 hours ago
- **When**: `processNewEmails(fromBackground: true)` is called
- **Then**: Those emails **MUST** be suppressed by the recency filter (>1 hour old)
- **Given**: Foreground sync returns 15 qualifying emails
- **When**: `processNewEmails()` processes them
- **Then**: Only the 10 most recent (by `dateReceived`) **MUST** produce banners; remaining 5 update badge only
- **Priority**: High

---

**AC-N-14**: SettingsStore Extensions

- **Given**: A fresh install with no notification preferences set
- **When**: SettingsStore loads
- **Then**:
  - `notificationCategoryPreferences` **MUST** be `[:]` (empty = all categories enabled)
  - `vipContacts` **MUST** be empty set
  - `mutedThreadIds` **MUST** be empty set
  - `quietHoursEnabled` **MUST** be `false`
  - `quietHoursStart` **MUST** be `1320` (22:00)
  - `quietHoursEnd` **MUST** be `420` (07:00)
- **When**: `addVIPContact("John@Example.com")` is called
- **Then**: `vipContacts` **MUST** contain "john@example.com" (lowercased)
- **When**: `toggleMuteThread(threadId: "T-123")` is called twice
- **Then**: First call **MUST** add "T-123" to `mutedThreadIds`; second call **MUST** remove it
- **When**: `resetAll()` is called
- **Then**: All 6 notification properties **MUST** be reset to defaults
- **Priority**: Medium

---

**AC-N-15**: macOS Multi-Account Sync

- **Given**: macOS with 3 accounts, Account A selected, Accounts B and C not selected
- **When**: `MacOSMainView` performs initial load sync
- **Then**:
  - Account A sync **MUST** pass `activeFolderType: selectedFolder?.folderType`
  - Accounts B and C sync **MUST** pass `activeFolderType: nil`
  - Notifications for B and C inboxes **MUST NOT** be suppressed by Account A's active folder
- **Given**: macOS toolbar refresh triggered
- **When**: Sync completes for all accounts
- **Then**: Same `activeFolderType` behavior as initial load (only selected account passes folder type)
- **Given**: IDLE monitor detects new mail on macOS
- **When**: `syncFolder()` returns new emails
- **Then**: `didSyncNewEmails(activeFolderType: selectedFolder?.folderType)` **MUST** be called
- **Priority**: High

---

**AC-N-16**: Response — Mark Read Action

- **Given**: A notification for thread "T-456" is displayed
- **When**: The user taps "Mark Read"
- **Then**:
  - `markReadUseCase.markAllRead(in: thread)` **MUST** be called (with `Thread` object, not String ID)
  - Notification **MUST** be removed from notification center
  - Badge **MUST** be updated
- **Priority**: High

---

**AC-N-17**: Response — Archive Action

- **Given**: A notification for thread "T-456" is displayed
- **When**: The user taps "Archive"
- **Then**:
  - `manageThreadActions.archiveThread(id: "T-456")` **MUST** be called
  - Notification **MUST** be removed
  - Badge **MUST** be updated
- **Priority**: High

---

**AC-N-18**: Response — Delete Action

- **Given**: A notification for thread "T-456" is displayed
- **When**: The user taps "Delete"
- **Then**:
  - `manageThreadActions.deleteThread(id: "T-456")` **MUST** be called
  - Notification **MUST** be removed
  - Badge **MUST** be updated
- **Priority**: High

---

**AC-N-19**: Response — Reply Action

- **Given**: A notification for email "E-789" in thread "T-456" from "sender@example.com"
- **When**: The user taps "Reply" and enters "Thanks, I'll be there!"
- **Then**:
  - Original email **MUST** be fetched via `emailRepository.getEmail(id: "E-789")`
  - `composeEmail.saveDraft()` **MUST** be called with all 11 parameters:
    - `toAddresses: [originalEmail.fromAddress]`
    - `subject: "Re: " + originalEmail.subject` (or original subject if already prefixed)
    - `bodyPlain: "Thanks, I'll be there!"`
    - `inReplyTo: originalEmail.messageId`
    - `references: [originalEmail.references, originalEmail.messageId].compactMap{$0}.joined(separator: " ")`
  - `queueForSending` and `executeSend` **MUST** be called
  - Notification **MUST** be removed and badge updated
- **Priority**: High

---

**AC-N-20**: Response — Tap Navigation

- **Given**: A notification for thread "T-456" is displayed
- **When**: The user taps the notification body
- **Then**:
  - `coordinator.pendingThreadNavigation` **MUST** be set to "T-456"
  - `ThreadListView` **MUST** navigate to `EmailDetailView` for thread "T-456"
  - `pendingThreadNavigation` **MUST** be set back to `nil` after navigation
- **Given**: The app is terminated and the user taps a notification (cold start)
- **When**: The app launches
- **Then**:
  - `pendingThreadNavigation` **MUST** be non-nil before `ThreadListView` appears
  - `ThreadListView` **MUST** read the value in `.task` and navigate immediately
  - Navigation **MUST** succeed without race conditions
- **Priority**: High

---

**AC-N-21**: Notification Settings UI

- **Given**: The user navigates to Settings > Notification Settings
- **When**: The `NotificationSettingsView` is displayed
- **Then**:
  - System permission section **MUST** show current authorization status
  - If authorization is denied, an "Open Settings" button **MUST** be shown
  - Per-account notification toggles **MUST** be displayed for each account
  - Per-category toggles **MUST** be shown: Primary, Social, Promotions, Updates
  - VIP contacts section **MUST** show list with add/delete functionality
  - Muted threads section **MUST** show thread subjects with unmute option
  - Quiet hours section **MUST** have enable toggle + two time pickers
- **Priority**: Medium

---

**AC-N-22**: Settings UI — Accessibility

- **Given**: VoiceOver is enabled
- **When**: The user navigates to Notification Settings
- **Then**:
  - All toggles **MUST** announce their purpose (e.g., "Notifications for john@example.com, on")
  - VIP contacts list items **MUST** announce the email address
  - Quiet hours time pickers **MUST** announce "Quiet hours start time" / "Quiet hours end time"
  - All text **MUST** scale with Dynamic Type
  - Muted threads **MUST** announce "Muted thread: [subject]"
- **Priority**: High

---

**AC-N-23**: Focus Mode Stub + macOS Platform

- **Given**: The `FocusModeFilter` is included in the pipeline
- **When**: Any email is evaluated
- **Then**: The filter **MUST** always return `true` (V1 stub)
- **Given**: macOS 14+ running the app
- **When**: New emails arrive and are synced
- **Then**:
  - Notifications **MUST** appear as macOS banners
  - All 4 actions **MUST** work (including text input reply)
  - Dock badge **MUST** update via `NSApplication.shared.dockTile.badgeLabel`
- **Priority**: Low

---

**AC-N-24**: Performance — Delivery Latency

- **Given**: 50 new emails arrive during a sync
- **When**: `processNewEmails()` is called
- **Then**:
  - Notification delivery **MUST** complete within 100ms of sync persistence
  - The filtering pipeline **MUST** execute in under 50ms for the batch
  - Query parsing (filter evaluation) per email **MUST** complete in <1ms
- **Priority**: High

---

**AC-N-25**: Performance — Background Budget

- **Given**: Background sync discovers 20 new emails
- **When**: Notifications are posted during background sync
- **Then**:
  - Total notification posting time **MUST NOT** exceed 1 second
  - Individual `UNUserNotificationCenter.add()` calls **MUST** complete in <10ms each
  - Combined with sync, total background execution **MUST** stay within 30-second iOS budget
- **Priority**: High

---

**AC-N-26**: Memory — Dedup Set Limits

- **Given**: The `deliveredNotificationIds` set has 10,000 entries
- **When**: A new notification is posted
- **Then**: The oldest entry **MUST** be evicted (FIFO) before adding the new one
- **When**: The set has fewer than 10,000 entries
- **Then**: Entries **MUST** be added without eviction
- **Priority**: Medium

---

**AC-N-27**: Concurrency Safety

- **Given**: The notification system is compiled with Swift 6 strict concurrency
- **When**: The project builds
- **Then**:
  - No concurrency warnings **MUST** be emitted from notification code
  - `NotificationAuthStatus` **MUST** conform to `Sendable`
  - `NotificationService` **MUST** be `@MainActor`-isolated
  - `NotificationResponseHandler` **MUST** be `@MainActor`-isolated
  - `NotificationFilterPipeline` **MUST** be `@MainActor`-isolated
  - All filter types **MUST** be `@MainActor`-isolated (read from `SettingsStore`)
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior | Test Case |
|---|---------|-------------------|-----------
| E-01 | Email with nil fromName | Title falls back to fromAddress | AC-N-03 |
| E-02 | Email with nil snippet | Body is empty string | Unit test |
| E-03 | Email with snippet > 100 chars | Body truncated at 100 characters | AC-N-03 |
| E-04 | VIP + muted thread + quiet hours + spam | VIP overrides ALL — notification sent | AC-N-05 |
| E-05 | Email only in Drafts folder | Suppressed by FolderTypeNotificationFilter | AC-N-06 |
| E-06 | Email in Inbox + Starred (Gmail multi-folder) | Allowed — inbox association present | AC-N-06 |
| E-07 | aiCategory is nil | CategoryNotificationFilter passes (uncategorized) | AC-N-07 |
| E-08 | Quiet hours overnight (22:00–07:00), time is 06:59 | Suppressed (within overnight range) | AC-N-07 |
| E-09 | Quiet hours overnight (22:00–07:00), time is 07:00 | Allowed (outside range) | AC-N-07 |
| E-10 | Quiet hours normal (09:00–17:00), time is 12:00 | Suppressed (within normal range) | Unit test |
| E-11 | Same email synced from 2 folders | Only one notification (dedup by email.id) | AC-N-10 |
| E-12 | App killed → cold start via notification tap | Navigation succeeds via pendingThreadNavigation | AC-N-20 |
| E-13 | 500 emails on first sync | ALL suppressed by isFirstLaunch flag | AC-N-13 |
| E-14 | 15 qualifying emails in one sync | Max 10 banners posted, 5 badge-only | AC-N-13 |
| E-15 | Background sync, email 2 hours old | Suppressed by recency filter (>1h) | AC-N-13 |
| E-16 | Foreground sync, email 10 minutes old | Suppressed by recency filter (>5m) | AC-N-13 |
| E-17 | Reply to email with "Re:" already in subject | Subject not double-prefixed | AC-N-19 |
| E-18 | Delete action on already-deleted email | Graceful error handling, no crash | Unit test |
| E-19 | Authorization denied → enable per-account toggle | Request permission first; if denied, toggle stays off | AC-N-02 |
| E-20 | macOS non-selected account sync | activeFolderType: nil — notifications not suppressed | AC-N-15 |
| E-21 | Muted thread cleanup on launch | Remove IDs for threads no longer in SwiftData | Unit test |
| E-22 | VIP contact case sensitivity | "John@Example.com" matches "john@example.com" | AC-N-08 |
| E-23 | Dedup set at 10K capacity | FIFO eviction of oldest entry | AC-N-26 |
| E-24 | Foreground — viewing same thread that triggers notification | Banner suppressed, badge still updates | Unit test |
| E-25 | Background-only launch (no foreground view) | BackgroundSyncScheduler calls markFirstLaunchComplete | AC-N-13 |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Corpus | Measurement Method | Failure Threshold |
|--------|--------|------------|--------|--------------------|-------------------|
| End-to-end delivery (50 emails) | <50ms | <100ms | 50 new emails | Time from processNewEmails() call to last center.add() | Fails if >100ms |
| Filter pipeline (50 emails) | <25ms | <50ms | 50 emails, 8 filters | Time for full pipeline evaluation | Fails if >50ms |
| Single filter evaluation | <0.5ms | <1ms | 1 email | Time for one filter's shouldNotify() | Fails if >1ms |
| Content building | <1ms | <5ms | 1 email | Time for NotificationContentBuilder.build() | Fails if >5ms |
| Badge count query | <10ms | <50ms | 10K emails | EmailRepository.getInboxUnreadCount() | Fails if >50ms |
| Badge count query (large) | <50ms | <200ms | 50K emails | EmailRepository.getInboxUnreadCount() | Fails if >200ms |
| Notification posting | <5ms | <10ms | 1 notification | Time for center.add() call | Fails if >10ms |
| Dedup set lookup | <0.01ms | <0.1ms | 10K entries | Set.contains() check | Fails if >0.1ms |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix. Additional notification-specific tests:

| Device | Key Validation |
|--------|----------------|
| iPhone SE (3rd gen) | Performance on low-RAM device; notification delivery latency |
| iPhone 16 | Full notification flow: post, actions, badge, removal |
| iPhone 16 Pro Max | Background sync budget compliance; large email corpus |
| iPad Air | Notification actions on iPad; larger screen settings UI |
| MacBook Air M2 | macOS dock badge; notification actions; MacOSMainView integration |
| Mac mini M2 | macOS headless-like scenario; IDLE real-time notifications |

---

## 6. Test Coverage Requirements

| Component | Min Unit Tests | Key Scenarios |
|-----------|---------------|---------------|
| NotificationService | 15 | Authorization, processNewEmails, first-launch, recency, dedup, batch limit, badge, removal |
| NotificationContentBuilder | 6 | Title/subtitle/body, fallbacks, userInfo, threadIdentifier, request ID |
| NotificationFilterPipeline | 5 | VIP override, AND logic, all pass, single reject, empty input |
| AccountNotificationFilter | 3 | Enabled, disabled, default state |
| SpamNotificationFilter | 2 | Spam true, spam false |
| FolderTypeNotificationFilter | 4 | Inbox, sent, drafts, multi-folder (inbox+starred) |
| CategoryNotificationFilter | 4 | Enabled, disabled, nil category, uncategorized |
| VIPContactFilter | 3 | VIP match, non-VIP, case-insensitive |
| MutedThreadFilter | 2 | Muted, non-muted |
| QuietHoursFilter | 5 | During hours, outside hours, overnight range, disabled, boundary |
| FocusModeFilter | 1 | Stub returns true |
| NotificationResponseHandler | 6 | Mark read, archive, delete, reply (11-param), default tap, foreground presentation |
| NotificationSyncCoordinator | 5 | didSyncNewEmails, didMarkThreadRead, didRemoveThread, markFirstLaunchComplete, pendingThreadNavigation |
| SettingsStore (notification) | 8 | VIP add/remove, muted toggle, quiet hours persistence, category prefs, defaults, resetAll, case normalization |

---

## 7. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
