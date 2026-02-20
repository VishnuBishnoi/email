import Foundation

/// Service protocol for local notification management.
///
/// Isolated to `@MainActor` because notification state (badge count,
/// authorization status) drives UI updates and must be read/written
/// on the main actor.
///
/// Implementations live in the Data layer. The Domain layer depends only
/// on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: NOTIF-01
@MainActor
public protocol NotificationServiceProtocol {
    // MARK: - Authorization

    /// Request notification authorization from the user.
    ///
    /// Returns `true` if the user granted permission, `false` otherwise.
    /// Safe to call multiple times; the OS will only show the prompt once.
    ///
    /// Spec ref: NOTIF-02
    func requestAuthorization() async -> Bool

    /// Query the current notification authorization status.
    ///
    /// Maps the platform authorization state to `NotificationAuthStatus`
    /// for use in domain logic and settings UI.
    ///
    /// Spec ref: NOTIF-02
    func authorizationStatus() async -> NotificationAuthStatus

    // MARK: - Notification Delivery

    /// Process newly fetched emails and schedule local notifications.
    ///
    /// Filters emails to determine which should trigger notifications
    /// based on read status, send date recency, and the filter pipeline.
    ///
    /// - Parameters:
    ///   - emails: Newly synced emails to evaluate for notification.
    ///   - fromBackground: Whether the sync originated from a background fetch.
    ///
    /// Spec ref: NOTIF-03, NOTIF-04
    func processNewEmails(_ emails: [Email], fromBackground: Bool) async

    // MARK: - Notification Removal

    /// Remove delivered notifications for specific email IDs.
    ///
    /// Called when emails are read, archived, or deleted so that
    /// stale notifications do not remain in Notification Center.
    ///
    /// - Parameter emailIds: The stable IDs of emails whose notifications
    ///   should be removed.
    ///
    /// Spec ref: NOTIF-05
    func removeNotifications(forEmailIds emailIds: [String]) async

    /// Remove delivered notifications for all emails in a thread.
    ///
    /// Called when a thread is opened, archived, or deleted to clear
    /// all associated notifications at once.
    ///
    /// - Parameter threadId: The thread ID whose notifications should be removed.
    ///
    /// Spec ref: NOTIF-05
    func removeNotifications(forThreadId threadId: String) async

    // MARK: - Badge Management

    /// Update the app badge count to reflect total unread emails.
    ///
    /// Reads the current unread count from the repository and sets
    /// the badge accordingly. Call after any operation that changes
    /// read status (sync, mark-read, archive, delete).
    ///
    /// Spec ref: NOTIF-06
    func updateBadgeCount() async

    // MARK: - Configuration

    /// Register notification categories and actions.
    ///
    /// Defines interactive notification actions (e.g., mark-as-read,
    /// archive, reply) that appear on long-press or notification
    /// expansion. Should be called once during app launch.
    ///
    /// Spec ref: NOTIF-07
    func registerCategories()

    /// Record that the first app launch has completed.
    ///
    /// Used to suppress notifications during the initial sync so
    /// the user is not flooded with alerts for pre-existing emails.
    ///
    /// Spec ref: NOTIF-08
    func markFirstLaunchComplete()

    // MARK: - Debug

    #if DEBUG
    /// Send a single test notification bypassing first-launch and recency guards.
    ///
    /// Still runs the filter pipeline so settings are respected.
    func sendDebugNotification(from email: Email) async

    /// Run the filter pipeline diagnostics and return a human-readable result.
    func diagnoseFilter(for email: Email) async -> String
    #endif
}
