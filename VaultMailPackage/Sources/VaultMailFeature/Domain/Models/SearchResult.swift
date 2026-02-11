import Foundation

/// Lightweight search result for display.
///
/// This is a value type carrying only display data. It does NOT embed @Model objects
/// (Thread, Email) which are ModelContext-bound and not safely Sendable across
/// concurrency boundaries. The view layer fetches full @Model objects on @MainActor
/// via the threadId/emailId when navigation is needed.
///
/// Spec ref: Section 6.4
public struct SearchResult: Identifiable, Sendable {
    /// Thread ID (used as Identifiable id)
    public let id: String
    /// Thread ID for navigation
    public let threadId: String
    /// Email ID of the best matching email in the thread
    public let emailId: String
    /// Email subject
    public let subject: String
    /// Sender display name
    public let senderName: String
    /// Sender email address
    public let senderEmail: String
    /// Email date
    public let date: Date
    /// Body snippet with match context
    public let snippet: String
    /// Ranges for keyword highlighting in subject
    public let highlightRanges: [HighlightRange]
    /// Whether the email has attachments
    public let hasAttachment: Bool
    /// RRF fusion score (higher = better match)
    public let score: Double
    /// Source of the match
    public let matchSource: MatchSource
    /// Account ID for multi-account display
    public let accountId: String
    /// Whether the email has been read
    public let isRead: Bool

    public init(
        id: String,
        threadId: String,
        emailId: String,
        subject: String,
        senderName: String,
        senderEmail: String,
        date: Date,
        snippet: String,
        highlightRanges: [HighlightRange] = [],
        hasAttachment: Bool = false,
        score: Double = 0,
        matchSource: MatchSource = .keyword,
        accountId: String,
        isRead: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.emailId = emailId
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.date = date
        self.snippet = snippet
        self.highlightRanges = highlightRanges
        self.hasAttachment = hasAttachment
        self.score = score
        self.matchSource = matchSource
        self.accountId = accountId
        self.isRead = isRead
    }
}

/// A highlight range in text (Sendable alternative to Range<String.Index>).
public struct HighlightRange: Sendable, Equatable {
    /// Start position (UTF-16 offset)
    public let start: Int
    /// Length (UTF-16 count)
    public let length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }
}

/// Source of a search match.
///
/// Spec ref: Section 6.4
public enum MatchSource: Sendable, Equatable {
    /// Matched via FTS5 keyword search
    case keyword
    /// Matched via semantic embedding search
    case semantic
    /// Matched by both keyword and semantic search
    case both
}
