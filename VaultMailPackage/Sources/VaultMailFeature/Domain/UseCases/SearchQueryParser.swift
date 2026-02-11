import Foundation

/// Parses natural language search queries into structured SearchQuery objects.
///
/// Extracts sender, date range, attachment, category, and read status filters
/// from natural language input. Remaining text becomes the free-text query
/// for FTS5 and semantic search.
///
/// Performance target: <5ms per parse.
///
/// Spec ref: FR-SEARCH-04
public enum SearchQueryParser: Sendable {

    // MARK: - Public API

    /// Parse a natural language query into a structured SearchQuery.
    ///
    /// Filters are extracted in a fixed order (sender, date, attachment, category,
    /// read status). Remaining text after filter extraction becomes the free-text
    /// query for full-text and semantic search.
    ///
    /// Examples:
    /// - "from john last week with attachments" -> sender: "john", dateRange: last 7 days, hasAttachment: true, text: ""
    /// - "budget report from sarah" -> sender: "sarah", text: "budget report"
    /// - "unread promotions from john" -> sender: "john", category: .promotions, isRead: false, text: ""
    ///
    /// Spec ref: FR-SEARCH-04
    public static func parse(_ rawQuery: String, scope: SearchScope = .allMail) -> SearchQuery {
        guard !rawQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SearchQuery(text: "", filters: SearchFilters(), scope: scope)
        }

        var remaining = rawQuery
        var filters = SearchFilters()

        // Extract filters in specified order
        filters.sender = extractSender(&remaining)
        filters.folder = extractFolder(&remaining)
        filters.dateRange = extractDateRange(&remaining)
        filters.hasAttachment = extractAttachmentFilter(&remaining)
        filters.category = extractCategory(&remaining)
        filters.isRead = extractReadStatus(&remaining)

        // Clean up remaining text
        let text = collapseWhitespace(remaining)

        return SearchQuery(text: text, filters: filters, scope: scope)
    }

    // MARK: - Sender Extraction

    /// Extract sender filter from the query.
    ///
    /// Matches "from user@example.com" or "from name" patterns.
    /// Email addresses take priority over plain names.
    ///
    /// Spec ref: FR-SEARCH-04 (sender filter)
    private static func extractSender(_ query: inout String) -> String? {
        // Try email address pattern first: from user@example.com
        if let emailRegex = try? Regex<(Substring, Substring)>(
            #"(?i)from\s+(\S+@\S+)"#
        ),
            let match = query.firstMatch(of: emailRegex) {
            let sender = String(match.output.1)
            query = query.replacingOccurrences(
                of: String(match.output.0),
                with: ""
            )
            return sender
        }

        // Try name pattern: from <name> followed by a known keyword boundary or end-of-string
        let namePattern = #"(?i)from\s+([a-zA-Z][a-zA-Z0-9\s]*?)(?:\s+(?:last|yesterday|today|this|before|after|in|with|has|unread|read|promotions?|social|updates?|forums?|primary)\b|\s*$)"#
        if let nameRegex = try? Regex<(Substring, Substring)>(namePattern),
           let match = query.firstMatch(of: nameRegex) {
            let sender = String(match.output.1).trimmingCharacters(in: .whitespaces)
            // Only remove the "from <name>" portion, not the boundary keyword
            let fromNamePattern = #"(?i)from\s+"# + Regex.escape(sender)
            if let removeRegex = try? Regex<Substring>(fromNamePattern),
               let removeMatch = query.firstMatch(of: removeRegex) {
                query.replaceSubrange(removeMatch.range, with: "")
            }
            return sender
        }

        return nil
    }

    // MARK: - Folder Extraction

    /// Extract folder filter from the query.
    ///
    /// Supports patterns like "in:inbox", "in:sent", "in:drafts",
    /// "in:trash", "folder:archive".
    private static func extractFolder(_ query: inout String) -> String? {
        let pattern = #"(?i)(?:in|folder)\s*:\s*(\S+)"#
        guard let regex = try? Regex<(Substring, Substring)>(pattern),
              let match = query.firstMatch(of: regex) else {
            return nil
        }
        let folder = String(match.output.1)
        query.replaceSubrange(match.range, with: "")
        return folder
    }

    // MARK: - Date Range Extraction

    /// Extract date range filter from the query.
    ///
    /// Supports relative dates (yesterday, today, last week, this week,
    /// last month, this month) and month-based patterns (before/after/in MONTH).
    ///
    /// Spec ref: FR-SEARCH-04 (date range filter)
    private static func extractDateRange(_ query: inout String) -> DateRange? {
        let calendar = Calendar.current
        let now = Date()

        // Check patterns in specified order
        if removePattern(&query, pattern: #"(?i)\byesterday\b"#) {
            let startOfYesterday = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -1, to: now)!
            )
            let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday)!
            return DateRange(start: startOfYesterday, end: endOfYesterday)
        }

        if removePattern(&query, pattern: #"(?i)\btoday\b"#) {
            let startOfToday = calendar.startOfDay(for: now)
            return DateRange(start: startOfToday, end: now)
        }

        if removePattern(&query, pattern: #"(?i)\blast\s+week\b"#) {
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return DateRange(start: calendar.startOfDay(for: sevenDaysAgo), end: now)
        }

        if removePattern(&query, pattern: #"(?i)\bthis\s+week\b"#) {
            let startOfWeek = startOfCurrentWeek(calendar: calendar, now: now)
            return DateRange(start: startOfWeek, end: now)
        }

        if removePattern(&query, pattern: #"(?i)\blast\s+month\b"#) {
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
            return DateRange(start: calendar.startOfDay(for: thirtyDaysAgo), end: now)
        }

        if removePattern(&query, pattern: #"(?i)\bthis\s+month\b"#) {
            let components = calendar.dateComponents([.year, .month], from: now)
            if let startOfMonth = calendar.date(from: components) {
                return DateRange(start: startOfMonth, end: now)
            }
        }

        // "before MONTH" -> from distant past to start of that month
        if let month = extractMonthPattern(&query, prefix: "before") {
            let monthStart = resolveMonthStart(month: month, calendar: calendar, now: now)
            let distantPast = calendar.date(byAdding: .year, value: -10, to: now)!
            return DateRange(start: distantPast, end: monthStart)
        }

        // "after MONTH" -> from start of that month to now
        if let month = extractMonthPattern(&query, prefix: "after") {
            let monthStart = resolveMonthStart(month: month, calendar: calendar, now: now)
            return DateRange(start: monthStart, end: now)
        }

        // "in MONTH" -> start to end of that month
        if let month = extractMonthPattern(&query, prefix: "in") {
            let monthStart = resolveMonthStart(month: month, calendar: calendar, now: now)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return DateRange(start: monthStart, end: monthEnd)
        }

        return nil
    }

    // MARK: - Attachment Filter Extraction

    /// Extract attachment filter from the query.
    ///
    /// Matches "with attachments", "has attachment", "with files" and variations.
    ///
    /// Spec ref: FR-SEARCH-04 (attachment filter)
    private static func extractAttachmentFilter(_ query: inout String) -> Bool? {
        let pattern = #"(?i)\b(?:with\s+(?:attachments?|files)|has\s+attachments?)\b"#
        if removePattern(&query, pattern: pattern) {
            return true
        }
        return nil
    }

    // MARK: - Category Filter Extraction

    /// Extract AI category filter from the query.
    ///
    /// Matches category names like "promotions", "social", "updates", "forums", "primary".
    ///
    /// Spec ref: FR-SEARCH-04 (category filter)
    private static func extractCategory(_ query: inout String) -> AICategory? {
        // Order matters: check longer patterns first to avoid partial matches.
        // "social emails" before "social", "update emails" before "updates", etc.
        let categoryPatterns: [(String, AICategory)] = [
            (#"(?i)\bsocial\s+emails?\b"#, .social),
            (#"(?i)\bupdate\s+emails?\b"#, .updates),
            (#"(?i)\bpromotions?\b"#, .promotions),
            (#"(?i)\bsocial\b"#, .social),
            (#"(?i)\bupdates?\b"#, .updates),
            (#"(?i)\bforums?\b"#, .forums),
            (#"(?i)\bprimary\b"#, .primary),
        ]

        for (pattern, category) in categoryPatterns {
            if removePattern(&query, pattern: pattern) {
                return category
            }
        }

        return nil
    }

    // MARK: - Read Status Extraction

    /// Extract read status filter from the query.
    ///
    /// Matches standalone "unread" or "read" (not part of another word).
    ///
    /// Spec ref: FR-SEARCH-04 (read status filter)
    private static func extractReadStatus(_ query: inout String) -> Bool? {
        // Check "unread" first (more specific, avoids "read" matching inside "unread")
        if removePattern(&query, pattern: #"(?i)\bunread\b"#) {
            return false
        }
        if removePattern(&query, pattern: #"(?i)\bread\b"#) {
            return true
        }
        return nil
    }

    // MARK: - Helpers

    /// Remove a regex pattern from the query string, returning whether it was found.
    @discardableResult
    private static func removePattern(_ query: inout String, pattern: String) -> Bool {
        guard let regex = try? Regex<Substring>(pattern),
              let match = query.firstMatch(of: regex) else {
            return false
        }
        query.replaceSubrange(match.range, with: "")
        return true
    }

    /// Extract a month name following a prefix keyword (e.g., "before March").
    /// Removes the matched pattern from the query and returns the month number (1-12).
    private static func extractMonthPattern(_ query: inout String, prefix: String) -> Int? {
        let pattern = #"(?i)\b"# + prefix + #"\s+("# + monthNamesPattern + #")\b"#
        guard let regex = try? Regex<(Substring, Substring)>(pattern),
              let match = query.firstMatch(of: regex) else {
            return nil
        }
        let monthName = String(match.output.1).lowercased()
        query.replaceSubrange(match.range, with: "")
        return monthNumber(from: monthName)
    }

    /// Regex alternation pattern for month names.
    private static let monthNamesPattern =
        "january|february|march|april|may|june|july|august|september|october|november|december"
        + "|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec"

    /// Convert a month name string to its number (1-12).
    private static func monthNumber(from name: String) -> Int? {
        let map: [String: Int] = [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12,
        ]
        return map[name]
    }

    /// Resolve a month number to the start of that month in the current or previous year.
    ///
    /// If the month hasn't occurred yet this year, uses the previous year.
    private static func resolveMonthStart(month: Int, calendar: Calendar, now: Date) -> Date {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        // If the month hasn't occurred yet this year, use last year
        let year = month > currentMonth ? currentYear - 1 : currentYear

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0

        return calendar.date(from: components) ?? now
    }

    /// Get the start of the current calendar week.
    private static func startOfCurrentWeek(calendar: Calendar, now: Date) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = calendar.firstWeekday
        return calendar.date(from: components) ?? calendar.startOfDay(for: now)
    }

    /// Collapse multiple spaces and trim whitespace from a string.
    private static func collapseWhitespace(_ string: String) -> String {
        string
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Regex Utility

private extension Regex where Output == Substring {
    /// Escape special regex characters in a string for literal matching.
    static func escape(_ string: String) -> String {
        let specialCharacters = #"\.+*?^${}()|[]"#
        var escaped = ""
        for char in string {
            if specialCharacters.contains(char) {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        return escaped
    }
}
