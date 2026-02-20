#if canImport(UserNotifications)
import UserNotifications
import VaultMailFeature
import Testing

@MainActor
final class MockNotificationCenter: NotificationCenterProviding {
    // MARK: - Recording Properties

    var addedRequests: [UNNotificationRequest] = []
    var removedDeliveredIdentifiers: [String] = []
    var removedPendingIdentifiers: [String] = []
    var registeredCategories: Set<UNNotificationCategory> = []
    var currentBadgeCount: Int = 0

    // MARK: - Configurable Behavior

    var authorizationGranted: Bool = true
    var shouldThrowOnAdd: Bool = false

    // MARK: - Protocol Methods

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationGranted
    }

    func notificationSettings() async -> UNNotificationSettings {
        // UNNotificationSettings cannot be directly instantiated.
        // Return the current notification center's settings as a fallback.
        await UNUserNotificationCenter.current().notificationSettings()
    }

    func add(_ request: UNNotificationRequest) throws {
        if shouldThrowOnAdd {
            throw MockError.addFailed
        }
        addedRequests.append(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }

    func setBadgeCount(_ count: Int) {
        currentBadgeCount = count
    }

    func deliveredNotifications() async -> [UNNotification] {
        []
    }

    // MARK: - Error Type

    enum MockError: Error {
        case addFailed
    }
}
#endif
