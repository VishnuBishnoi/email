import Foundation

/// Generates embeddings for search queries and email content.
///
/// Wraps the AI engine's `embed()` method with proper fallback behavior.
/// When the engine is unavailable or embedding fails, returns nil so the
/// caller can fall back to FTS5-only search.
///
/// All returned vectors are L2-normalized to enable cosine similarity
/// via simple dot product.
///
/// Expected embedding dimension: 384 (all-MiniLM-L6-v2).
///
/// Spec ref: FR-SEARCH-07, AC-S-06, AC-S-08
public enum GenerateEmbeddingUseCase: Sendable {

    // MARK: - Public API

    /// Generate an embedding vector for a single search query or text.
    ///
    /// Returns nil if the engine is unavailable or `embed()` throws,
    /// enabling graceful FTS5-only fallback (spec AC-S-08).
    ///
    /// - Parameters:
    ///   - text: The text to embed (search query or email content).
    ///   - engine: The AI engine to use for embedding generation.
    /// - Returns: An L2-normalized float vector, or nil on failure.
    ///
    /// Spec ref: FR-SEARCH-07, AC-S-06
    public static func embedQuery(
        text: String,
        using engine: any AIEngineProtocol
    ) async -> [Float]? {
        guard await engine.isAvailable() else {
            return nil
        }

        do {
            let vector = try await engine.embed(text: text)
            guard !vector.isEmpty else { return nil }
            return normalize(vector)
        } catch {
            return nil
        }
    }

    /// Generate embeddings for multiple texts.
    ///
    /// Each element in the returned array corresponds to the input text
    /// at the same index. Elements are nil if that particular embedding
    /// failed, allowing partial success across the batch.
    ///
    /// - Parameters:
    ///   - texts: The texts to embed.
    ///   - engine: The AI engine to use for embedding generation.
    /// - Returns: An array of optional L2-normalized float vectors.
    ///
    /// Spec ref: FR-SEARCH-07, AC-S-06, AC-S-08
    public static func embedBatch(
        texts: [String],
        using engine: any AIEngineProtocol
    ) async -> [[Float]?] {
        guard await engine.isAvailable() else {
            return Array(repeating: nil, count: texts.count)
        }

        var results: [[Float]?] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            do {
                let vector = try await engine.embed(text: text)
                if vector.isEmpty {
                    results.append(nil)
                } else {
                    results.append(normalize(vector))
                }
            } catch {
                results.append(nil)
            }
        }

        return results
    }

    // MARK: - Normalization

    /// L2-normalize a float vector to unit length.
    ///
    /// After normalization, the vector's L2 norm equals 1.0, enabling
    /// cosine similarity computation via simple dot product.
    ///
    /// Returns the zero vector unchanged (avoids division by zero).
    ///
    /// - Parameter vector: The input float vector.
    /// - Returns: The L2-normalized vector.
    public static func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
