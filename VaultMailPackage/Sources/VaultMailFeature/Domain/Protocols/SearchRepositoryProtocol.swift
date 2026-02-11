import Foundation

/// Repository protocol for hybrid search operations.
///
/// Combines FTS5 full-text search with semantic embedding search
/// via Reciprocal Rank Fusion (RRF).
///
/// Spec ref: FR-SEARCH-05, FR-SEARCH-06, FR-SEARCH-07
public protocol SearchRepositoryProtocol: Sendable {
    /// Execute a hybrid search combining keyword and semantic results.
    ///
    /// - Parameters:
    ///   - query: Parsed search query with text and structured filters.
    ///   - engine: AI engine for query embedding (nil = keyword-only).
    /// - Returns: Array of search results sorted by relevance score.
    @MainActor func searchEmails(query: SearchQuery, engine: (any AIEngineProtocol)?) async throws -> [SearchResult]
}
