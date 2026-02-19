---
title: "Notifications — iOS/macOS Implementation Plan"
platform: iOS
spec-ref: docs/features/notifications/spec.md
version: "1.0.0"
status: locked
assignees:
  - Core Team
target-milestone: V1.0
---

# Notifications — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the full local notification system: core service with protocol-based DI, category registration, content building, composable filter pipeline (8 filters with VIP override), notification actions (mark read, archive, delete, reply), sync integration across all three sync paths (background, foreground, IDLE), badge management, deduplication, notification removal, and the notification settings UI.

**Task IDs**: Notifications uses its own namespace (IOS-N-01..08) to avoid collision with other locked feature docs.

**Backend tasks** (IOS-N-01–06) build the notification infrastructure. **UI task** (IOS-N-07) builds the settings interface. **Polish task** (IOS-N-08) adds the Focus mode stub and macOS platform refinements. All tasks are tracked in this plan and the corresponding tasks file.

---

## 2. Platform Context

Refer to Foundation plan Section 2. All notifications are local — triggered on-device via `UNUserNotificationCenter`. No APNs server required. `UNUserNotificationCenter` APIs work identically on iOS 17+ and macOS 14+; platform-specific behavior is limited to badge management (`setBadgeCount` vs `NSApplication.dockTile`) and background sync (`BGTaskScheduler` is iOS-only). macOS settings UI uses `MacSettingsView` → `MacNotificationsSettingsTab` hosting shared `NotificationSettingsContent`.

---

## 3. Architecture Mapping

### Files — Domain Layer

| File | Layer | Purpose |
|------|-------|---------|
| `NotificationServiceProtocol.swift` | Domain/Protocols | `@MainActor` protocol for notification lifecycle: authorize, process, remove, badge |
| `NotificationCenterProviding.swift` | Domain/Protocols | `@MainActor` protocol wrapping `UNUserNotificationCenter` for testability |
| `NotificationFilterProtocol.swift` | Domain/Protocols | `@MainActor` filter protocol: `shouldNotify(for: Email) async -> Bool` |
| `NotificationAuthStatus.swift` | Domain/Models | Sendable enum: notDetermined, authorized, denied, provisional |

### Files — Data Layer

| File | Layer | Purpose |
|------|-------|---------|
| `NotificationService.swift` | Data/Notifications | `@Observable @MainActor` service implementing `NotificationServiceProtocol` — core orchestration |
| `NotificationResponseHandler.swift` | Data/Notifications | `UNUserNotificationCenterDelegate` — handles mark read, archive, delete, reply, tap navigation |
| `NotificationContentBuilder.swift` | Data/Notifications | Builds `UNMutableNotificationContent` from `Email` model |
| `NotificationFilterPipeline.swift` | Data/Notifications | Composable pipeline: VIP override → 7 AND-chained filters |
| `NotificationSyncCoordinator.swift` | Data/Notifications | `@Observable @MainActor` coordinator bridging sync events → service; holds `pendingThreadNavigation` |
| `UNUserNotificationCenterWrapper.swift` | Data/Notifications | Production `NotificationCenterProviding` conformance wrapping real `UNUserNotificationCenter` |
| `AccountNotificationFilter.swift` | Data/Notifications/Filters | Per-account toggle filter — O(1) dictionary lookup |
| `CategoryNotificationFilter.swift` | Data/Notifications/Filters | Per-category toggle filter — O(1) dictionary lookup |
| `VIPContactFilter.swift` | Data/Notifications/Filters | VIP override — O(1) set lookup (runs before pipeline) |
| `MutedThreadFilter.swift` | Data/Notifications/Filters | Muted thread suppression — O(1) set lookup |
| `SpamNotificationFilter.swift` | Data/Notifications/Filters | Spam suppression — O(1) boolean check |
| `FolderTypeNotificationFilter.swift` | Data/Notifications/Filters | Inbox-only filter — O(n) where n = email's folder count |
| `QuietHoursFilter.swift` | Data/Notifications/Filters | Time-based suppression with overnight range support |
| `FocusModeFilter.swift` | Data/Notifications/Filters | Stub (always passes) — V2 implementation |

### Files — Presentation Layer

| File | Layer | Purpose |
|------|-------|---------|
| `NotificationSettingsView.swift` | Presentation/Settings | iOS notification settings (wraps shared content) |
| `NotificationSettingsContent.swift` | Presentation/Settings | Shared settings content: accounts, categories, VIP, muted, quiet hours |

### Files — Test Infrastructure

| File | Layer | Purpose |
|------|-------|---------|
| `MockNotificationCenter.swift` | Tests/Mocks | Mock `NotificationCenterProviding` recording all calls |
| `NotificationFilterPipelineTests.swift` | Tests | Pipeline integration: VIP override, AND logic, empty input |
| `NotificationFiltersTests.swift` | Tests | Individual filter unit tests: account, category, VIP, muted, spam, folder, quiet hours |
| `NotificationContentBuilderTests.swift` | Tests | Content building: title, subtitle, body, thread grouping, userInfo |
| `NotificationServiceTests.swift` | Tests | Service integration: process, dedup, remove, badge, first-launch, recency, batch limit |
| `SettingsStoreNotificationTests.swift` | Tests | SettingsStore extensions: VIP, muted, quiet hours, categories, reset |

### Existing Files to Modify

| File | Change |
|------|--------|
| `Shared/Services/SettingsStore.swift` | Add 6 notification properties, 4 helper methods, 6 UserDefaults keys, init logic, resetAll() |
| `Shared/Constants.swift` | Add notification identifiers (category, actions), `maxNotificationsPerSync`, recency constants |
| `Data/Sync/BackgroundSyncScheduler.swift` | Add `NotificationSyncCoordinator?` param; call `markFirstLaunchComplete()` + `didSyncNewEmails()` |
| `VaultMail/VaultMailApp.swift` (app target) | Wire all notification dependencies in AppDependencies; pass coordinator to MacOSMainView |
| `Presentation/ThreadList/ThreadListView.swift` | Call coordinator after sync; observe `pendingThreadNavigation`; add mute thread action |
| `Presentation/macOS/MacOSMainView.swift` | Add coordinator param; call coordinator after all 3 sync paths; `activeFolderType` only for selected account |
| `Presentation/Settings/SettingsView.swift` | Replace inline notification toggles with NavigationLink to NotificationSettingsView |
| `Presentation/macOS/MacSettingsView.swift` | Replace `MacNotificationsSettingsTab` with shared `NotificationSettingsContent` |
| `Presentation/ThreadList/ThreadRowView.swift` | Show muted indicator (`bell.slash` SF Symbol) |
| `Domain/Protocols/EmailRepositoryProtocol.swift` | Add `getInboxUnreadCount() async throws -> Int` |
| `Data/Repositories/EmailRepositoryImpl.swift` | Implement `getInboxUnreadCount()` — per-Email inbox count |

---

## 4. Implementation Phases

### Phase 1: Core Service + Protocols + Settings Extensions (IOS-N-01)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-01a | `NotificationServiceProtocol` — `@MainActor` protocol with 8 methods | None |
| IOS-N-01b | `NotificationCenterProviding` — `@MainActor` protocol wrapping UNUserNotificationCenter | None |
| IOS-N-01c | `NotificationAuthStatus` — Sendable enum (4 cases) | None |
| IOS-N-01d | `UNUserNotificationCenterWrapper` — production conformance for `NotificationCenterProviding` | IOS-N-01b |
| IOS-N-01e | `NotificationService` — `@Observable @MainActor` class: authorization, `registerCategories()`, `isFirstLaunch` flag, recency filter, dedup set, batch limit, badge management | IOS-N-01a, IOS-N-01b, IOS-N-01c |
| IOS-N-01f | `Constants.swift` — add notification identifiers, recency constants, batch limit | None |
| IOS-N-01g | `SettingsStore` extensions — 6 properties, 4 helpers, 6 keys, init, resetAll() | None |
| IOS-N-01h | `MockNotificationCenter` — test mock recording all calls | IOS-N-01b |
| IOS-N-01i | Unit tests: `NotificationServiceTests`, `SettingsStoreNotificationTests` | IOS-N-01e, IOS-N-01g, IOS-N-01h |

### Phase 2: Content Builder + Thread Grouping + Deduplication (IOS-N-02)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-02a | `NotificationContentBuilder` — build `UNMutableNotificationContent` from `Email`: title, subtitle, body (100 chars), sound, category, threadIdentifier, userInfo | IOS-N-01 |
| IOS-N-02b | Integrate dedup into `NotificationService.processNewEmails()` — `deliveredNotificationIds` set, rebuild on launch | IOS-N-01e |
| IOS-N-02c | Unit tests: `NotificationContentBuilderTests` | IOS-N-02a |

### Phase 3: Filter Pipeline + P0 Filters (IOS-N-03)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-03a | `NotificationFilterProtocol` — `@MainActor` protocol with `shouldNotify(for:)` | None |
| IOS-N-03b | `NotificationFilterPipeline` — VIP override → AND-chained filters | IOS-N-03a |
| IOS-N-03c | `AccountNotificationFilter` — per-account toggle check | IOS-N-03a, IOS-N-01g |
| IOS-N-03d | `SpamNotificationFilter` — `email.isSpam` check | IOS-N-03a |
| IOS-N-03e | `FolderTypeNotificationFilter` — inbox-only check via EmailFolder relationships | IOS-N-03a |
| IOS-N-03f | Unit tests: `NotificationFilterPipelineTests`, `NotificationFiltersTests` (account, spam, folder) | IOS-N-03b–e |

### Phase 4: Sync Integration + Badge Management (IOS-N-04)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-04a | `NotificationSyncCoordinator` — `@Observable @MainActor` facade with `pendingThreadNavigation`, `didSyncNewEmails()`, `markFirstLaunchComplete()` | IOS-N-01e |
| IOS-N-04b | `EmailRepositoryProtocol` + `EmailRepositoryImpl` — add `getInboxUnreadCount()` | None |
| IOS-N-04c | Badge management in `NotificationService` — platform guards (`#if canImport(UIKit/AppKit)`), `updateBadgeCount()` | IOS-N-01e, IOS-N-04b |
| IOS-N-04d | `BackgroundSyncScheduler` integration — add coordinator param, `markFirstLaunchComplete()`, `didSyncNewEmails()` | IOS-N-04a |
| IOS-N-04e | `ThreadListView` integration — call coordinator after foreground/IDLE sync, pass `activeFolderType` | IOS-N-04a |
| IOS-N-04f | `MacOSMainView` integration — call coordinator after all 3 sync paths; `activeFolderType` only for selected account | IOS-N-04a |
| IOS-N-04g | `VaultMailApp.swift` — wire all dependencies in AppDependencies; pass coordinator to views | IOS-N-04a |
| IOS-N-04h | Unit tests for coordinator, badge, and sync integration | IOS-N-04a–g |

### Phase 5: Response Handler + Notification Removal (IOS-N-05)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-05a | `NotificationResponseHandler` — `UNUserNotificationCenterDelegate`: mark read, archive, delete, reply (full 11-param saveDraft), tap navigation via `pendingThreadNavigation` | IOS-N-04a |
| IOS-N-05b | `ThreadListView` — observe `pendingThreadNavigation` via `.onChange(of:)` and `.task` (cold start) | IOS-N-04a |
| IOS-N-05c | `MacOSMainView` — observe `pendingThreadNavigation` | IOS-N-04a |
| IOS-N-05d | Foreground presentation (`willPresent`) — suppress banner when viewing same thread | IOS-N-05a |
| IOS-N-05e | Notification removal — `removeNotifications(forThreadId:)`, `removeNotifications(forEmailIds:)` | IOS-N-01e |
| IOS-N-05f | Unit tests for response handler and removal | IOS-N-05a–e |

### Phase 6: P1/P2 Filters (IOS-N-06)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-06a | `CategoryNotificationFilter` — per-category toggle check from SettingsStore | IOS-N-03a, IOS-N-01g |
| IOS-N-06b | `VIPContactFilter` — VIP override check (runs before pipeline) | IOS-N-03a, IOS-N-01g |
| IOS-N-06c | `MutedThreadFilter` — muted thread suppression | IOS-N-03a, IOS-N-01g |
| IOS-N-06d | `QuietHoursFilter` — time-based suppression with overnight range | IOS-N-03a, IOS-N-01g |
| IOS-N-06e | `ThreadListView` — add mute/unmute swipe action and context menu | IOS-N-06c |
| IOS-N-06f | `ThreadRowView` — show `bell.slash` muted indicator | IOS-N-06c |
| IOS-N-06g | Unit tests: `NotificationFiltersTests` (category, VIP, muted, quiet hours) | IOS-N-06a–d |

### Phase 7: Settings UI (IOS-N-07)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-07a | `NotificationSettingsContent` — shared view: system permission, accounts, categories, VIP contacts, muted threads, quiet hours | IOS-N-01g, IOS-N-06 |
| IOS-N-07b | `NotificationSettingsView` — iOS wrapper composing shared content | IOS-N-07a |
| IOS-N-07c | `SettingsView` — replace inline toggles with NavigationLink | IOS-N-07b |
| IOS-N-07d | `MacSettingsView` — replace `MacNotificationsSettingsTab` with shared content | IOS-N-07a |
| IOS-N-07e | Accessibility annotations (labels, hints, Dynamic Type) | IOS-N-07a–d |

### Phase 8: Focus Mode Stub + macOS Polish (IOS-N-08)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-N-08a | `FocusModeFilter` — stub returning `true` always | IOS-N-03a |
| IOS-N-08b | macOS badge via `NSApplication.shared.dockTile.badgeLabel` with `#if canImport(AppKit)` | IOS-N-04c |
| IOS-N-08c | Integration test: full end-to-end flow on macOS | IOS-N-08a, IOS-N-08b |

---

## 5. Dependency Graph

```
IOS-N-01 (Core Service + Protocols + Settings + Categories)
    |
    +---> IOS-N-02 (Content Builder + Dedup)
    |         |
    +---> IOS-N-03 (Filter Pipeline + P0 Filters)
    |         |
    |         v
    +---> IOS-N-04 (Sync Integration + Badge + Coordinator)
              |
              v
          IOS-N-05 (Response Handler + Removal + Navigation)
              |
    +---------+
    |
    v
IOS-N-06 (P1/P2 Filters: Category, VIP, Muted, Quiet Hours)
    |
    v
IOS-N-07 (Settings UI)
    |
    v
IOS-N-08 (Focus Mode Stub + macOS Polish)
```

**Parallelizable**: IOS-N-02 + IOS-N-03 can be built concurrently after IOS-N-01. IOS-N-03a (filter protocol) has no dependency and can start early. IOS-N-06a–d (individual filters) can be built concurrently.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| First sync floods notifications | High | High | Three-layer anti-flood: `isFirstLaunch` flag, recency filter (1h/5m), batch limit (max 10) |
| Background-only launch misses notifications | Medium | High | `BackgroundSyncScheduler` calls `markFirstLaunchComplete()` after first account sync |
| `UNUserNotificationCenterDelegate` reassigned | Low | High | Set delegate in App.init(); retain handler in AppDependencies |
| Cold-start notification tap fails to navigate | Medium | Medium | `@Observable pendingThreadNavigation` on coordinator — view reads on `.task` appear |
| macOS multi-account suppression | Medium | Medium | `activeFolderType` only for selected account; `nil` for non-selected syncs |
| Reply sends without confirmation | Low | Medium | Same SMTP pipeline as in-app compose; V2 may add confirmation |
| Muted thread ID set grows unbounded | Low | Low | Periodic cleanup on app launch — remove IDs not in SwiftData |
| SwiftData nested predicate for inbox unread count | Medium | Medium | Fallback strategy: two-step query (fetch inbox folders → count emails) |
| Quiet hours time zone changes | Low | Low | `Calendar.current` respects device time zone automatically |
