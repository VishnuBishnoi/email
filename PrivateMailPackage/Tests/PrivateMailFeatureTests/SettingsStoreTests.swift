import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("SettingsStore")
struct SettingsStoreTests {

    /// Creates a SettingsStore backed by a unique, ephemeral UserDefaults suite.
    @MainActor
    private static func makeStore() -> (SettingsStore, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        return (store, defaults)
    }

    // MARK: - Defaults

    @Test("Default theme is system")
    @MainActor
    func defaultTheme() {
        let (store, _) = Self.makeStore()
        #expect(store.theme == .system)
    }

    @Test("Default undo send delay is 5 seconds")
    @MainActor
    func defaultUndoSendDelay() {
        let (store, _) = Self.makeStore()
        #expect(store.undoSendDelay == .fiveSeconds)
    }

    @Test("Default category visibility is all true")
    @MainActor
    func defaultCategoryVisibility() {
        let (store, _) = Self.makeStore()
        #expect(store.categoryTabVisibility[AICategory.primary.rawValue] == true)
        #expect(store.categoryTabVisibility[AICategory.social.rawValue] == true)
        #expect(store.categoryTabVisibility[AICategory.promotions.rawValue] == true)
        #expect(store.categoryTabVisibility[AICategory.updates.rawValue] == true)
    }

    @Test("Default app lock is disabled")
    @MainActor
    func defaultAppLock() {
        let (store, _) = Self.makeStore()
        #expect(store.appLockEnabled == false)
    }

    @Test("Default onboarding is not complete")
    @MainActor
    func defaultOnboarding() {
        let (store, _) = Self.makeStore()
        #expect(store.isOnboardingComplete == false)
    }

    @Test("Default sending account is nil")
    @MainActor
    func defaultSendingAccount() {
        let (store, _) = Self.makeStore()
        #expect(store.defaultSendingAccountId == nil)
    }

    // MARK: - Persistence Round-Trip

    @Test("Theme persists across instances")
    @MainActor
    func themePersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.theme = .dark

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.theme == .dark)
    }

    @Test("Undo send delay persists across instances")
    @MainActor
    func undoSendDelayPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.undoSendDelay = .thirtySeconds

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.undoSendDelay == .thirtySeconds)
    }

    @Test("App lock persists across instances")
    @MainActor
    func appLockPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.appLockEnabled = true

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.appLockEnabled == true)
    }

    @Test("Onboarding complete persists across instances")
    @MainActor
    func onboardingPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.isOnboardingComplete = true

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.isOnboardingComplete == true)
    }

    @Test("Category visibility JSON persists across instances")
    @MainActor
    func categoryVisibilityPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.categoryTabVisibility[AICategory.social.rawValue] = false

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.categoryTabVisibility[AICategory.social.rawValue] == false)
        #expect(store2.categoryTabVisibility[AICategory.primary.rawValue] == true)
    }

    @Test("Notification preferences JSON persists across instances")
    @MainActor
    func notificationPreferencesPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.notificationPreferences["acc-1"] = false

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.notificationPreferences["acc-1"] == false)
    }

    @Test("Attachment cache limits JSON persists across instances")
    @MainActor
    func attachmentCacheLimitsPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.setCacheLimit(250, for: "acc-1")

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.cacheLimit(for: "acc-1") == 250)
    }

    @Test("Default sending account persists across instances")
    @MainActor
    func defaultSendingAccountPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.defaultSendingAccountId = "acc-123"

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.defaultSendingAccountId == "acc-123")
    }

    // MARK: - Helpers

    @Test("cacheLimit returns default 500 for unknown account")
    @MainActor
    func cacheLimitDefaultForUnknown() {
        let (store, _) = Self.makeStore()
        #expect(store.cacheLimit(for: "unknown") == 500)
    }

    @Test("notificationsEnabled returns true for unknown account")
    @MainActor
    func notificationsEnabledDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.notificationsEnabled(for: "unknown") == true)
    }

    @Test("colorScheme returns correct values")
    @MainActor
    func colorSchemeMapping() {
        let (store, _) = Self.makeStore()

        store.theme = .system
        #expect(store.colorScheme == nil)

        store.theme = .light
        #expect(store.colorScheme == .light)

        store.theme = .dark
        #expect(store.colorScheme == .dark)
    }

    // MARK: - Reset

    @Test("resetAll restores all defaults")
    @MainActor
    func resetAll() {
        let (store, _) = Self.makeStore()

        // Set non-default values
        store.theme = .dark
        store.undoSendDelay = .thirtySeconds
        store.appLockEnabled = true
        store.isOnboardingComplete = true
        store.defaultSendingAccountId = "acc-1"
        store.notificationPreferences["acc-1"] = false
        store.attachmentCacheLimits["acc-1"] = 100

        // Reset
        store.resetAll()

        #expect(store.theme == .system)
        #expect(store.undoSendDelay == .fiveSeconds)
        #expect(store.appLockEnabled == false)
        #expect(store.isOnboardingComplete == false)
        #expect(store.defaultSendingAccountId == nil)
        #expect(store.notificationPreferences.isEmpty)
        #expect(store.attachmentCacheLimits.isEmpty)
    }
}
