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
}
