import Foundation
import SwiftData

/// Search index entry for semantic search via AI embeddings.
///
/// Stores email ID, account ID, indexed text content, and the AI-generated
/// embedding vector. Lifecycle is managed at the repository layer — entries
/// are deleted when the email or account is deleted (no direct SwiftData
/// relationship to avoid circular dependency issues).
///
/// The `accountId` field enables account-scoped search queries and bulk
/// deletion when an account is removed.
///
/// Spec ref: Search spec Section 6.1, FR-SEARCH-08
@Model
public final class SearchIndex {
    /// Email ID this index entry belongs to
    public var emailId: String
    /// Account ID for account-scoped queries and bulk deletion.
    /// Default empty string for lightweight SwiftData migration — backfilled on first launch.
    public var accountId: String = ""
    /// Indexed text content (subject + body + sender)
    public var content: String
    /// AI-generated embedding vector (384-dim Float32, pre-L2-normalized, 1536 bytes).
    /// Nil when CoreML embedding model is unavailable.
    public var embedding: Data?

    public init(
        emailId: String,
        accountId: String = "",
        content: String,
        embedding: Data? = nil
    ) {
        self.emailId = emailId
        self.accountId = accountId
        self.content = content
        self.embedding = embedding
    }
}
