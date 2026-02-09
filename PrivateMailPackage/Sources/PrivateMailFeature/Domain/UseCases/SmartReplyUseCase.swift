import Foundation

/// Use case for generating smart reply suggestions.
///
/// Wraps AIRepositoryProtocol.smartReply. Returns empty array on failure
/// (graceful hiding per FR-ED-02).
///
/// Smart replies are available in reply and reply-all modes only.
/// Generation is asynchronous and non-blocking — if unavailable,
/// the suggestion area is hidden entirely (no error shown).
///
/// Spec ref: Email Detail FR-ED-02, Email Composer FR-COMP-03
@MainActor
public protocol SmartReplyUseCaseProtocol {
    /// Generate replies for a full Email model (used by EmailDetailView).
    func generateReplies(for email: Email) async -> [String]
    /// Generate replies for a composer email context (used by ComposerView).
    func generateReplies(for emailContext: ComposerEmailContext) async -> [String]
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

    public func generateReplies(for emailContext: ComposerEmailContext) async -> [String] {
        // STUB: Composer-context smart replies not yet wired to AI layer.
        // When ready, convert ComposerEmailContext to Email and call aiRepository.
        try? await Task.sleep(for: .milliseconds(100))
        return []
    }
}
