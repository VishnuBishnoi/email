import Foundation

/// Errors thrown by AI engine operations.
///
/// These errors represent failures in the on-device AI inference pipeline.
/// Use cases catch these and return graceful defaults (empty arrays, nil, etc.)
/// per FR-ED-02.
public enum AIEngineError: Error, Sendable, LocalizedError {
    /// No GGUF model file found at the expected path.
    case modelNotFound(path: String)
    /// Model file failed SHA-256 integrity verification.
    case integrityCheckFailed(expected: String, actual: String)
    /// llama.cpp failed to load the model (corrupt file, unsupported format, etc.).
    case modelLoadFailed(String)
    /// llama.cpp failed to create a context for inference.
    case contextCreationFailed
    /// Tokenization of the input prompt failed.
    case tokenizationFailed
    /// The decode (forward pass) step failed.
    case decodeFailed(Int32)
    /// No categories provided for classification.
    case noCategories
    /// The model is not loaded or the engine is unavailable.
    case engineUnavailable
    /// Insufficient device RAM to load the requested model.
    case insufficientMemory(required: UInt64, available: UInt64)
    /// Model download failed.
    case downloadFailed(Error)
    /// Model download was cancelled by the user.
    case downloadCancelled
    /// Classification response didn't match any provided categories.
    case classificationFailed(response: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            "AI model not found at \(path)"
        case .integrityCheckFailed(let expected, let actual):
            "Model integrity check failed: expected \(expected.prefix(8))…, got \(actual.prefix(8))…"
        case .modelLoadFailed(let reason):
            "Failed to load AI model: \(reason)"
        case .contextCreationFailed:
            "Failed to create AI inference context"
        case .tokenizationFailed:
            "Failed to tokenize input text"
        case .decodeFailed(let code):
            "AI inference decode failed with code \(code)"
        case .noCategories:
            "No categories provided for classification"
        case .engineUnavailable:
            "AI engine is not available"
        case .insufficientMemory(let required, let available):
            "Insufficient memory: \(required / 1_048_576) MB required, \(available / 1_048_576) MB available"
        case .downloadFailed(let error):
            "Model download failed: \(error.localizedDescription)"
        case .downloadCancelled:
            "Model download was cancelled"
        case .classificationFailed(let response):
            "Classification failed: LLM response '\(response.prefix(50))' didn't match any category"
        }
    }
}
