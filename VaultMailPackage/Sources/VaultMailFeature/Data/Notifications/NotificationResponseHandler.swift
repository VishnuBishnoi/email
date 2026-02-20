#if canImport(UserNotifications)
import UserNotifications
import Foundation

/// Handles user responses to delivered notifications (taps, actions).
///
/// Implements UNUserNotificationCenterDelegate to receive notification
/// interactions and dispatch them to the appropriate use cases.
///
/// Spec ref: NOTIF-17, NOTIF-18
@MainActor
public final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    private let markReadUseCase: any MarkReadUseCaseProtocol
    private let manageThreadActions: any ManageThreadActionsUseCaseProtocol
    private let composeEmailUseCase: any ComposeEmailUseCaseProtocol
    private let emailRepository: any EmailRepositoryProtocol
    private let notificationService: any NotificationServiceProtocol
    private let coordinator: NotificationSyncCoordinator

    public init(
        markReadUseCase: any MarkReadUseCaseProtocol,
        manageThreadActions: any ManageThreadActionsUseCaseProtocol,
        composeEmailUseCase: any ComposeEmailUseCaseProtocol,
        emailRepository: any EmailRepositoryProtocol,
        notificationService: any NotificationServiceProtocol,
        coordinator: NotificationSyncCoordinator
    ) {
        self.markReadUseCase = markReadUseCase
        self.manageThreadActions = manageThreadActions
        self.composeEmailUseCase = composeEmailUseCase
        self.emailRepository = emailRepository
        self.notificationService = notificationService
        self.coordinator = coordinator
        super.init()
    }

    // MARK: - UNUserNotificationCenterDelegate

    // nonisolated because UNUserNotificationCenterDelegate requires it
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Extract all values before crossing isolation boundary to satisfy Swift 6 Sendable checks.
        // UNNotificationResponse is not Sendable, so we must not capture it in the @MainActor closure.
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        let threadId = userInfo["threadId"] as? String
        let emailId = userInfo["emailId"] as? String
        let accountId = userInfo["accountId"] as? String
        let fromAddress = userInfo["fromAddress"] as? String
        let replyText = (response as? UNTextInputNotificationResponse)?.userText

        let finish = completionHandler

        Task { @MainActor [self] in
            if let threadId {
                await self.handleResponseValues(
                    actionIdentifier: actionIdentifier,
                    threadId: threadId,
                    emailId: emailId,
                    accountId: accountId,
                    fromAddress: fromAddress,
                    replyText: replyText
                )
            }
            finish()
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner, badge, and sound for foreground notifications
        completionHandler([.banner, .badge, .sound])
    }

    // MARK: - Response Handling

    private func handleResponseValues(
        actionIdentifier: String,
        threadId: String,
        emailId: String?,
        accountId: String?,
        fromAddress: String?,
        replyText: String?
    ) async {
        switch actionIdentifier {
        case AppConstants.notificationActionMarkRead:
            await handleMarkRead(threadId: threadId)

        case AppConstants.notificationActionArchive:
            await handleArchive(threadId: threadId)

        case AppConstants.notificationActionDelete:
            await handleDelete(threadId: threadId)

        case AppConstants.notificationActionReply:
            if let replyText {
                await handleReply(
                    replyText: replyText,
                    emailId: emailId,
                    threadId: threadId,
                    accountId: accountId,
                    fromAddress: fromAddress
                )
            }

        default:
            // Default tap action — navigate to thread
            coordinator.pendingThreadNavigation = threadId
        }
    }

    private func handleMarkRead(threadId: String) async {
        do {
            guard let thread = try await emailRepository.getThread(id: threadId) else { return }
            try await markReadUseCase.markAllRead(in: thread)
            await notificationService.removeNotifications(forThreadId: threadId)
        } catch {
            // Non-critical: silently fail
        }
    }

    private func handleArchive(threadId: String) async {
        do {
            try await manageThreadActions.archiveThread(id: threadId)
            await notificationService.removeNotifications(forThreadId: threadId)
        } catch {
            // Non-critical
        }
    }

    private func handleDelete(threadId: String) async {
        do {
            try await manageThreadActions.deleteThread(id: threadId)
            await notificationService.removeNotifications(forThreadId: threadId)
        } catch {
            // Non-critical
        }
    }

    private func handleReply(
        replyText: String,
        emailId: String?,
        threadId: String,
        accountId: String?,
        fromAddress: String?
    ) async {
        guard let emailId, let accountId else { return }

        do {
            // Look up the original email to build reply context
            let originalEmail = try await emailRepository.getEmail(id: emailId)
            let replyTo = fromAddress ?? originalEmail?.fromAddress ?? ""
            let subject = "Re: \(originalEmail?.subject ?? "")"
            let messageId = originalEmail?.messageId
            let references = [originalEmail?.references, messageId]
                .compactMap { $0 }
                .joined(separator: " ")

            // Save draft, queue, and send
            let draftId = try await composeEmailUseCase.saveDraft(
                draftId: nil,
                accountId: accountId,
                threadId: threadId,
                toAddresses: [replyTo],
                ccAddresses: [],
                bccAddresses: [],
                subject: subject,
                bodyPlain: replyText,
                inReplyTo: messageId,
                references: references.isEmpty ? nil : references,
                attachments: []
            )
            try await composeEmailUseCase.queueForSending(emailId: draftId)
            try await composeEmailUseCase.executeSend(emailId: draftId)
        } catch {
            // Reply failed — non-critical, email stays in outbox
        }
    }
}

#endif
