import Foundation

/// Use case for marking all unread emails in a thread as read.
///
/// Called immediately when thread opens (FR-ED-01).
/// Optimistic local update.
///
/// Spec ref: Email Detail FR-ED-01
@MainActor
public protocol MarkReadUseCaseProtocol {
    /// Mark all unread emails as read and update thread unreadCount.
    func markAllRead(in thread: Thread) async throws
}

@MainActor
public final class MarkReadUseCase: MarkReadUseCaseProtocol {
    private let repository: EmailRepositoryProtocol

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    public func markAllRead(in thread: Thread) async throws {
        do {
            let unreadEmails = thread.emails.filter { !$0.isRead }
            guard !unreadEmails.isEmpty else { return }

            for email in unreadEmails {
                email.isRead = true
                try await repository.saveEmail(email)
            }
            thread.unreadCount = 0
            try await repository.saveThread(thread)
        } catch {
            throw EmailDetailError.markReadFailed(error.localizedDescription)
        }
    }
}
