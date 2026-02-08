import Foundation

/// Use case for generating smart reply suggestions.
///
/// Wraps AIRepositoryProtocol.smartReply. Returns empty array on failure
/// (graceful hiding per FR-ED-02).
///
/// Spec ref: Email Detail FR-ED-02
@MainActor
public protocol SmartReplyUseCaseProtocol {
    func generateReplies(for email: Email) async -> [String]
}

@MainActor
public final class SmartReplyUseCase: SmartReplyUseCaseProtocol {
    private let aiRepository: AIRepositoryProtocol

    public init(aiRepository: AIRepositoryProtocol) {
        self.aiRepository = aiRepository
    }

    public func generateReplies(for email: Email) async -> [String] {
        do {
            return try await aiRepository.smartReply(email: email)
        } catch {
            return []  // Graceful hiding per FR-ED-02
        }
    }
}
