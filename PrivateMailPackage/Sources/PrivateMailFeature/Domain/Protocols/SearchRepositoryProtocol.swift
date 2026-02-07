import Foundation

/// Repository protocol for semantic search operations.
///
/// Combines full-text search with AI-powered embedding-based search.
///
/// Spec ref: Foundation spec Section 6
public protocol SearchRepositoryProtocol: Sendable {
    /// Search emails by query string (full-text + semantic).
    func search(query: String, accountId: String) async throws -> [SearchIndex]
    /// Index an email for future search.
    func indexEmail(emailId: String, content: String, embedding: Data?) async throws
    /// Remove an email from the search index.
    func removeFromIndex(emailId: String) async throws
}
