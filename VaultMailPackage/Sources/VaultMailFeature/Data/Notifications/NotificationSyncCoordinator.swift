import Foundation

/// Coordinates notification events between the sync engine and notification service.
///
/// Thin orchestration layer. All business logic lives in NotificationService;
/// this type simply routes sync events to the appropriate service methods.
///
/// Spec ref: NOTIF-03, NOTIF-05
@Observable
@MainActor
public final class NotificationSyncCoordinator {

    /// Thread ID to navigate to when the user taps a notification. Set by the response handler.
    public var pendingThreadNavigation: String?

    private let notificationService: any NotificationServiceProtocol

    public init(notificationService: any NotificationServiceProtocol) {
        self.notificationService = notificationService
    }

    /// Called after a sync completes with newly fetched emails.
    public func didSyncNewEmails(_ emails: [Email] = [], fromBackground: Bool, activeFolderType: String?) async {
        await notificationService.processNewEmails(emails, fromBackground: fromBackground, activeFolderType: activeFolderType)
    }

    /// Called when a thread is marked as read.
    public func didMarkThreadRead(threadId: String) async {
        await notificationService.removeNotifications(forThreadId: threadId)
    }

    /// Called when a thread is removed (archived/deleted).
    public func didRemoveThread(threadId: String) async {
        await notificationService.removeNotifications(forThreadId: threadId)
    }

    /// Called after first sync completes to enable future notifications.
    public func markFirstLaunchComplete() {
        notificationService.markFirstLaunchComplete()
    }

    // MARK: - Debug

    #if DEBUG
    /// Send a test notification directly, bypassing first-launch and recency guards.
    public func sendDebugNotification(from email: Email) async {
        await notificationService.sendDebugNotification(from: email)
    }

    /// Run filter pipeline diagnostics for a test email.
    public func diagnoseFilter(for email: Email) async -> String {
        await notificationService.diagnoseFilter(for: email)
    }
    #endif
}
