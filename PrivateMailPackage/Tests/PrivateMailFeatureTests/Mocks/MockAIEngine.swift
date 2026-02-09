import Foundation
@testable import PrivateMailFeature

/// Controllable mock of AIEngineProtocol for testing engine resolver and use cases.
///
/// Allows configuring availability, generated output, classification results,
/// and embedding output. Tracks call counts for verification.
actor MockAIEngine: AIEngineProtocol {

    // MARK: - Configurable State

    var _isAvailable = false
    var generateTokens: [String] = []
    var classifyResult: String = "primary"
    var embedResult: [Float] = []
    var shouldThrow = false
    var unloadCallCount = 0
    var generateCallCount = 0
    var classifyCallCount = 0
    var embedCallCount = 0

    // MARK: - Configuration helpers

    func setAvailable(_ available: Bool) {
        _isAvailable = available
    }

    func setGenerateTokens(_ tokens: [String]) {
        generateTokens = tokens
    }

    func setClassifyResult(_ result: String) {
        classifyResult = result
    }

    func setShouldThrow(_ shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
    }

    func getUnloadCallCount() -> Int { unloadCallCount }
    func getGenerateCallCount() -> Int { generateCallCount }
    func getClassifyCallCount() -> Int { classifyCallCount }
    func getEmbedCallCount() -> Int { embedCallCount }

    // MARK: - AIEngineProtocol

    func isAvailable() -> Bool {
        _isAvailable
    }

    func generate(prompt: String, maxTokens: Int) -> AsyncStream<String> {
        generateCallCount += 1
        let tokens = generateTokens
        return AsyncStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func classify(text: String, categories: [String]) async throws -> String {
        classifyCallCount += 1
        if shouldThrow { throw AIEngineError.engineUnavailable }
        return classifyResult
    }

    func embed(text: String) async throws -> [Float] {
        embedCallCount += 1
        if shouldThrow { throw AIEngineError.engineUnavailable }
        return embedResult
    }

    func unload() {
        unloadCallCount += 1
        _isAvailable = false
    }
}
