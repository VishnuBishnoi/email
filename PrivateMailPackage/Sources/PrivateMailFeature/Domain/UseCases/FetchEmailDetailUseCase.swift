import Foundation

/// Use case for fetching a thread with its emails for the detail view.
///
/// Per FR-FOUND-01, views MUST call use cases, not repositories.
///
/// Spec ref: Email Detail FR-ED-01
@MainActor
public protocol FetchEmailDetailUseCaseProtocol {
    /// Fetch a thread by ID with all emails.
    func fetchThread(threadId: String) async throws -> Thread

    // MARK: - Trusted Senders (FR-ED-04)

    /// Get all trusted sender email addresses.
    func getAllTrustedSenderEmails() async throws -> Set<String>
    /// Save a sender as trusted (always load remote images).
    func saveTrustedSender(email: String) async throws
}

@MainActor
public final class FetchEmailDetailUseCase: FetchEmailDetailUseCaseProtocol {
    private let repository: EmailRepositoryProtocol

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    public func fetchThread(threadId: String) async throws -> Thread {
        do {
            guard let thread = try await repository.getThread(id: threadId) else {
                throw EmailDetailError.threadNotFound(id: threadId)
            }
            return thread
        } catch let error as EmailDetailError {
            throw error
        } catch {
            throw EmailDetailError.loadFailed(error.localizedDescription)
        }
    }

    public func getAllTrustedSenderEmails() async throws -> Set<String> {
        let senders = try await repository.getAllTrustedSenders()
        return Set(senders.map(\.senderEmail))
    }

    public func saveTrustedSender(email senderEmail: String) async throws {
        let sender = TrustedSender(senderEmail: senderEmail)
        try await repository.saveTrustedSender(sender)
    }
}
