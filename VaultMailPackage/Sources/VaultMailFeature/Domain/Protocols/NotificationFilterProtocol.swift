import Foundation

/// Protocol for composable notification filters.
/// Each filter independently decides whether an email should trigger a notification.
/// Spec ref: NOTIF-07
@MainActor
public protocol NotificationFilter {
    /// Returns `true` if the email should trigger a notification, `false` to suppress.
    func shouldNotify(for email: Email) async -> Bool
}
