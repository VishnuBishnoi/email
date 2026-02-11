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
/// Results are cached on the `Email.aiSmartReplies` field (JSON-encoded)
/// so subsequent views of the same email don't re-run inference.
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
        // Check SwiftData cache first — avoid re-running LLM inference
        if let cached = email.aiSmartReplies,
           let data = cached.data(using: .utf8),
           let replies = try? JSONDecoder().decode([String].self, from: data),
           !replies.isEmpty {
            return replies
        }

        // Generate fresh suggestions
        do {
            let replies = try await aiRepository.smartReply(email: email)
            guard !replies.isEmpty else { return [] }

            // Persist to SwiftData for future loads
            if let jsonData = try? JSONEncoder().encode(replies),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                email.aiSmartReplies = jsonString
            }

            return replies
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
