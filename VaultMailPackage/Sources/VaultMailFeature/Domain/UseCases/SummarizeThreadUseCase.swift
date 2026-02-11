import Foundation

/// Use case for generating AI thread summaries.
///
/// Wraps AIRepositoryProtocol.summarize. Returns nil on failure
/// (graceful hiding per FR-ED-02).
///
/// Spec ref: Email Detail FR-ED-02
@MainActor
public protocol SummarizeThreadUseCaseProtocol {
    func summarize(thread: Thread) async -> String?
}

@MainActor
public final class SummarizeThreadUseCase: SummarizeThreadUseCaseProtocol {
    private let aiRepository: AIRepositoryProtocol

    public init(aiRepository: AIRepositoryProtocol) {
        self.aiRepository = aiRepository
    }

    public func summarize(thread: Thread) async -> String? {
        do {
            return try await aiRepository.summarize(thread: thread)
        } catch {
            return nil  // Graceful hiding per FR-ED-02
        }
    }
}
