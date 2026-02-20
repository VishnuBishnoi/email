import Foundation
import Testing
@testable import VaultMailFeature

#if canImport(UserNotifications)
import UserNotifications

@Suite("NotificationService")
struct NotificationServiceTests {
    @MainActor
    private static func makeService(
        authGranted: Bool = true,
        emails: [Email] = []
    ) -> (NotificationService, MockNotificationCenter, MockEmailRepository, SettingsStore) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settingsStore = SettingsStore(defaults: defaults)
        let center = MockNotificationCenter()
        center.authorizationGranted = authGranted
        let repo = MockEmailRepository()
        repo.emails = emails
        let vipFilter = VIPContactFilter(settingsStore: settingsStore)
        let pipeline = NotificationFilterPipeline(vipFilter: vipFilter, filters: [])
        let service = NotificationService(
            center: center,
            settingsStore: settingsStore,
            emailRepository: repo,
            filterPipeline: pipeline
        )
        return (service, center, repo, settingsStore)
    }

    @MainActor
    private static func makeEmail(
        id: String = UUID().uuidString,
        accountId: String = "acc1",
        threadId: String = "t1",
        fromAddress: String = "sender@test.com",
        subject: String = "Test",
        dateReceived: Date = Date(),
        isRead: Bool = false
    ) -> Email {
        Email(
            id: id,
            accountId: accountId,
            threadId: threadId,
            messageId: "msg-\(id)",
            fromAddress: fromAddress,
            subject: subject,
            dateReceived: dateReceived,
            isRead: isRead
        )
    }

    // MARK: - First Launch Behavior

    @Test("First launch suppresses notifications")
    @MainActor
    func firstLaunchSuppressesNotifications() async {
        let (service, center, _, _) = Self.makeService()
        let email = Self.makeEmail(dateReceived: Date())

        await service.processNewEmails([email], fromBackground: false)

        #expect(center.addedRequests.isEmpty)
    }

    @Test("After markFirstLaunchComplete, notifications are delivered")
    @MainActor
    func afterMarkFirstLaunchCompleteNotificationsDelivered() async {
        let (service, center, _, _) = Self.makeService()
        let email = Self.makeEmail(dateReceived: Date())

        service.markFirstLaunchComplete()
        await service.processNewEmails([email], fromBackground: false)

        #expect(center.addedRequests.count == 1)
    }

    // MARK: - Email Filtering

    @Test("Read emails are skipped")
    @MainActor
    func readEmailsAreSkipped() async {
        let (service, center, _, _) = Self.makeService()
        let email = Self.makeEmail(dateReceived: Date(), isRead: true)

        service.markFirstLaunchComplete()
        await service.processNewEmails([email], fromBackground: false)

        #expect(center.addedRequests.isEmpty)
    }

    @Test("Dedup skips already-delivered emails")
    @MainActor
    func dedupSkipsAlreadyDeliveredEmails() async {
        let (service, center, _, _) = Self.makeService()
        let email = Self.makeEmail(id: "email1", dateReceived: Date())

        service.markFirstLaunchComplete()

        // Process first time
        await service.processNewEmails([email], fromBackground: false)
        #expect(center.addedRequests.count == 1)

        // Process second time - should be skipped
        await service.processNewEmails([email], fromBackground: false)
        #expect(center.addedRequests.count == 1)
    }

    // MARK: - Batch Limits

    @Test("Batch limit capped at maxNotificationsPerSync")
    @MainActor
    func batchLimitCappedAtMaxNotificationsPerSync() async {
        let (service, center, _, _) = Self.makeService()

        // Create 15 emails
        let emails = (0..<15).map { index in
            Self.makeEmail(
                id: "email\(index)",
                dateReceived: Date()
            )
        }

        service.markFirstLaunchComplete()
        await service.processNewEmails(emails, fromBackground: false)

        #expect(center.addedRequests.count == AppConstants.maxNotificationsPerSync)
    }

    // MARK: - Recency Filtering

    @Test("Old emails suppressed by recency in foreground")
    @MainActor
    func oldEmailsSuppressedByRecencyInForeground() async {
        let (service, center, _, _) = Self.makeService()

        // Create email 2 hours ago (older than foreground threshold of 300 seconds)
        let oldEmail = Self.makeEmail(
            dateReceived: Date().addingTimeInterval(-7200)
        )

        service.markFirstLaunchComplete()
        await service.processNewEmails([oldEmail], fromBackground: false)

        #expect(center.addedRequests.isEmpty)
    }

    @Test("Recent emails delivered in foreground")
    @MainActor
    func recentEmailsDeliveredInForeground() async {
        let (service, center, _, _) = Self.makeService()

        // Create email 30 seconds ago (within foreground threshold of 120 seconds)
        let recentEmail = Self.makeEmail(
            dateReceived: Date().addingTimeInterval(-30)
        )

        service.markFirstLaunchComplete()
        await service.processNewEmails([recentEmail], fromBackground: false)

        #expect(center.addedRequests.count == 1)
    }

    @Test("Old emails delivered in background within threshold")
    @MainActor
    func oldEmailsDeliveredInBackgroundWithinThreshold() async {
        let (service, center, _, _) = Self.makeService()

        // Create email 5 minutes ago (within background threshold of 900 seconds)
        let email = Self.makeEmail(
            dateReceived: Date().addingTimeInterval(-300)
        )

        service.markFirstLaunchComplete()
        await service.processNewEmails([email], fromBackground: true)

        #expect(center.addedRequests.count == 1)
    }

    // MARK: - Badge Count

    @Test("Badge count updates after processNewEmails")
    @MainActor
    func badgeCountUpdatesAfterProcessNewEmails() async {
        let emails = (0..<3).map { index in
            Self.makeEmail(id: "email\(index)", isRead: false)
        }
        let (service, center, repo, _) = Self.makeService(emails: emails)

        // Configure repo to return 3 unread emails
        repo.emails = emails

        let newEmail = Self.makeEmail(id: "new", dateReceived: Date())

        service.markFirstLaunchComplete()
        await service.processNewEmails([newEmail], fromBackground: false)

        #expect(center.currentBadgeCount == 3)
    }

    // MARK: - Notification Removal

    @Test("removeNotifications by email IDs")
    @MainActor
    func removeNotificationsByEmailIds() async {
        let (service, center, _, _) = Self.makeService()
        let email = Self.makeEmail(id: "email123", dateReceived: Date())

        service.markFirstLaunchComplete()
        await service.processNewEmails([email], fromBackground: false)

        #expect(center.addedRequests.count == 1)

        await service.removeNotifications(forEmailIds: ["email123"])

        #expect(center.removedDeliveredIdentifiers.contains("email-email123"))
    }

    // MARK: - Category Registration

    @Test("registerCategories sets categories")
    @MainActor
    func registerCategoriesSetsCategories() async {
        let (service, center, _, _) = Self.makeService()

        await service.registerCategories()

        #expect(!center.registeredCategories.isEmpty)
    }

    // MARK: - Authorization

    @Test("requestAuthorization returns true when granted")
    @MainActor
    func requestAuthorizationReturnsTrueWhenGranted() async throws {
        let (service, center, _, _) = Self.makeService(authGranted: true)

        let granted = try await service.requestAuthorization()

        #expect(granted == true)
    }

    @Test("requestAuthorization returns false when denied")
    @MainActor
    func requestAuthorizationReturnsFalseWhenDenied() async throws {
        let (service, center, _, _) = Self.makeService(authGranted: false)

        let granted = try await service.requestAuthorization()

        #expect(granted == false)
    }
}

#endif
