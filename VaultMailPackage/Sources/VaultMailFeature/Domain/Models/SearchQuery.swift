import Foundation

/// Parsed search query with extracted structured filters.
///
/// Spec ref: FR-SEARCH-04 (NL query parsing), Section 6.3
public struct SearchQuery: Sendable {
    /// Free-text query (remaining after filter extraction)
    public var text: String
    /// Structured filters extracted from natural language
    public var filters: SearchFilters
    /// Search scope (all mail or current folder)
    public var scope: SearchScope

    public init(text: String = "", filters: SearchFilters = SearchFilters(), scope: SearchScope = .allMail) {
        self.text = text
        self.filters = filters
        self.scope = scope
    }
}

/// Structured search filters.
///
/// All filters are optional. When multiple are set, they combine with AND logic.
/// Spec ref: FR-SEARCH-02
public struct SearchFilters: Sendable, Equatable {
    /// Filter by sender email or display name
    public var sender: String?
    /// Filter by date range
    public var dateRange: DateRange?
    /// Filter by attachment presence
    public var hasAttachment: Bool?
    /// Filter to specific folder ID
    public var folder: String?
    /// Filter by AI category
    public var category: AICategory?
    /// Filter by read status
    public var isRead: Bool?

    public init(
        sender: String? = nil,
        dateRange: DateRange? = nil,
        hasAttachment: Bool? = nil,
        folder: String? = nil,
        category: AICategory? = nil,
        isRead: Bool? = nil
    ) {
        self.sender = sender
        self.dateRange = dateRange
        self.hasAttachment = hasAttachment
        self.folder = folder
        self.category = category
        self.isRead = isRead
    }

    /// Whether any filter is active
    public var hasActiveFilters: Bool {
        sender != nil || dateRange != nil || hasAttachment != nil ||
        folder != nil || category != nil || isRead != nil
    }
}

/// Date range for filtering.
public struct DateRange: Sendable, Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Search scope.
///
/// Spec ref: FR-SEARCH-03
public enum SearchScope: Sendable, Equatable, Hashable {
    /// Search across all folders and accounts
    case allMail
    /// Search within a specific folder
    case currentFolder(folderId: String)
}
