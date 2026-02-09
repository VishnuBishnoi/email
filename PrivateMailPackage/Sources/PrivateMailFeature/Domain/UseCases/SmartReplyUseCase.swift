import Foundation

/// Use case for generating smart reply suggestions.
///
/// Smart replies are available in reply and reply-all modes only.
/// Generation is asynchronous and non-blocking — if unavailable,
/// the suggestion area is hidden entirely (no error shown).
///
/// STUBBED: The AI layer is not yet built. This returns an empty
/// array, which causes the composer to hide the suggestion area.
///
/// Spec ref: Email Composer spec FR-COMP-03
@MainActor
public protocol SmartReplyUseCaseProtocol {
    /// Generate up to 3 smart reply suggestions for the given email.
    /// Returns empty array if unavailable (no error thrown).
    func generateReplies(for emailContext: ComposerEmailContext) async -> [String]
}

/// Stubbed implementation of `SmartReplyUseCaseProtocol`.
///
/// Returns empty array until the AI layer is built.
/// Per FR-COMP-03: if unavailable, hide suggestion area entirely.
@MainActor
public final class SmartReplyUseCase: SmartReplyUseCaseProtocol {

    public init() {}

    public func generateReplies(for emailContext: ComposerEmailContext) async -> [String] {
        // STUB: AI layer not built yet.
        // When ready, this will call the local llama.cpp model
        // via AIRepositoryProtocol.smartReply(email:).
        // Simulating a brief delay as if checking model availability.
        try? await Task.sleep(for: .milliseconds(100))
        return []
    }
}
