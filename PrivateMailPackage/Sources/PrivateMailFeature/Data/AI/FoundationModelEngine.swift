import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Tier-1 on-device AI engine wrapping Apple's Foundation Models framework.
///
/// Provides zero-download generative AI via Apple Intelligence on devices
/// running iOS 26+ / macOS 26+. The system manages the model lifecycle
/// (loading, caching, memory eviction), so this engine has no explicit
/// load/unload management.
///
/// **Threading**: This class is `Sendable` and safe to call from any context.
/// Foundation Models session calls are async but do not require actor isolation.
///
/// **Capabilities**:
/// - Text generation with streaming (via `LanguageModelSession.streamResponse`)
/// - Classification (prompt-based, picks one category)
/// - Embedding: **not supported** — throws `AIEngineError.engineUnavailable`
///
/// Spec ref: FR-AI-01 (Tier 1 — Foundation Models), AC-A-02
///
/// **Availability note:** The class itself has no `@available` annotation so it
/// can be stored as a property on any deployment target. Runtime availability
/// is gated inside each method via `#available(iOS 26.0, macOS 26.0, *)`.
/// On older OS versions every method gracefully degrades (returns unavailable /
/// empty stream / throws).
public final class FoundationModelEngine: AIEngineProtocol, Sendable {

    // MARK: - Init

    public init() {}

    // MARK: - AIEngineProtocol

    public func isAvailable() async -> Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    public func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return AsyncStream { $0.finish() }
        }

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)

        // Capture prompt for the detached task
        let capturedPrompt = prompt

        Task {
            defer { continuation.finish() }

            do {
                let session = LanguageModelSession()
                let responseStream = session.streamResponse(to: capturedPrompt)

                for try await partialText in responseStream {
                    guard !Task.isCancelled else { break }
                    let text = String(describing: partialText)
                    if !text.isEmpty {
                        continuation.yield(text)
                    }
                }
            } catch {
                // Generation failed — finish the stream silently.
                // Callers handle empty streams gracefully per FR-ED-02.
            }
        }

        return stream
    }

    public func classify(text: String, categories: [String]) async throws -> String {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw AIEngineError.engineUnavailable
        }
        guard await isAvailable() else {
            throw AIEngineError.engineUnavailable
        }
        guard !categories.isEmpty else {
            throw AIEngineError.noCategories
        }

        let categoryList = categories.joined(separator: ", ")
        let prompt = """
        Classify the following email into exactly one of these categories: \(categoryList).
        Respond with only the category name, nothing else.

        Email: \(text.prefix(1000))

        Category:
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        let trimmed = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let match = categories.first(where: { trimmed.contains($0.lowercased()) }) {
            return match
        }

        throw AIEngineError.classificationFailed(response: response.content)
    }

    public func embed(text: String) async throws -> [Float] {
        // Foundation Models does not expose an embedding API.
        // The VectorStore uses CoreML MiniLM for embeddings instead.
        throw AIEngineError.engineUnavailable
    }

    public func unload() async {
        // No-op — the system manages Foundation Models lifecycle.
        // There are no resources to release on our side.
    }
}

#else

/// Fallback for platforms where Foundation Models is not available (iOS < 26).
///
/// This stub always reports unavailable, ensuring compile-time safety
/// on older deployment targets. The `AIEngineResolver` skips this engine
/// when it returns `false` from `isAvailable()` and falls through to
/// the llama.cpp or stub tiers.
///
/// Spec ref: FR-AI-01 (graceful degradation)
public final class FoundationModelEngine: AIEngineProtocol, Sendable {

    public init() {}

    public func isAvailable() async -> Bool {
        false
    }

    public func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    public func classify(text: String, categories: [String]) async throws -> String {
        throw AIEngineError.engineUnavailable
    }

    public func embed(text: String) async throws -> [Float] {
        throw AIEngineError.engineUnavailable
    }

    public func unload() async {
        // No-op — nothing to unload
    }
}

#endif
