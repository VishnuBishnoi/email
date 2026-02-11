import Accelerate
import Foundation

// MARK: - Supporting Types

/// A lightweight entry for bulk-loading vectors into ``VectorSearchEngine``.
///
/// Spec ref: FR-SEARCH-07
public struct VectorEntry: Sendable {
    /// The unique identifier of the email this embedding belongs to.
    public let emailId: String
    /// Pre-L2-normalized embedding vector (typically 384 dimensions).
    public let embedding: [Float]

    public init(emailId: String, embedding: [Float]) {
        self.emailId = emailId
        self.embedding = embedding
    }
}

/// A single result from a vector similarity search.
///
/// Spec ref: FR-SEARCH-07
public struct VectorSearchResult: Sendable {
    /// The unique identifier of the matched email.
    public let emailId: String
    /// Cosine similarity score (dot product of L2-normalized vectors).
    /// Range: -1.0 (opposite) to 1.0 (identical).
    public let similarity: Double

    public init(emailId: String, similarity: Double) {
        self.emailId = emailId
        self.similarity = similarity
    }
}

// MARK: - VectorSearchEngine

/// In-memory vector search engine for semantic email similarity.
///
/// Performs brute-force dot-product search over pre-L2-normalized embeddings.
/// Because the vectors are L2-normalized, the dot product equals cosine
/// similarity, avoiding the overhead of per-query normalization.
///
/// This actor is intentionally **not** `@MainActor` -- all computation runs
/// on a background executor so the main thread is never blocked.
///
/// Spec ref: FR-SEARCH-07
public actor VectorSearchEngine {

    // MARK: - State

    /// Stored vectors indexed for brute-force search.
    private var vectors: [(emailId: String, embedding: [Float])] = []

    // MARK: - Init

    public init() {}

    // MARK: - Loading

    /// Replaces all stored vectors with the provided entries.
    ///
    /// Any entries whose embedding has zero length are silently skipped.
    ///
    /// - Parameter entries: Pre-extracted ``VectorEntry`` values to load.
    public func loadVectors(from entries: [VectorEntry]) {
        vectors = entries
            .filter { !$0.embedding.isEmpty }
            .map { (emailId: $0.emailId, embedding: $0.embedding) }
    }

    /// Adds a single vector to the in-memory corpus.
    ///
    /// If an entry with the same `emailId` already exists, it is replaced.
    ///
    /// - Parameters:
    ///   - emailId: Unique identifier of the email.
    ///   - embedding: Pre-L2-normalized embedding vector.
    public func addVector(emailId: String, embedding: [Float]) {
        // Remove existing entry to avoid duplicates.
        vectors.removeAll { $0.emailId == emailId }
        vectors.append((emailId: emailId, embedding: embedding))
    }

    /// Removes the vector associated with the given email ID.
    ///
    /// No-op if the email ID is not in the corpus.
    ///
    /// - Parameter emailId: Identifier of the email to remove.
    public func removeVector(emailId: String) {
        vectors.removeAll { $0.emailId == emailId }
    }

    /// Removes all vectors from the in-memory corpus.
    public func removeAll() {
        vectors.removeAll()
    }

    // MARK: - Search

    /// Searches for the most similar vectors to the given query.
    ///
    /// Uses brute-force dot product via the Accelerate framework (`vDSP_dotpr`)
    /// for performance. Entries whose embedding dimension does not match the
    /// query dimension are silently skipped.
    ///
    /// - Parameters:
    ///   - query: Pre-L2-normalized query embedding vector.
    ///   - limit: Maximum number of results to return. Defaults to 50.
    /// - Returns: Top results sorted by similarity (descending).
    public func search(query: [Float], limit: Int = 50) -> [VectorSearchResult] {
        guard !query.isEmpty, !vectors.isEmpty else { return [] }

        let queryCount = query.count

        var results: [(emailId: String, similarity: Double)] = []
        results.reserveCapacity(vectors.count)

        for entry in vectors {
            // Skip dimension mismatches.
            guard entry.embedding.count == queryCount else { continue }

            var dotProduct: Float = 0
            vDSP_dotpr(
                entry.embedding, 1,
                query, 1,
                &dotProduct,
                vDSP_Length(queryCount)
            )

            results.append((emailId: entry.emailId, similarity: Double(dotProduct)))
        }

        // Sort by similarity descending, then take the top `limit`.
        results.sort { $0.similarity > $1.similarity }

        let topResults = results.prefix(limit)
        return topResults.map {
            VectorSearchResult(emailId: $0.emailId, similarity: $0.similarity)
        }
    }

    // MARK: - Accessors

    /// The number of vectors currently stored in memory.
    public var count: Int {
        vectors.count
    }
}
