import Foundation

/// Stub AI repository that returns empty/default results.
///
/// Used as a placeholder until the real llama.cpp-based AI layer is built.
/// All methods return safe defaults (empty arrays, .uncategorized, etc.)
/// so the UI gracefully hides AI features per spec.
@MainActor
public final class StubAIRepository: AIRepositoryProtocol {

    public init() {}

    public func categorize(email: Email) async throws -> AICategory {
        .uncategorized
    }

    public func summarize(thread: Thread) async throws -> String {
        ""
    }

    public func smartReply(email: Email) async throws -> [String] {
        []
    }

    public func generateEmbedding(text: String) async throws -> Data {
        Data()
    }
}
