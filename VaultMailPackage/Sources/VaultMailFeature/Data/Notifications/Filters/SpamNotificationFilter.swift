import Foundation

/// Filter that suppresses notifications for spam emails.
/// Spec ref: NOTIF-07
@MainActor
public final class SpamNotificationFilter: NotificationFilter {
    public init() {}

    public func shouldNotify(for email: Email) async -> Bool {
        !email.isSpam
    }
}
