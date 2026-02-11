import Foundation
import LlamaSwift

/// On-device LLM inference engine wrapping llama.cpp.
///
/// Loads GGUF model files and provides streaming text generation,
/// classification (LLM fallback), and embedding generation.
///
/// **Threading**: This actor runs inference on a background thread.
/// All llama.cpp C API calls are serialized through the actor.
///
/// **Memory management**: The model and context are loaded on demand
/// and can be unloaded via `unload()` to free memory under pressure.
///
/// Spec ref: FR-AI-01 (Tier 2 — llama.cpp), AC-A-01
public actor LlamaEngine: AIEngineProtocol {

    // MARK: - Configuration

    /// Configuration for the llama.cpp inference context.
    public struct Configuration: Sendable {
        /// Number of context tokens. Affects memory usage.
        public var contextSize: UInt32
        /// Number of GPU layers to offload (Metal). -1 = all layers.
        public var gpuLayers: Int32
        /// Number of threads for CPU inference.
        public var threadCount: Int32
        /// Temperature for sampling (0.0 = greedy, higher = more random).
        public var temperature: Float
        /// Top-K sampling: consider only the K most likely tokens.
        public var topK: Int32
        /// Top-P (nucleus) sampling: consider tokens with cumulative probability ≤ P.
        public var topP: Float

        /// Default configuration suitable for email tasks on mobile devices.
        public static let `default` = Configuration(
            contextSize: 2048,
            gpuLayers: -1,  // Offload all layers to Metal/GPU
            threadCount: 4,
            temperature: 0.7,
            topK: 40,
            topP: 0.9
        )

        public init(
            contextSize: UInt32 = 2048,
            gpuLayers: Int32 = -1,
            threadCount: Int32 = 4,
            temperature: Float = 0.7,
            topK: Int32 = 40,
            topP: Float = 0.9
        ) {
            self.contextSize = contextSize
            self.gpuLayers = gpuLayers
            self.threadCount = threadCount
            self.temperature = temperature
            self.topK = topK
            self.topP = topP
        }
    }

    // MARK: - State

    private var model: OpaquePointer?     // llama_model *
    private var ctx: OpaquePointer?       // llama_context *
    private var samplerChain: UnsafeMutablePointer<llama_sampler>?
    private let config: Configuration
    private var _modelPath: String?

    // MARK: - Init

    public init(configuration: Configuration = .default) {
        self.config = configuration
    }

    // MARK: - AIEngineProtocol

    public func isAvailable() -> Bool {
        model != nil && ctx != nil && samplerChain != nil
    }

    public func generate(prompt: String, maxTokens: Int) -> AsyncStream<String> {
        guard let model = self.model,
              let ctx = self.ctx,
              let samplerChain = self.samplerChain else {
            return AsyncStream { $0.finish() }
        }

        // Generate all tokens within the actor's isolation, then
        // emit them via AsyncStream (no actor-crossing of C pointers).
        var tokens: [String] = []
        do {
            tokens = try self.generateAllTokens(
                model: model,
                ctx: ctx,
                sampler: samplerChain,
                prompt: prompt,
                maxTokens: maxTokens
            )
        } catch {
            // Return empty stream on failure
        }

        let capturedTokens = tokens
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        for token in capturedTokens {
            continuation.yield(token)
        }
        continuation.finish()
        return stream
    }

    public func classify(text: String, categories: [String]) async throws -> String {
        guard isAvailable() else {
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

        var result = ""
        for await token in generate(prompt: prompt, maxTokens: 20) {
            result += token
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Return matched category, or throw if LLM response doesn't match any (P2-1).
        // Avoids defaulting to categories[0] which would introduce bias.
        if let match = categories.first(where: { trimmed.contains($0.lowercased()) }) {
            return match
        }
        throw AIEngineError.classificationFailed(response: result)
    }

    public func embed(text: String) async throws -> [Float] {
        // LLM-based embedding is not the primary path (CoreML MiniLM is preferred).
        // Throw — the VectorStore will skip indexing when CoreML is unavailable.
        throw AIEngineError.engineUnavailable
    }

    public func unload() {
        cleanupResources()
    }

    // MARK: - Model Loading

    /// Load a GGUF model from the specified file path.
    ///
    /// - Parameter path: Absolute path to the .gguf model file.
    /// - Throws: `AIEngineError` if the file is missing or loading fails.
    public func loadModel(at path: String) throws {
        cleanupResources()

        guard FileManager.default.fileExists(atPath: path) else {
            throw AIEngineError.modelNotFound(path: path)
        }

        // Initialize llama backend (idempotent)
        llama_backend_init()

        // Load model
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.gpuLayers

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw AIEngineError.modelLoadFailed("llama_model_load_from_file returned nil for \(path)")
        }
        self.model = loadedModel

        // Create context
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = config.contextSize
        ctxParams.n_threads = config.threadCount
        ctxParams.n_threads_batch = config.threadCount

        guard let context = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            self.model = nil
            throw AIEngineError.contextCreationFailed
        }
        self.ctx = context

        // Create sampler chain
        self.samplerChain = createSamplerChain()
        self._modelPath = path
    }

    /// The path of the currently loaded model, or nil if no model is loaded.
    public func loadedModelPath() -> String? {
        _modelPath
    }

    // MARK: - Private: Token Generation

    /// Generate all tokens synchronously within the actor's isolation.
    ///
    /// Returns an array of string tokens. This runs entirely on the actor,
    /// ensuring safe access to model/context/sampler C pointers.
    private func generateAllTokens(
        model: OpaquePointer,
        ctx: OpaquePointer,
        sampler: UnsafeMutablePointer<llama_sampler>,
        prompt: String,
        maxTokens: Int
    ) throws -> [String] {
        let vocab = llama_model_get_vocab(model)

        // Tokenize the prompt
        let tokens = try tokenize(text: prompt, vocab: vocab, addBos: true)
        guard !tokens.isEmpty else {
            throw AIEngineError.tokenizationFailed
        }

        // Check context size
        let nCtx = llama_n_ctx(ctx)
        let promptLen = Int32(tokens.count)
        guard promptLen < nCtx else {
            throw AIEngineError.tokenizationFailed
        }

        // Clear KV cache for fresh generation
        llama_memory_clear(llama_get_memory(ctx), true)

        // Process prompt (prefill)
        var promptTokens = tokens
        let batch = llama_batch_get_one(&promptTokens, promptLen)
        let decodeResult = llama_decode(ctx, batch)
        guard decodeResult == 0 else {
            throw AIEngineError.decodeFailed(decodeResult)
        }

        let eosToken = llama_vocab_eos(vocab)
        var result: [String] = []

        // Auto-regressive generation loop
        for _ in 0..<maxTokens {
            guard !Task.isCancelled else { break }

            // Sample next token
            let newToken = llama_sampler_sample(sampler, ctx, -1)

            // Check for end-of-sequence
            if newToken == eosToken || llama_vocab_is_eog(vocab, newToken) {
                break
            }

            // Convert token to string
            let piece = tokenToPiece(token: newToken, vocab: vocab)
            if !piece.isEmpty {
                result.append(piece)
            }

            // Prepare and decode next token
            var nextTokens: [llama_token] = [newToken]
            let nextBatch = llama_batch_get_one(&nextTokens, 1)
            let nextResult = llama_decode(ctx, nextBatch)
            guard nextResult == 0 else {
                throw AIEngineError.decodeFailed(nextResult)
            }
        }

        return result
    }

    // MARK: - Private: Tokenization

    private func tokenize(
        text: String,
        vocab: OpaquePointer?,
        addBos: Bool
    ) throws -> [llama_token] {
        guard let vocab else {
            throw AIEngineError.tokenizationFailed
        }

        let utf8Count = text.utf8.count
        let maxTokens = Int32(utf8Count) + (addBos ? 1 : 0)

        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = text.withCString { cStr in
            llama_tokenize(
                vocab,
                cStr,
                Int32(utf8Count),
                &tokens,
                maxTokens,
                addBos,
                true  // special tokens
            )
        }

        guard nTokens >= 0 else {
            throw AIEngineError.tokenizationFailed
        }

        tokens.removeSubrange(Int(nTokens)...)
        return tokens
    }

    private func tokenToPiece(
        token: llama_token,
        vocab: OpaquePointer?
    ) -> String {
        guard let vocab else { return "" }

        var buffer = [CChar](repeating: 0, count: 128)
        let nBytes = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)

        if nBytes < 0 {
            // Buffer too small — retry with correct size
            var largerBuffer = [CChar](repeating: 0, count: Int(-nBytes) + 1)
            let retryBytes = llama_token_to_piece(vocab, token, &largerBuffer, Int32(largerBuffer.count), 0, true)
            guard retryBytes > 0 else { return "" }
            return String(decoding: largerBuffer.prefix(Int(retryBytes)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        guard nBytes > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(nBytes)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Private: Sampler

    private func createSamplerChain() -> UnsafeMutablePointer<llama_sampler>? {
        let chainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(chainParams) else {
            return nil
        }

        // Temperature → Top-K → Top-P → distribution sampler
        llama_sampler_chain_add(chain, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(config.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        return chain
    }

    // MARK: - Private: Cleanup

    private func cleanupResources() {
        if let samplerChain {
            llama_sampler_free(samplerChain)
            self.samplerChain = nil
        }
        if let ctx {
            llama_free(ctx)
            self.ctx = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        _modelPath = nil
    }
}
