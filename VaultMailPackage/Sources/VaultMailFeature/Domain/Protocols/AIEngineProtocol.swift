import Foundation

/// Low-level protocol for on-device AI inference engines.
///
/// Three implementations form a tiered fallback chain:
/// 1. `FoundationModelEngine` — Apple Intelligence (iOS/macOS 26+)
/// 2. `LlamaEngine` — llama.cpp with downloaded GGUF models
/// 3. `StubAIEngine` — graceful degradation (returns empty results)
///
/// **Threading**: This protocol is intentionally **nonisolated** (not @MainActor).
/// Inference runs on background threads. Use cases that call engine methods
/// update SwiftData on @MainActor after receiving results.
///
/// All methods are async to support both actor-based (LlamaEngine) and
/// non-actor (StubAIEngine, FoundationModelEngine) implementations.
///
/// **Canonical shape** (spec Section 7.1):
/// - `isAvailable() async -> Bool`
/// - `generate(prompt:maxTokens:) async -> AsyncStream<String>`
/// - `classify(text:categories:) async throws -> String`
/// - `embed(text:) async throws -> [Float]`
/// - `unload() async`
///
/// Spec ref: FR-AI-01, AI-03 (Constitution)
/// Validation ref: AC-A-02
public protocol AIEngineProtocol: Sendable {
    /// Whether this engine is ready for inference.
    ///
    /// For `FoundationModelEngine`: checks `SystemLanguageModel.isAvailable`.
    /// For `LlamaEngine`: checks that a GGUF model is loaded.
    /// For `StubAIEngine`: always returns `false`.
    func isAvailable() async -> Bool

    /// Generate text from a prompt, streaming tokens as they are produced.
    ///
    /// - Parameters:
    ///   - prompt: The full prompt string (already formatted by `PromptTemplates`).
    ///   - maxTokens: Maximum number of tokens to generate.
    /// - Returns: An `AsyncStream` that yields token strings as they are decoded.
    ///
    /// Supports cooperative cancellation via `Task.isCancelled`.
    func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String>

    /// Classify text into one of the provided categories.
    ///
    /// Used as LLM fallback when CoreML classification is unavailable.
    /// The engine generates a structured response selecting one of the categories.
    ///
    /// - Parameters:
    ///   - text: Email text to classify.
    ///   - categories: Valid category names (e.g., ["primary", "social", "promotions"]).
    /// - Returns: The selected category name.
    func classify(text: String, categories: [String]) async throws -> String

    /// Generate an embedding vector for the given text.
    ///
    /// Used for semantic search when CoreML embedding model is unavailable.
    ///
    /// - Parameter text: Text to embed.
    /// - Returns: A float array (dimensionality depends on the model).
    func embed(text: String) async throws -> [Float]

    /// Unload the model from memory.
    ///
    /// Called when memory pressure is detected or when the engine is no longer needed.
    /// After calling this, `isAvailable()` returns `false` until a new model is loaded.
    func unload() async
}
