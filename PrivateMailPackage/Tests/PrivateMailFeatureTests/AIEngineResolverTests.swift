import Testing
import Foundation
@testable import PrivateMailFeature

@Suite("AIEngineResolver")
struct AIEngineResolverTests {

    // MARK: - RAM-based model selection

    @Test("recommends Qwen3-1.7B on devices with >= 6 GB RAM")
    func recommendsLargeModel() async {
        let modelManager = ModelManager(
            modelsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ResolverTest-\(UUID().uuidString)")
        )
        let resolver = AIEngineResolver(modelManager: modelManager)
        let recommended = resolver.recommendedModelID()

        // On most Mac dev machines, RAM >= 6 GB
        let ramGB = await resolver.deviceRAMInGB()
        if ramGB >= 6 {
            #expect(recommended == "qwen3-1.7b-q4km")
        } else {
            #expect(recommended == "qwen3-0.6b-q4km")
        }
    }

    @Test("falls back to StubAIEngine when no model is downloaded")
    func fallsBackToStub() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResolverTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)

        // Inject StubAIEngine as the FM engine so the test always exercises
        // the full fallback chain regardless of macOS version / Apple Intelligence.
        let resolver = AIEngineResolver(
            modelManager: modelManager,
            foundationModelEngine: StubAIEngine()
        )

        let engine = await resolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        #expect(!available, "Should return stub engine (not available) when no models downloaded")
        #expect(engine is StubAIEngine, "Resolved engine should be StubAIEngine")

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("device RAM returns a positive value")
    func deviceRAMPositive() async {
        let modelManager = ModelManager(
            modelsDirectory: FileManager.default.temporaryDirectory
        )
        let resolver = AIEngineResolver(modelManager: modelManager)
        let ram = resolver.deviceRAMInGB()

        #expect(ram > 0, "Device should report positive RAM")
    }
}
