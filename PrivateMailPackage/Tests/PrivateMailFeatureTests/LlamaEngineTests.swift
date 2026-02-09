import Testing
import Foundation
@testable import PrivateMailFeature

@Suite("LlamaEngine")
struct LlamaEngineTests {

    @Test("isAvailable returns false when no model loaded")
    func notAvailableByDefault() async {
        let engine = LlamaEngine()
        let available = await engine.isAvailable()
        #expect(!available)
    }

    @Test("loadModel throws modelNotFound for missing file")
    func loadModelMissingFile() async {
        let engine = LlamaEngine()
        await #expect(throws: AIEngineError.self) {
            try await engine.loadModel(at: "/nonexistent/path/model.gguf")
        }
    }

    @Test("loadModel throws modelNotFound with correct path in error")
    func loadModelMissingFileErrorPath() async {
        let engine = LlamaEngine()
        let path = "/tmp/nonexistent-\(UUID().uuidString).gguf"

        do {
            try await engine.loadModel(at: path)
            #expect(Bool(false), "Should have thrown")
        } catch let error as AIEngineError {
            if case .modelNotFound(let errorPath) = error {
                #expect(errorPath == path)
            } else {
                #expect(Bool(false), "Expected modelNotFound, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected AIEngineError, got \(error)")
        }
    }

    @Test("generate returns empty stream when no model loaded")
    func generateEmptyWithoutModel() async {
        let engine = LlamaEngine()
        let stream = await engine.generate(prompt: "Hello", maxTokens: 10)

        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }

        #expect(tokens.isEmpty, "Should return empty stream without loaded model")
    }

    @Test("classify throws engineUnavailable without loaded model")
    func classifyThrowsWithoutModel() async {
        let engine = LlamaEngine()
        await #expect(throws: AIEngineError.self) {
            try await engine.classify(
                text: "Test email",
                categories: ["primary", "social"]
            )
        }
    }

    @Test("embed always throws engineUnavailable")
    func embedAlwaysThrows() async {
        let engine = LlamaEngine()
        await #expect(throws: AIEngineError.self) {
            try await engine.embed(text: "Test")
        }
    }

    @Test("unload does not crash when no model loaded")
    func unloadSafe() async {
        let engine = LlamaEngine()
        await engine.unload()
        // Should not crash
        let available = await engine.isAvailable()
        #expect(!available)
    }

    @Test("loadedModelPath is nil when no model loaded")
    func noModelPath() async {
        let engine = LlamaEngine()
        let path = await engine.loadedModelPath()
        #expect(path == nil)
    }

    @Test("configuration uses sensible defaults")
    func defaultConfiguration() {
        let config = LlamaEngine.Configuration.default
        #expect(config.contextSize == 2048)
        #expect(config.gpuLayers == -1)
        #expect(config.threadCount == 4)
        #expect(config.temperature == 0.7)
        #expect(config.topK == 40)
        #expect(config.topP == 0.9)
    }

    @Test("custom configuration is respected")
    func customConfiguration() {
        let config = LlamaEngine.Configuration(
            contextSize: 4096,
            gpuLayers: 20,
            threadCount: 8,
            temperature: 0.5,
            topK: 50,
            topP: 0.95
        )
        #expect(config.contextSize == 4096)
        #expect(config.gpuLayers == 20)
        #expect(config.threadCount == 8)
        #expect(config.temperature == 0.5)
        #expect(config.topK == 50)
        #expect(config.topP == 0.95)
    }
}
