#if canImport(UserNotifications)
import UserNotifications
import Foundation

/// Core notification service implementation.
/// Spec refs: NOTIF-01 through NOTIF-08
@Observable
@MainActor
public final class NotificationService: NotificationServiceProtocol {
    // Dependencies
    private let center: any NotificationCenterProviding
    private let settingsStore: SettingsStore
    private let emailRepository: any EmailRepositoryProtocol
    private let filterPipeline: NotificationFilterPipeline

    // Internal state
    private var isFirstLaunch = true
    private var deliveredNotificationIds: Set<String> = []
    private let maxDeliveredIdsCacheSize = 10_000

    public init(
        center: any NotificationCenterProviding,
        settingsStore: SettingsStore,
        emailRepository: any EmailRepositoryProtocol,
        filterPipeline: NotificationFilterPipeline
    ) {
        self.center = center
        self.settingsStore = settingsStore
        self.emailRepository = emailRepository
        self.filterPipeline = filterPipeline
    }

    // MARK: - Authorization (NOTIF-02)

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    public func authorizationStatus() async -> NotificationAuthStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        @unknown default: return .denied
        }
    }

    // MARK: - Notification Delivery (NOTIF-03, NOTIF-04)

    public func processNewEmails(_ emails: [Email], fromBackground: Bool) async {
        // Suppress during first launch (NOTIF-08)
        guard !isFirstLaunch else { return }

        // Recency threshold
        let recencySeconds = fromBackground
            ? AppConstants.backgroundNotificationRecencySeconds
            : AppConstants.foregroundNotificationRecencySeconds
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(recencySeconds))

        var deliveredCount = 0

        for email in emails {
            // Batch limit (NOTIF-19)
            guard deliveredCount < AppConstants.maxNotificationsPerSync else { break }

            // Skip read emails
            guard !email.isRead else { continue }

            // Dedup: skip if already delivered
            let notificationId = "email-\(email.id)"
            guard !deliveredNotificationIds.contains(notificationId) else { continue }

            // Recency: skip old emails
            let emailDate = email.dateReceived ?? email.dateSent ?? .distantPast
            guard emailDate > cutoffDate else { continue }

            // Run filter pipeline
            guard await filterPipeline.shouldNotify(for: email) else { continue }

            // Build and deliver notification
            let request = NotificationContentBuilder.build(from: email)
            do {
                try await center.add(request)
                deliveredNotificationIds.insert(notificationId)
                deliveredCount += 1

                // FIFO cache eviction
                if deliveredNotificationIds.count > maxDeliveredIdsCacheSize {
                    deliveredNotificationIds.removeFirst()
                }
            } catch {
                // Silently skip failed notification delivery
            }
        }

        // Update badge after processing
        await updateBadgeCount()
    }

    // MARK: - Notification Removal (NOTIF-05)

    public func removeNotifications(forEmailIds emailIds: [String]) async {
        let identifiers = emailIds.map { "email-\($0)" }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for id in identifiers {
            deliveredNotificationIds.remove(id)
        }
        await updateBadgeCount()
    }

    public func removeNotifications(forThreadId threadId: String) async {
        // Get delivered notifications and filter by threadId
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered
            .filter { $0.request.content.threadIdentifier == threadId }
            .map { $0.request.identifier }

        if !identifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            for id in identifiers {
                deliveredNotificationIds.remove(id)
            }
        }
        await updateBadgeCount()
    }

    // MARK: - Badge Management (NOTIF-06)

    public func updateBadgeCount() async {
        do {
            let count = try await emailRepository.getInboxUnreadCount()
            try await center.setBadgeCount(count)
        } catch {
            // Badge update failure is non-critical
        }
    }

    // MARK: - Configuration (NOTIF-07)

    public func registerCategories() {
        let markReadAction = UNNotificationAction(
            identifier: AppConstants.notificationActionMarkRead,
            title: "Mark as Read",
            options: []
        )
        let archiveAction = UNNotificationAction(
            identifier: AppConstants.notificationActionArchive,
            title: "Archive",
            options: []
        )
        let deleteAction = UNNotificationAction(
            identifier: AppConstants.notificationActionDelete,
            title: "Delete",
            options: [.destructive]
        )
        let replyAction = UNTextInputNotificationAction(
            identifier: AppConstants.notificationActionReply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your reply..."
        )

        let emailCategory = UNNotificationCategory(
            identifier: AppConstants.notificationCategoryEmail,
            actions: [markReadAction, archiveAction, deleteAction, replyAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([emailCategory])
    }

    // MARK: - First Launch (NOTIF-08)

    public func markFirstLaunchComplete() {
        isFirstLaunch = false
    }

    // MARK: - Debug

    #if DEBUG
    public func sendDebugNotification(from email: Email) async {
        // Bypass filter pipeline for debug emails — filters check SwiftData
        // relationships (emailFolders) that don't exist on in-memory test emails.
        let request = NotificationContentBuilder.build(from: email)
        try? await center.add(request)
    }

    public func diagnoseFilter(for email: Email) async -> String {
        await filterPipeline.diagnose(for: email)
    }
    #endif
}

#else

// Stub for platforms without UserNotifications
@Observable
@MainActor
public final class NotificationService: NotificationServiceProtocol {
    public init() {}
    public func requestAuthorization() async -> Bool { false }
    public func authorizationStatus() async -> NotificationAuthStatus { .denied }
    public func processNewEmails(_ emails: [Email], fromBackground: Bool) async {}
    public func removeNotifications(forEmailIds emailIds: [String]) async {}
    public func removeNotifications(forThreadId threadId: String) async {}
    public func updateBadgeCount() async {}
    public func registerCategories() {}
    public func markFirstLaunchComplete() {}

    #if DEBUG
    public func sendDebugNotification(from email: Email) async {}
    public func diagnoseFilter(for email: Email) async -> String { "Unavailable (stub)" }
    #endif
}

#endif
