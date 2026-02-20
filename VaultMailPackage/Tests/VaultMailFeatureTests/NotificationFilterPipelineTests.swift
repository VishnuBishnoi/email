import Foundation
import Testing
@testable import VaultMailFeature

@Suite("NotificationFilterPipeline")
struct NotificationFilterPipelineTests {
    // MARK: - Helpers

    @MainActor
    private static func makeSettingsStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return SettingsStore(defaults: defaults)
    }

    @MainActor
    private static func makeEmail(
        fromAddress: String = "user@test.com",
        threadId: String = "t1",
        subject: String = "Test Subject"
    ) -> Email {
        Email(
            accountId: "acc1",
            threadId: threadId,
            messageId: "msg1",
            fromAddress: fromAddress,
            subject: subject
        )
    }

    // MARK: - Mock Filter

    @MainActor
    private final class MockFilter: NotificationFilter {
        var result: Bool
        var callCount = 0

        init(result: Bool) {
            self.result = result
        }

        func shouldNotify(for email: Email) async -> Bool {
            callCount += 1
            return result
        }
    }

    // MARK: - Tests

    @Test("VIP override bypasses all filters")
    @MainActor
    func vipOverrideBypassesAllFilters() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "vip@example.com")

        // Add sender to VIP contacts
        settingsStore.addVIPContact("vip@example.com")

        // Create a rejecting filter
        let rejectingFilter = MockFilter(result: false)

        // Create VIP filter and pipeline
        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [rejectingFilter])

        // Should return true (VIP override) and NOT call the rejecting filter
        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == true)
        #expect(rejectingFilter.callCount == 0)
    }

    @Test("All filters pass → true")
    @MainActor
    func allFiltersPassReturnsTrue() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        // Create two passing filters
        let filter1 = MockFilter(result: true)
        let filter2 = MockFilter(result: true)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [filter1, filter2])

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == true)
        #expect(filter1.callCount == 1)
        #expect(filter2.callCount == 1)
    }

    @Test("One filter rejects → false with early termination")
    @MainActor
    func oneFilterRejectsWithEarlyTermination() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        // Create [passing, rejecting, passing] filter chain
        let passingFilter1 = MockFilter(result: true)
        let rejectingFilter = MockFilter(result: false)
        let passingFilter2 = MockFilter(result: true)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(
            vipFilter: vipFilter,
            filters: [passingFilter1, rejectingFilter, passingFilter2]
        )

        let shouldNotify = await pipeline.shouldNotify(for: email)

        // Should return false, first filter called, rejecting filter called, third should NOT be called
        #expect(shouldNotify == false)
        #expect(passingFilter1.callCount == 1)
        #expect(rejectingFilter.callCount == 1)
        #expect(passingFilter2.callCount == 0)
    }

    @Test("Empty filter list → true")
    @MainActor
    func emptyFilterListReturnsTrue() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [])

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == true)
    }

    @Test("Non-VIP with all rejecting → false")
    @MainActor
    func nonVipWithRejectingFilterReturnsFalse() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        let rejectingFilter = MockFilter(result: false)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [rejectingFilter])

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == false)
        #expect(rejectingFilter.callCount == 1)
    }

    @Test("VIP case-insensitive matching")
    @MainActor
    func vipCaseInsensitiveMatching() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "VIP@EXAMPLE.COM")

        // Add VIP contact with different case
        settingsStore.addVIPContact("vip@example.com")

        let rejectingFilter = MockFilter(result: false)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [rejectingFilter])

        let shouldNotify = await pipeline.shouldNotify(for: email)

        // Should match despite case difference and bypass rejecting filter
        #expect(shouldNotify == true)
        #expect(rejectingFilter.callCount == 0)
    }

    @Test("Multiple filters in sequence")
    @MainActor
    func multipleFiltersSequence() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        let filter1 = MockFilter(result: true)
        let filter2 = MockFilter(result: true)
        let filter3 = MockFilter(result: true)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(
            vipFilter: vipFilter,
            filters: [filter1, filter2, filter3]
        )

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == true)
        #expect(filter1.callCount == 1)
        #expect(filter2.callCount == 1)
        #expect(filter3.callCount == 1)
    }

    @Test("First filter rejects immediately")
    @MainActor
    func firstFilterRejectsImmediately() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        let rejectingFilter = MockFilter(result: false)
        let passingFilter = MockFilter(result: true)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(
            vipFilter: vipFilter,
            filters: [rejectingFilter, passingFilter]
        )

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == false)
        #expect(rejectingFilter.callCount == 1)
        #expect(passingFilter.callCount == 0)
    }

    @Test("Non-VIP with all passing filters")
    @MainActor
    func nonVipWithAllPassingFilters() async {
        let settingsStore = Self.makeSettingsStore()
        let email = Self.makeEmail(fromAddress: "user@example.com")

        let filter1 = MockFilter(result: true)
        let filter2 = MockFilter(result: true)

        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [filter1, filter2])

        let shouldNotify = await pipeline.shouldNotify(for: email)

        #expect(shouldNotify == true)
        #expect(filter1.callCount == 1)
        #expect(filter2.callCount == 1)
    }
}
