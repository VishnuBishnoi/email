import Foundation

#if canImport(UserNotifications)
import UserNotifications

/// Abstraction over `UNUserNotificationCenter` for testability.
///
/// Production code uses the real notification center; tests inject a mock
/// that records calls and returns canned responses without triggering
/// system permission dialogs or delivering actual notifications.
///
/// Spec ref: NOTIF-01
@MainActor
public protocol NotificationCenterProviding {

    // MARK: - Authorization

    /// Request the user's permission to display alerts, sounds, and badges.
    ///
    /// - Parameter options: The authorization options your app is requesting.
    /// - Returns: `true` if the user granted authorization, `false` otherwise.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool

    /// Retrieve the current notification authorization settings.
    ///
    /// - Returns: A snapshot of the app's notification settings.
    func notificationSettings() async -> UNNotificationSettings

    // MARK: - Scheduling

    /// Schedule a local notification for delivery.
    ///
    /// - Parameter request: The notification request containing content and trigger.
    func add(_ request: UNNotificationRequest) async throws

    // MARK: - Removal

    /// Remove delivered notifications from Notification Center.
    ///
    /// - Parameter identifiers: The identifiers of the notifications to remove.
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])

    /// Remove pending notification requests that have not yet been delivered.
    ///
    /// - Parameter identifiers: The identifiers of the pending requests to cancel.
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])

    // MARK: - Categories

    /// Register the notification categories and actions the app supports.
    ///
    /// - Parameter categories: The set of categories to register.
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)

    // MARK: - Badge

    /// Update the app's badge count.
    ///
    /// - Parameter count: The number to display on the app badge.
    func setBadgeCount(_ count: Int) async throws

    // MARK: - Retrieval

    /// Retrieve the list of notifications that have been delivered and remain visible.
    ///
    /// - Returns: An array of delivered notifications.
    func deliveredNotifications() async -> [UNNotification]
}
#endif
