import Foundation

/// Repository protocol for local AI operations (llama.cpp).
///
/// All AI inference runs on-device. No user data leaves the device (P-02).
///
/// Spec ref: Foundation spec Section 6
public protocol AIRepositoryProtocol: Sendable {
    /// Categorize an email into an AICategory.
    func categorize(email: Email) async throws -> AICategory
    /// Generate a summary for a thread.
    func summarize(thread: Thread) async throws -> String
    /// Generate smart reply suggestions for an email.
    func smartReply(email: Email) async throws -> [String]
    /// Generate an embedding vector for search indexing.
    func generateEmbedding(text: String) async throws -> Data
}
