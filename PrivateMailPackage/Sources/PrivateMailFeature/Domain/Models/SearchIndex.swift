import Foundation
import SwiftData

/// Search index entry for semantic search via AI embeddings.
///
/// Lifecycle is tied to the parent email — entries are deleted when the
/// email is deleted. Managed at the repository layer (no direct SwiftData
/// relationship to avoid circular dependency issues).
///
/// Spec ref: Foundation spec Section 5.1
@Model
public final class SearchIndex {
    /// Email ID this index entry belongs to
    public var emailId: String
    /// Indexed text content (subject + body + sender)
    public var content: String
    /// AI-generated embedding vector (binary blob)
    public var embedding: Data?

    public init(
        emailId: String,
        content: String,
        embedding: Data? = nil
    ) {
        self.emailId = emailId
        self.content = content
        self.embedding = embedding
    }
}
