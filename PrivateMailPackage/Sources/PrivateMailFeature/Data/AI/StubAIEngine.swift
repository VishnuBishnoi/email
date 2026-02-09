import Foundation

/// Graceful degradation engine that returns empty results.
///
/// Used when no generative engine is available (no Foundation Models,
/// no downloaded GGUF model). The UI hides AI features when it detects
/// the stub engine via `isAvailable() == false`.
///
/// Spec ref: FR-AI-01 (graceful degradation), AC-A-02
public final class StubAIEngine: AIEngineProtocol, Sendable {

    public init() {}

    public func isAvailable() async -> Bool {
        false
    }

    public func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    public func classify(text: String, categories: [String]) async throws -> String {
        guard let first = categories.first else {
            throw AIEngineError.noCategories
        }
        return first
    }

    public func embed(text: String) async throws -> [Float] {
        []
    }

    public func unload() async {
        // No-op — nothing loaded
    }
}
