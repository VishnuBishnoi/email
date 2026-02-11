import Foundation
@testable import VaultMailFeature

/// Controllable mock of AIRepositoryProtocol for testing AI use cases.
///
/// Isolated to `@MainActor` matching the protocol's isolation.
@MainActor
final class MockAIRepository: AIRepositoryProtocol, @unchecked Sendable {

    // MARK: - Configurable Results

    var summarizeResult: String = "Test summary"
    var smartReplyResult: [String] = ["Thanks!", "Got it", "Will do"]
    var categorizeResult: AICategory = .primary
    var embeddingResult: Data = Data()
    var shouldThrowError = false

    // MARK: - Call Counters

    var summarizeCallCount = 0
    var smartReplyCallCount = 0
    var categorizeCallCount = 0
    var embeddingCallCount = 0

    // MARK: - AIRepositoryProtocol

    func categorize(email: Email) async throws -> AICategory {
        categorizeCallCount += 1
        if shouldThrowError { throw NSError(domain: "MockAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI categorize failed"]) }
        return categorizeResult
    }

    func summarize(thread: VaultMailFeature.Thread) async throws -> String {
        summarizeCallCount += 1
        if shouldThrowError { throw NSError(domain: "MockAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "AI summarize failed"]) }
        return summarizeResult
    }

    func smartReply(email: Email) async throws -> [String] {
        smartReplyCallCount += 1
        if shouldThrowError { throw NSError(domain: "MockAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "AI smart reply failed"]) }
        return smartReplyResult
    }

    func generateEmbedding(text: String) async throws -> Data {
        embeddingCallCount += 1
        if shouldThrowError { throw NSError(domain: "MockAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "AI embedding failed"]) }
        return embeddingResult
    }
}
