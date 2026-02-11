import Testing
import Foundation
@testable import VaultMailFeature

// MARK: - Mock Embedding Engine

/// Lightweight configurable mock for testing embedding generation.
/// Named distinctly from the shared `MockAIEngine` actor in Mocks/.
private struct MockEmbeddingEngine: AIEngineProtocol {
    var available: Bool = true
    var embedResult: [Float]? = nil
    var shouldThrow: Bool = false

    func isAvailable() async -> Bool { available }

    func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    func classify(text: String, categories: [String]) async throws -> String { "" }

    func embed(text: String) async throws -> [Float] {
        if shouldThrow {
            throw NSError(domain: "MockEmbeddingEngine", code: 1, userInfo: nil)
        }
        return embedResult ?? []
    }

    func unload() async {}
}

// MARK: - Tests

@Suite("GenerateEmbeddingUseCase Tests")
struct GenerateEmbeddingUseCaseTests {

    @Test("embedQuery returns nil when engine is unavailable")
    func embedQueryUnavailable() async {
        let engine = MockEmbeddingEngine(available: false)
        let result = await GenerateEmbeddingUseCase.embedQuery(
            text: "test query",
            using: engine
        )
        #expect(result == nil)
    }

    @Test("embedQuery returns normalized vector when engine succeeds")
    func embedQuerySuccess() async throws {
        let rawVector: [Float] = [3.0, 4.0]
        let engine = MockEmbeddingEngine(available: true, embedResult: rawVector)

        let result = await GenerateEmbeddingUseCase.embedQuery(
            text: "test query",
            using: engine
        )

        let vector = try #require(result)
        #expect(vector.count == 2)

        // Expected: [3/5, 4/5] = [0.6, 0.8]
        #expect(abs(vector[0] - 0.6) < 1e-5)
        #expect(abs(vector[1] - 0.8) < 1e-5)

        // Verify L2 norm is approximately 1.0
        let norm = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 1e-5)
    }

    @Test("embedQuery returns nil when engine throws")
    func embedQueryThrows() async {
        let engine = MockEmbeddingEngine(available: true, shouldThrow: true)
        let result = await GenerateEmbeddingUseCase.embedQuery(
            text: "test query",
            using: engine
        )
        #expect(result == nil)
    }

    @Test("embedQuery returns nil when engine returns empty vector")
    func embedQueryEmptyVector() async {
        let engine = MockEmbeddingEngine(available: true, embedResult: [])
        let result = await GenerateEmbeddingUseCase.embedQuery(
            text: "test query",
            using: engine
        )
        #expect(result == nil)
    }

    @Test("embedBatch returns array with nil elements for failed embeddings")
    func embedBatchPartialFailure() async {
        // Engine that throws on embed — all embeddings should be nil
        let engine = MockEmbeddingEngine(available: true, shouldThrow: true)
        let results = await GenerateEmbeddingUseCase.embedBatch(
            texts: ["text1", "text2", "text3"],
            using: engine
        )

        #expect(results.count == 3)
        for result in results {
            #expect(result == nil)
        }
    }

    @Test("embedBatch returns all nil when engine is unavailable")
    func embedBatchUnavailable() async {
        let engine = MockEmbeddingEngine(available: false)
        let results = await GenerateEmbeddingUseCase.embedBatch(
            texts: ["a", "b"],
            using: engine
        )

        #expect(results.count == 2)
        #expect(results[0] == nil)
        #expect(results[1] == nil)
    }

    @Test("embedBatch returns normalized vectors when engine succeeds")
    func embedBatchSuccess() async throws {
        let engine = MockEmbeddingEngine(available: true, embedResult: [3.0, 4.0])
        let results = await GenerateEmbeddingUseCase.embedBatch(
            texts: ["text1", "text2"],
            using: engine
        )

        #expect(results.count == 2)
        for result in results {
            let vector = try #require(result)
            let norm = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
            #expect(abs(norm - 1.0) < 1e-5)
        }
    }

    @Test("normalize produces a unit vector")
    func normalizeUnitVector() {
        let input: [Float] = [1.0, 2.0, 3.0, 4.0]
        let normalized = GenerateEmbeddingUseCase.normalize(input)

        #expect(normalized.count == input.count)

        // L2 norm should be approximately 1.0
        let norm = sqrt(normalized.reduce(0.0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 1e-5)

        // Direction should be preserved (ratios between elements)
        // input[1] / input[0] == normalized[1] / normalized[0]
        let originalRatio = input[1] / input[0]
        let normalizedRatio = normalized[1] / normalized[0]
        #expect(abs(originalRatio - normalizedRatio) < 1e-5)
    }

    @Test("normalize handles zero vector without crashing")
    func normalizeZeroVector() {
        let input: [Float] = [0.0, 0.0, 0.0]
        let normalized = GenerateEmbeddingUseCase.normalize(input)

        #expect(normalized.count == 3)
        // Zero vector should remain zero (no division by zero)
        for value in normalized {
            #expect(value == 0.0)
        }
    }

    @Test("embedBatch with empty input returns empty array")
    func embedBatchEmptyInput() async {
        let engine = MockEmbeddingEngine(available: true)
        let results = await GenerateEmbeddingUseCase.embedBatch(
            texts: [],
            using: engine
        )
        #expect(results.isEmpty)
    }
}
