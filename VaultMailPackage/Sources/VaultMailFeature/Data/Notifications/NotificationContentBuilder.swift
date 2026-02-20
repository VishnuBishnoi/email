#if canImport(UserNotifications)
import UserNotifications

/// Builds `UNNotificationRequest` instances from `Email` models for local delivery.
///
/// This is a caseless enum exposing only static factory methods. Each request is configured
/// with the email metadata needed for deep-linking and thread grouping in Notification Center.
///
/// - Spec refs:
///   - **NOTIF-04**: Local notification content mapping (title, subtitle, body, sound).
///   - **NOTIF-05**: Category identifier for actionable notification actions.
///   - **NOTIF-17**: `userInfo` payload carries `emailId`, `threadId`, `accountId`, and
///     `fromAddress` so the app can navigate to the correct thread on tap.
public enum NotificationContentBuilder {

    /// Creates a notification request for immediate delivery of a new-email notification.
    ///
    /// - Parameter email: The `Email` model to build the notification from.
    /// - Returns: A `UNNotificationRequest` with `nil` trigger (immediate delivery).
    public static func build(from email: Email) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()

        // NOTIF-04: Content fields
        content.title = email.fromName ?? email.fromAddress
        content.subtitle = email.subject
        content.body = String(email.snippet?.prefix(100) ?? "")
        content.sound = .default

        // NOTIF-05: Category for actionable notifications (mark-read, archive, etc.)
        content.categoryIdentifier = AppConstants.notificationCategoryEmail

        // Group by thread so Notification Center stacks related messages
        content.threadIdentifier = email.threadId

        // Active interruption level — shows on Lock Screen and banners
        content.interruptionLevel = .active

        // NOTIF-17: Deep-link payload for tap handling
        content.userInfo = [
            "emailId": email.id,
            "threadId": email.threadId,
            "accountId": email.accountId,
            "fromAddress": email.fromAddress,
        ]

        // Identifier scoped to the email's stable SHA256 ID to prevent duplicates
        let identifier = "email-\(email.id)"

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // immediate delivery
        )
    }
}

#else

/// Stub for platforms where UserNotifications is unavailable.
public enum NotificationContentBuilder {}

#endif
