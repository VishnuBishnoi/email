import Foundation
import SwiftData

/// A conversation thread grouping related emails.
///
/// Thread belongs to an Account via `accountId` stored field (not a relationship)
/// to avoid double-cascade through Account→Folder→Email→Thread.
///
/// Multi-value field serialization (Section 5.6):
/// - `participants`: JSON array of objects `[{"name": "Alice", "email": "alice@example.com"}]`
///
/// Spec ref: Foundation spec Section 5.1
@Model
public final class Thread {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Account ID this thread belongs to (stored field, not relationship)
    public var accountId: String
    /// Thread subject line
    public var subject: String
    /// Date of the most recent email in the thread
    public var latestDate: Date?
    /// Number of messages in the thread
    public var messageCount: Int
    /// Number of unread messages in the thread
    public var unreadCount: Int
    /// Whether any email in the thread is starred
    public var isStarred: Bool
    /// AI-assigned category for the thread (raw value of AICategory)
    public var aiCategory: String?
    /// AI-generated thread summary
    public var aiSummary: String?
    /// Preview snippet from the latest email
    public var snippet: String?
    /// Thread participants (JSON array of objects per Section 5.6)
    public var participants: String?

    /// Emails in this thread.
    /// Cascade: deleting a Thread deletes all its Emails.
    @Relationship(deleteRule: .cascade, inverse: \Email.thread)
    public var emails: [Email]

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        subject: String,
        latestDate: Date? = nil,
        messageCount: Int = 0,
        unreadCount: Int = 0,
        isStarred: Bool = false,
        aiCategory: String? = nil,
        aiSummary: String? = nil,
        snippet: String? = nil,
        participants: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.subject = subject
        self.latestDate = latestDate
        self.messageCount = messageCount
        self.unreadCount = unreadCount
        self.isStarred = isStarred
        self.aiCategory = aiCategory
        self.aiSummary = aiSummary
        self.snippet = snippet
        self.participants = participants
        self.emails = []
    }
}
