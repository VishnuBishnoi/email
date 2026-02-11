import Testing
@testable import VaultMailFeature

@Suite("StubAIEngine")
struct StubAIEngineTests {

    @Test("isAvailable returns false")
    func isNotAvailable() async {
        let engine = StubAIEngine()
        let available = await engine.isAvailable()
        #expect(!available)
    }

    @Test("generate yields no tokens and finishes immediately")
    func generateEmpty() async {
        let engine = StubAIEngine()
        let stream = await engine.generate(prompt: "Hello", maxTokens: 100)

        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }

        #expect(tokens.isEmpty)
    }

    @Test("classify returns first category as default")
    func classifyReturnsFirstCategory() async throws {
        let engine = StubAIEngine()
        let result = try await engine.classify(
            text: "Test email",
            categories: ["promotions", "primary", "social"]
        )
        #expect(result == "promotions")
    }

    @Test("classify throws when categories are empty")
    func classifyThrowsOnEmptyCategories() async {
        let engine = StubAIEngine()
        await #expect(throws: AIEngineError.self) {
            try await engine.classify(text: "Test", categories: [])
        }
    }

    @Test("embed returns empty array")
    func embedReturnsEmpty() async throws {
        let engine = StubAIEngine()
        let result = try await engine.embed(text: "Test")
        #expect(result.isEmpty)
    }

    @Test("unload is a no-op")
    func unloadNoOp() async {
        let engine = StubAIEngine()
        await engine.unload()
        // Should not crash — no-op
        let available = await engine.isAvailable()
        #expect(!available)
    }
}
