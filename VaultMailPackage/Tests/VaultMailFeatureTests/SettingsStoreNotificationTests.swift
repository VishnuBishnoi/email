import Foundation
import Testing
@testable import VaultMailFeature

@Suite("SettingsStore Notifications")
struct SettingsStoreNotificationTests {

    /// Creates a SettingsStore backed by a unique, ephemeral UserDefaults suite.
    @MainActor
    private static func makeStore() -> (SettingsStore, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        return (store, defaults)
    }

    // MARK: - VIP Contacts: Defaults & Behavior

    @Test("VIP contacts default to empty set")
    @MainActor
    func vipContactsDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.vipContacts.isEmpty)
    }

    @Test("Add VIP contact and contains returns true")
    @MainActor
    func addVIPContact() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("John.Doe@example.com")
        #expect(store.vipContacts.contains("john.doe@example.com"))
    }

    @Test("VIP contact is lowercased on add")
    @MainActor
    func vipContactLowercased() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("ALICE@EXAMPLE.COM")
        #expect(store.vipContacts.contains("alice@example.com"))
        #expect(!store.vipContacts.contains("ALICE@EXAMPLE.COM"))
    }

    @Test("Adding duplicate VIP contact results in single entry")
    @MainActor
    func addDuplicateVIPContact() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("test@example.com")
        store.addVIPContact("Test@Example.Com")
        #expect(store.vipContacts.count == 1)
        #expect(store.vipContacts.contains("test@example.com"))
    }

    @Test("Remove VIP contact succeeds")
    @MainActor
    func removeVIPContact() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("contact@example.com")
        #expect(store.vipContacts.contains("contact@example.com"))

        store.removeVIPContact("contact@example.com")
        #expect(!store.vipContacts.contains("contact@example.com"))
        #expect(store.vipContacts.isEmpty)
    }

    @Test("Remove VIP contact with mixed case works")
    @MainActor
    func removeVIPContactMixedCase() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("alice@example.com")
        store.removeVIPContact("ALICE@EXAMPLE.COM")
        #expect(!store.vipContacts.contains("alice@example.com"))
    }

    @Test("Multiple VIP contacts can coexist")
    @MainActor
    func multipleVIPContacts() {
        let (store, _) = Self.makeStore()
        store.addVIPContact("alice@example.com")
        store.addVIPContact("bob@example.com")
        store.addVIPContact("charlie@example.com")

        #expect(store.vipContacts.count == 3)
        #expect(store.vipContacts.contains("alice@example.com"))
        #expect(store.vipContacts.contains("bob@example.com"))
        #expect(store.vipContacts.contains("charlie@example.com"))
    }

    // MARK: - Muted Threads: Defaults & Toggle Behavior

    @Test("Muted thread IDs default to empty set")
    @MainActor
    func mutedThreadsDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.mutedThreadIds.isEmpty)
    }

    @Test("Toggle mute thread adds thread to muted set")
    @MainActor
    func toggleMuteThreadAdds() {
        let (store, _) = Self.makeStore()
        store.toggleMuteThread(threadId: "thread-123")
        #expect(store.mutedThreadIds.contains("thread-123"))
    }

    @Test("Toggle mute thread twice removes thread from muted set")
    @MainActor
    func toggleMuteThreadTwice() {
        let (store, _) = Self.makeStore()
        store.toggleMuteThread(threadId: "thread-456")
        #expect(store.mutedThreadIds.contains("thread-456"))

        store.toggleMuteThread(threadId: "thread-456")
        #expect(!store.mutedThreadIds.contains("thread-456"))
    }

    @Test("Toggle mute thread is idempotent")
    @MainActor
    func toggleMuteThreadIdempotent() {
        let (store, _) = Self.makeStore()

        store.toggleMuteThread(threadId: "thread-789")
        let firstToggleState = store.mutedThreadIds.contains("thread-789")

        store.toggleMuteThread(threadId: "thread-789")
        store.toggleMuteThread(threadId: "thread-789")
        let afterTwoToggesState = store.mutedThreadIds.contains("thread-789")

        #expect(firstToggleState == afterTwoToggesState)
    }

    @Test("Multiple threads can be muted independently")
    @MainActor
    func multipleMutedThreads() {
        let (store, _) = Self.makeStore()

        store.toggleMuteThread(threadId: "t1")
        store.toggleMuteThread(threadId: "t2")
        store.toggleMuteThread(threadId: "t3")

        #expect(store.mutedThreadIds.count == 3)
        #expect(store.mutedThreadIds.contains("t1"))
        #expect(store.mutedThreadIds.contains("t2"))
        #expect(store.mutedThreadIds.contains("t3"))
    }

    @Test("Unmuting one thread preserves others")
    @MainActor
    func unmuteSingleThreadPreservesOthers() {
        let (store, _) = Self.makeStore()

        store.toggleMuteThread(threadId: "t1")
        store.toggleMuteThread(threadId: "t2")
        store.toggleMuteThread(threadId: "t3")

        store.toggleMuteThread(threadId: "t2")

        #expect(store.mutedThreadIds.count == 2)
        #expect(store.mutedThreadIds.contains("t1"))
        #expect(!store.mutedThreadIds.contains("t2"))
        #expect(store.mutedThreadIds.contains("t3"))
    }

    // MARK: - Quiet Hours: Defaults & Configuration

    @Test("Quiet hours enabled defaults to false")
    @MainActor
    func quietHoursEnabledDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.quietHoursEnabled == false)
    }

    @Test("Quiet hours start defaults to 1320 (22:00)")
    @MainActor
    func quietHoursStartDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.quietHoursStart == 1320)
    }

    @Test("Quiet hours end defaults to 420 (07:00)")
    @MainActor
    func quietHoursEndDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.quietHoursEnd == 420)
    }

    @Test("Can enable quiet hours")
    @MainActor
    func enableQuietHours() {
        let (store, _) = Self.makeStore()
        store.quietHoursEnabled = true
        #expect(store.quietHoursEnabled == true)
    }

    @Test("Can set quiet hours start time")
    @MainActor
    func setQuietHoursStart() {
        let (store, _) = Self.makeStore()
        store.quietHoursStart = 600 // 10:00
        #expect(store.quietHoursStart == 600)
    }

    @Test("Can set quiet hours end time")
    @MainActor
    func setQuietHoursEnd() {
        let (store, _) = Self.makeStore()
        store.quietHoursEnd = 900 // 15:00
        #expect(store.quietHoursEnd == 900)
    }

    @Test("Can configure full quiet hours independently")
    @MainActor
    func configureQuietHoursFully() {
        let (store, _) = Self.makeStore()

        store.quietHoursEnabled = true
        store.quietHoursStart = 540 // 09:00
        store.quietHoursEnd = 1020 // 17:00

        #expect(store.quietHoursEnabled == true)
        #expect(store.quietHoursStart == 540)
        #expect(store.quietHoursEnd == 1020)
    }

    // MARK: - Notification Category Preferences

    @Test("Notification category preferences default to empty")
    @MainActor
    func notificationCategoryPreferencesDefault() {
        let (store, _) = Self.makeStore()
        #expect(store.notificationCategoryPreferences.isEmpty)
    }

    @Test("notificationCategoryEnabled returns true for absent key")
    @MainActor
    func notificationCategoryEnabledAbsentKey() {
        let (store, _) = Self.makeStore()
        #expect(store.notificationCategoryEnabled(for: "primary") == true)
        #expect(store.notificationCategoryEnabled(for: "social") == true)
        #expect(store.notificationCategoryEnabled(for: "unknown") == true)
    }

    @Test("Setting category preference to false returns false")
    @MainActor
    func notificationCategoryDisabled() {
        let (store, _) = Self.makeStore()
        store.notificationCategoryPreferences["social"] = false
        #expect(store.notificationCategoryEnabled(for: "social") == false)
    }

    @Test("Can set multiple category preferences independently")
    @MainActor
    func multipleNotificationCategoryPreferences() {
        let (store, _) = Self.makeStore()

        store.notificationCategoryPreferences["primary"] = false
        store.notificationCategoryPreferences["social"] = true
        store.notificationCategoryPreferences["promotions"] = false

        #expect(store.notificationCategoryEnabled(for: "primary") == false)
        #expect(store.notificationCategoryEnabled(for: "social") == true)
        #expect(store.notificationCategoryEnabled(for: "promotions") == false)
        #expect(store.notificationCategoryEnabled(for: "updates") == true) // absent = true
    }

    @Test("Setting category preference to true returns true")
    @MainActor
    func notificationCategoryExplicitlyEnabled() {
        let (store, _) = Self.makeStore()
        store.notificationCategoryPreferences["custom"] = true
        #expect(store.notificationCategoryEnabled(for: "custom") == true)
    }

    // MARK: - Persistence: VIP Contacts

    @Test("VIP contacts persist across instances")
    @MainActor
    func vipContactsPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.addVIPContact("alice@example.com")
        store1.addVIPContact("bob@example.com")

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.vipContacts.contains("alice@example.com"))
        #expect(store2.vipContacts.contains("bob@example.com"))
        #expect(store2.vipContacts.count == 2)
    }

    @Test("VIP contacts persist as empty set")
    @MainActor
    func vipContactsEmptyPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.addVIPContact("temp@example.com")
        store1.removeVIPContact("temp@example.com")

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.vipContacts.isEmpty)
    }

    // MARK: - Persistence: Muted Threads

    @Test("Muted threads persist across instances")
    @MainActor
    func mutedThreadsPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.toggleMuteThread(threadId: "thread-1")
        store1.toggleMuteThread(threadId: "thread-2")
        store1.toggleMuteThread(threadId: "thread-3")

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.mutedThreadIds.contains("thread-1"))
        #expect(store2.mutedThreadIds.contains("thread-2"))
        #expect(store2.mutedThreadIds.contains("thread-3"))
        #expect(store2.mutedThreadIds.count == 3)
    }

    @Test("Muted threads persist as empty set")
    @MainActor
    func mutedThreadsEmptyPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.toggleMuteThread(threadId: "temp-thread")
        store1.toggleMuteThread(threadId: "temp-thread")

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.mutedThreadIds.isEmpty)
    }

    // MARK: - Persistence: Quiet Hours

    @Test("Quiet hours enabled persists across instances")
    @MainActor
    func quietHoursEnabledPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.quietHoursEnabled = true

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.quietHoursEnabled == true)
    }

    @Test("Quiet hours start time persists across instances")
    @MainActor
    func quietHoursStartPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.quietHoursStart = 660 // 11:00

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.quietHoursStart == 660)
    }

    @Test("Quiet hours end time persists across instances")
    @MainActor
    func quietHoursEndPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.quietHoursEnd = 480 // 08:00

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.quietHoursEnd == 480)
    }

    @Test("Full quiet hours configuration persists")
    @MainActor
    func fullQuietHoursPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.quietHoursEnabled = true
        store1.quietHoursStart = 1200 // 20:00
        store1.quietHoursEnd = 360 // 06:00

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.quietHoursEnabled == true)
        #expect(store2.quietHoursStart == 1200)
        #expect(store2.quietHoursEnd == 360)
    }

    // MARK: - Persistence: Notification Category Preferences

    @Test("Notification category preferences persist across instances")
    @MainActor
    func notificationCategoryPreferencesPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.notificationCategoryPreferences["primary"] = false
        store1.notificationCategoryPreferences["social"] = false
        store1.notificationCategoryPreferences["promotions"] = true

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.notificationCategoryEnabled(for: "primary") == false)
        #expect(store2.notificationCategoryEnabled(for: "social") == false)
        #expect(store2.notificationCategoryEnabled(for: "promotions") == true)
    }

    // MARK: - Combined Persistence: All Notification Settings

    @Test("All notification settings persist together")
    @MainActor
    func allNotificationSettingsPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.addVIPContact("vip@example.com")
        store1.toggleMuteThread(threadId: "muted-1")
        store1.quietHoursEnabled = true
        store1.quietHoursStart = 1380 // 23:00
        store1.quietHoursEnd = 360 // 06:00
        store1.notificationCategoryPreferences["social"] = false

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.vipContacts.contains("vip@example.com"))
        #expect(store2.mutedThreadIds.contains("muted-1"))
        #expect(store2.quietHoursEnabled == true)
        #expect(store2.quietHoursStart == 1380)
        #expect(store2.quietHoursEnd == 360)
        #expect(store2.notificationCategoryEnabled(for: "social") == false)
    }

    // MARK: - Reset All

    @Test("resetAll clears VIP contacts")
    @MainActor
    func resetAllClearsVIPContacts() {
        let (store, _) = Self.makeStore()

        store.addVIPContact("alice@example.com")
        store.addVIPContact("bob@example.com")
        store.resetAll()

        #expect(store.vipContacts.isEmpty)
    }

    @Test("resetAll clears muted threads")
    @MainActor
    func resetAllClearsMutedThreads() {
        let (store, _) = Self.makeStore()

        store.toggleMuteThread(threadId: "t1")
        store.toggleMuteThread(threadId: "t2")
        store.resetAll()

        #expect(store.mutedThreadIds.isEmpty)
    }

    @Test("resetAll restores quiet hours defaults")
    @MainActor
    func resetAllRestoresQuietHoursDefaults() {
        let (store, _) = Self.makeStore()

        store.quietHoursEnabled = true
        store.quietHoursStart = 600
        store.quietHoursEnd = 900

        store.resetAll()

        #expect(store.quietHoursEnabled == false)
        #expect(store.quietHoursStart == 1320)
        #expect(store.quietHoursEnd == 420)
    }

    @Test("resetAll clears notification category preferences")
    @MainActor
    func resetAllClearsNotificationCategoryPreferences() {
        let (store, _) = Self.makeStore()

        store.notificationCategoryPreferences["primary"] = false
        store.notificationCategoryPreferences["social"] = false
        store.notificationCategoryPreferences["promotions"] = true

        store.resetAll()

        #expect(store.notificationCategoryPreferences.isEmpty)
        #expect(store.notificationCategoryEnabled(for: "primary") == true)
    }

    @Test("resetAll resets all notification settings together")
    @MainActor
    func resetAllNotificationSettings() {
        let (store, _) = Self.makeStore()

        // Set all notification-related fields
        store.addVIPContact("vip@example.com")
        store.toggleMuteThread(threadId: "thread-1")
        store.quietHoursEnabled = true
        store.quietHoursStart = 600
        store.quietHoursEnd = 900
        store.notificationCategoryPreferences["social"] = false

        // Also set non-notification fields to verify selectivity
        store.theme = .dark
        store.appLockEnabled = true
        store.isOnboardingComplete = true

        store.resetAll()

        // Verify notification settings reset
        #expect(store.vipContacts.isEmpty)
        #expect(store.mutedThreadIds.isEmpty)
        #expect(store.quietHoursEnabled == false)
        #expect(store.quietHoursStart == 1320)
        #expect(store.quietHoursEnd == 420)
        #expect(store.notificationCategoryPreferences.isEmpty)

        // Verify non-notification settings also reset
        #expect(store.theme == .system)
        #expect(store.appLockEnabled == false)
        #expect(store.isOnboardingComplete == false)
    }
}
