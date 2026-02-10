import Foundation

/// Auto-selects the best available AI engine based on device capabilities.
///
/// Resolution order for generative engine (spec Section 8):
/// 1. **Foundation Models** (iOS/macOS 26+, Apple Intelligence) — zero download
/// 2. **llama.cpp** (iOS 18+, downloaded GGUF) — RAM-based model selection
/// 3. **StubAIEngine** — graceful degradation (no generative features)
///
/// RAM-based model selection for llama.cpp (spec FR-AI-01):
/// - ≥ 6 GB RAM → Qwen3-1.7B (1 GB GGUF)
/// - < 6 GB RAM → Qwen3-0.6B (400 MB GGUF)
///
/// Spec ref: FR-AI-01, Spec Section 8, AC-A-02
public actor AIEngineResolver {

    // MARK: - Dependencies

    private let modelManager: ModelManager
    /// Tier-1 engine slot. Typed as `any AIEngineProtocol` so tests can inject
    /// a `StubAIEngine` to force fallback to keyword classification.
    private let foundationModelEngine: any AIEngineProtocol
    private let llamaEngine: LlamaEngine
    private let stubEngine: StubAIEngine

    // Cache the resolved engine to avoid re-resolution on every call.
    // TTL of 60 seconds: after that, re-resolve to pick up new model downloads/deletes.
    private var cachedEngine: (any AIEngineProtocol)?
    private var lastResolveTime: Date?
    private let cacheTTL: TimeInterval = 60

    // MARK: - Init

    public init(
        modelManager: ModelManager,
        foundationModelEngine: any AIEngineProtocol = FoundationModelEngine(),
        llamaEngine: LlamaEngine = LlamaEngine(),
        stubEngine: StubAIEngine = StubAIEngine()
    ) {
        self.modelManager = modelManager
        self.foundationModelEngine = foundationModelEngine
        self.llamaEngine = llamaEngine
        self.stubEngine = stubEngine
    }

    // MARK: - Resolution

    /// Resolve the best available generative AI engine.
    ///
    /// Follows the tiered fallback chain: FM → llama.cpp → stub.
    ///
    /// Spec ref: AC-A-02 — `resolveGenerativeEngine()` return logic:
    /// - iOS 26+ with Apple Intelligence → `FoundationModelEngine`
    /// - iOS 18-25 with downloaded GGUF → `LlamaEngine`
    /// - No generative engine → `StubAIEngine` (graceful degradation)
    public func resolveGenerativeEngine() async -> any AIEngineProtocol {
        // Return cached engine if within TTL
        if let cached = cachedEngine,
           let resolveTime = lastResolveTime,
           Date().timeIntervalSince(resolveTime) < cacheTTL {
            return cached
        }

        let resolved = await performResolution()
        cachedEngine = resolved
        lastResolveTime = Date()
        return resolved
    }

    /// Perform the actual engine resolution without caching.
    private func performResolution() async -> any AIEngineProtocol {
        // Tier 1: Foundation Models (iOS/macOS 26+)
        // FoundationModelEngine wraps Apple's on-device language model API.
        // Provides zero-download generative AI via Apple Intelligence.
        // On platforms without FoundationModels framework, the engine's
        // isAvailable() always returns false and is immediately skipped.
        if await foundationModelEngine.isAvailable() {
            return foundationModelEngine
        }

        // Tier 2: llama.cpp with downloaded GGUF
        if await llamaEngine.isAvailable() {
            return llamaEngine
        }

        // Try to load a downloaded model.
        // Check recommended model first, then fall back to any other downloaded model.
        // This ensures a user who downloads a non-recommended model (e.g., smaller model
        // on a high-RAM device for storage reasons) still gets AI features.
        let recommended = recommendedModelID()
        let modelIDs = ModelManager.availableModelInfos.map(\.id)
        let sortedIDs = modelIDs.sorted { a, _ in a == recommended }

        for modelID in sortedIDs {
            if await modelManager.isModelDownloaded(id: modelID),
               let modelPath = await modelManager.modelPath(forID: modelID) {
                do {
                    try await llamaEngine.loadModel(at: modelPath.path)
                    return llamaEngine
                } catch {
                    // This model failed to load — try next
                    continue
                }
            }
        }

        // Tier 3: Graceful degradation
        return stubEngine
    }

    /// Determine the recommended model ID based on device RAM.
    ///
    /// - ≥ 6 GB → Qwen3-1.7B
    /// - < 6 GB → Qwen3-0.6B
    ///
    /// Spec ref: AC-A-02
    public nonisolated func recommendedModelID() -> String {
        let ramGB = deviceRAMInGB()
        if ramGB >= 6 {
            return "qwen3-1.7b-q4km"
        } else {
            return "qwen3-0.6b-q4km"
        }
    }

    /// Invalidate the cached engine resolution.
    ///
    /// Call this after a model is downloaded or deleted to force re-resolution.
    public func invalidateCache() {
        cachedEngine = nil
        lastResolveTime = nil
    }

    // MARK: - Device Info

    /// Get device RAM in gigabytes.
    nonisolated func deviceRAMInGB() -> Int {
        let bytesPerGB: UInt64 = 1_073_741_824
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        return Int(totalRAM / bytesPerGB)
    }
}
