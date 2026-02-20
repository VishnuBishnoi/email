import Foundation

#if canImport(UserNotifications)
import UserNotifications

/// Production wrapper around UNUserNotificationCenter conforming to NotificationCenterProviding.
/// Delegates all notification operations to the system notification center.
/// - Tag: NOTIF-01
@MainActor
public final class UNUserNotificationCenterWrapper: NotificationCenterProviding {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func notificationSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    public func setBadgeCount(_ count: Int) async throws {
        try await center.setBadgeCount(count)
    }

    public func deliveredNotifications() async -> [UNNotification] {
        await center.deliveredNotifications()
    }
}
#endif
