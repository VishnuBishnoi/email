import Foundation
import Testing
@testable import VaultMailFeature

/// Tests all 7 individual notification filters.
///
/// Filters tested:
/// 1. AccountNotificationFilter — checks account notification enable/disable
/// 2. SpamNotificationFilter — filters out spam emails
/// 3. CategoryNotificationFilter — checks per-category notification preferences
/// 4. VIPContactFilter — checks if sender is a VIP contact
/// 5. MutedThreadFilter — filters out muted threads
/// 6. QuietHoursFilter — respects quiet hours settings
/// 7. FocusModeFilter — stub filter (always returns true)
///
/// Spec ref: NOTIF-07 through NOTIF-15
@Suite("NotificationFilters")
struct NotificationFiltersTests {

    // MARK: - Helpers

    @MainActor
    private static func makeSettingsStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return SettingsStore(defaults: defaults)
    }

    @MainActor
    private static func makeEmail(
        id: String = UUID().uuidString,
        accountId: String = "acc1",
        threadId: String = "thread1",
        fromAddress: String = "sender@test.com",
        isSpam: Bool = false,
        isRead: Bool = false,
        aiCategory: String? = AICategory.uncategorized.rawValue
    ) -> Email {
        Email(
            id: id,
            accountId: accountId,
            threadId: threadId,
            messageId: "msg-\(id)",
            fromAddress: fromAddress,
            subject: "Test",
            isRead: isRead,
            aiCategory: aiCategory,
            isSpam: isSpam
        )
    }

    // MARK: - AccountNotificationFilter Tests

    @Test("Account filter: enabled by default")
    @MainActor
    func accountFilterEnabledByDefault() async {
        let store = Self.makeSettingsStore()
        let filter = AccountNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(accountId: "acc-default")

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Account filter: respects disabled preference")
    @MainActor
    func accountFilterDisabled() async {
        let store = Self.makeSettingsStore()
        store.notificationPreferences["acc1"] = false

        let filter = AccountNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(accountId: "acc1")

        let result = await filter.shouldNotify(for: email)
        #expect(result == false)
    }

    // MARK: - SpamNotificationFilter Tests

    @Test("Spam filter: allows non-spam emails")
    @MainActor
    func spamFilterAllowsNonSpam() async {
        let filter = SpamNotificationFilter()
        let email = Self.makeEmail(isSpam: false)

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Spam filter: blocks spam emails")
    @MainActor
    func spamFilterBlocksSpam() async {
        let filter = SpamNotificationFilter()
        let email = Self.makeEmail(isSpam: true)

        let result = await filter.shouldNotify(for: email)
        #expect(result == false)
    }

    // MARK: - CategoryNotificationFilter Tests

    @Test("Category filter: allows nil category")
    @MainActor
    func categoryFilterNilCategory() async {
        let store = Self.makeSettingsStore()
        let filter = CategoryNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(aiCategory: nil)

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Category filter: allows uncategorized")
    @MainActor
    func categoryFilterUncategorized() async {
        let store = Self.makeSettingsStore()
        let filter = CategoryNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(aiCategory: AICategory.uncategorized.rawValue)

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Category filter: allows enabled category by default")
    @MainActor
    func categoryFilterEnabledByDefault() async {
        let store = Self.makeSettingsStore()
        let filter = CategoryNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(aiCategory: AICategory.social.rawValue)

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Category filter: respects disabled category")
    @MainActor
    func categoryFilterDisabled() async {
        let store = Self.makeSettingsStore()
        store.notificationCategoryPreferences[AICategory.social.rawValue] = false

        let filter = CategoryNotificationFilter(settingsStore: store)
        let email = Self.makeEmail(aiCategory: AICategory.social.rawValue)

        let result = await filter.shouldNotify(for: email)
        #expect(result == false)
    }

    // MARK: - VIPContactFilter Tests

    @Test("VIP filter: non-VIP contact returns false")
    @MainActor
    func vipFilterNonVIP() async {
        let store = Self.makeSettingsStore()
        let filter = VIPContactFilter(settingsStore: store)
        let email = Self.makeEmail(fromAddress: "regular@test.com")

        let result = await filter.shouldNotify(for: email)
        #expect(result == false)
    }

    @Test("VIP filter: VIP contact returns true")
    @MainActor
    func vipFilterIsVIP() async {
        let store = Self.makeSettingsStore()
        store.addVIPContact("vip@test.com")

        let filter = VIPContactFilter(settingsStore: store)
        let email = Self.makeEmail(fromAddress: "vip@test.com")

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("VIP filter: case-insensitive VIP matching")
    @MainActor
    func vipFilterCaseInsensitive() async {
        let store = Self.makeSettingsStore()
        store.addVIPContact("VIP@TEST.COM")

        let filter = VIPContactFilter(settingsStore: store)
        let email = Self.makeEmail(fromAddress: "vip@test.com")

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    // MARK: - MutedThreadFilter Tests

    @Test("Muted filter: allows unmuted thread")
    @MainActor
    func mutedFilterUnmuted() async {
        let store = Self.makeSettingsStore()
        let filter = MutedThreadFilter(settingsStore: store)
        let email = Self.makeEmail(threadId: "thread1")

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    @Test("Muted filter: blocks muted thread")
    @MainActor
    func mutedFilterMuted() async {
        let store = Self.makeSettingsStore()
        store.toggleMuteThread(threadId: "thread1")

        let filter = MutedThreadFilter(settingsStore: store)
        let email = Self.makeEmail(threadId: "thread1")

        let result = await filter.shouldNotify(for: email)
        #expect(result == false)
    }

    // MARK: - QuietHoursFilter Tests

    @Test("Quiet hours filter: disabled returns true")
    @MainActor
    func quietHoursFilterDisabled() async {
        let store = Self.makeSettingsStore()
        store.quietHoursEnabled = false

        let filter = QuietHoursFilter(settingsStore: store)
        let email = Self.makeEmail()

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

    // MARK: - FocusModeFilter Tests

    @Test("Focus mode filter: always returns true")
    @MainActor
    func focusModeFilterAlwaysTrue() async {
        let filter = FocusModeFilter()
        let email = Self.makeEmail()

        let result = await filter.shouldNotify(for: email)
        #expect(result == true)
    }

}
