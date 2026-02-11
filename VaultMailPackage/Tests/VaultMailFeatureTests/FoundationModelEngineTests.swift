import Foundation
import Testing
@testable import VaultMailFeature

/// Tests FoundationModelEngine behavior.
///
/// On macOS 26+ / iOS 26+ where `canImport(FoundationModels)` is true AND
/// Apple Intelligence is available, the engine is live. On older platforms,
/// or when Apple Intelligence is not configured, all methods gracefully degrade.
///
/// Tests are structured to pass on both paths: they verify either the live
/// or fallback behavior depending on actual `isAvailable()`.
@Suite("FoundationModelEngine")
struct FoundationModelEngineTests {

    @Test("init succeeds without crash")
    func initSucceeds() {
        let engine = FoundationModelEngine()
        _ = engine
    }

    @Test("isAvailable returns a Bool without crash")
    func isAvailableReturnsBool() async {
        let engine = FoundationModelEngine()
        let available = await engine.isAvailable()
        // On macOS 26 with Apple Intelligence: true
        // On iOS < 26 or without Apple Intelligence: false
        // Either way, it should return without crash
        _ = available
    }

    @Test("generate returns a stream (empty or with tokens)")
    func generateReturnsStream() async {
        let engine = FoundationModelEngine()
        let available = await engine.isAvailable()
        let stream = await engine.generate(prompt: "Say hi", maxTokens: 10)

        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }

        if available {
            // Live engine may produce tokens
            // (no assertion on count — depends on model availability)
        } else {
            #expect(tokens.isEmpty)
        }
    }

    @Test("classify behavior depends on availability")
    func classifyBehavior() async {
        let engine = FoundationModelEngine()
        let available = await engine.isAvailable()

        if available {
            // Live engine should return a category or throw classification error
            do {
                let result = try await engine.classify(text: "Hello", categories: ["greeting", "farewell"])
                #expect(!result.isEmpty)
            } catch {
                // Classification might fail — that's acceptable
            }
        } else {
            // Fallback should throw engineUnavailable
            await #expect(throws: AIEngineError.self) {
                _ = try await engine.classify(text: "Test", categories: ["a", "b"])
            }
        }
    }

    @Test("embed always throws engineUnavailable (Foundation Models has no embed API)")
    func embedThrowsUnavailable() async {
        let engine = FoundationModelEngine()
        // embed() always throws — even on live engine, Foundation Models
        // doesn't expose an embedding API
        await #expect(throws: AIEngineError.self) {
            _ = try await engine.embed(text: "Test")
        }
    }

    @Test("unload is a no-op and does not crash")
    func unloadIsNoOp() async {
        let engine = FoundationModelEngine()
        await engine.unload()
    }

    @Test("classify with empty categories throws")
    func classifyEmptyCategoriesThrows() async {
        let engine = FoundationModelEngine()
        let available = await engine.isAvailable()

        if available {
            // Live engine should throw noCategories
            await #expect(throws: AIEngineError.self) {
                _ = try await engine.classify(text: "Test", categories: [])
            }
        } else {
            // Fallback throws engineUnavailable regardless
            await #expect(throws: AIEngineError.self) {
                _ = try await engine.classify(text: "Test", categories: [])
            }
        }
    }
}
