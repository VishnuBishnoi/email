import Testing
import Foundation
@testable import VaultMailFeature

@Suite("SearchQueryParser")
struct SearchQueryParserTests {

    // MARK: - Empty & Plain Text Queries

    @Test("Empty query returns empty text with no filters")
    func emptyQuery() {
        let result = SearchQueryParser.parse("")
        #expect(result.text == "")
        #expect(result.filters.sender == nil)
        #expect(result.filters.dateRange == nil)
        #expect(result.filters.hasAttachment == nil)
        #expect(result.filters.folder == nil)
        #expect(result.filters.category == nil)
        #expect(result.filters.isRead == nil)
        #expect(!result.filters.hasActiveFilters)
    }

    @Test("Whitespace-only query returns empty text with no filters")
    func whitespaceOnlyQuery() {
        let result = SearchQueryParser.parse("   ")
        #expect(result.text == "")
        #expect(!result.filters.hasActiveFilters)
    }

    @Test("Plain text query passes through without filters")
    func plainTextQuery() {
        let result = SearchQueryParser.parse("budget report")
        #expect(result.text == "budget report")
        #expect(!result.filters.hasActiveFilters)
    }

    // MARK: - Sender Extraction

    @Test("Extracts sender email address from 'from user@example.com'")
    func senderWithEmailAddress() {
        let result = SearchQueryParser.parse("from user@example.com project")
        #expect(result.filters.sender == "user@example.com")
        #expect(result.text == "project")
    }

    @Test("Extracts sender name from 'from john' followed by keyword boundary")
    func senderWithName() {
        let result = SearchQueryParser.parse("from john last week")
        #expect(result.filters.sender == "john")
        #expect(result.filters.dateRange != nil)
        #expect(result.text == "")
    }

    @Test("Extracts sender name at end of string")
    func senderNameAtEndOfString() {
        let result = SearchQueryParser.parse("from sarah")
        #expect(result.filters.sender == "sarah")
        #expect(result.text == "")
    }

    @Test("Sender extraction with text before 'from'")
    func senderWithPrecedingText() {
        let result = SearchQueryParser.parse("budget report from sarah")
        #expect(result.filters.sender == "sarah")
        #expect(result.text == "budget report")
    }

    // MARK: - Date Range: Yesterday

    @Test("'yesterday' extracts date range covering yesterday")
    func yesterdayDateRange() throws {
        let result = SearchQueryParser.parse("yesterday invoices")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let expectedStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: now)!
        )

        // Start should be start-of-day yesterday
        #expect(abs(range.start.timeIntervalSince(expectedStart)) < 2)
        // End should be start-of-day today (one day after yesterday start)
        #expect(range.end > range.start)
        #expect(range.end.timeIntervalSince(range.start) < 86401) // ~24 hours
        #expect(result.text == "invoices")
    }

    // MARK: - Date Range: Today

    @Test("'today' extracts date range from start of today to now")
    func todayDateRange() throws {
        let result = SearchQueryParser.parse("today meeting")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let expectedStart = calendar.startOfDay(for: now)

        #expect(abs(range.start.timeIntervalSince(expectedStart)) < 2)
        #expect(range.end >= range.start)
        // End should be close to now (within a few seconds of parse time)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(result.text == "meeting")
    }

    // MARK: - Date Range: Last Week

    @Test("'last week' extracts date range covering past 7 days")
    func lastWeekDateRange() throws {
        let result = SearchQueryParser.parse("last week reports")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let expectedStart = calendar.startOfDay(for: sevenDaysAgo)

        #expect(abs(range.start.timeIntervalSince(expectedStart)) < 2)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(range.start < range.end)
        #expect(result.text == "reports")
    }

    // MARK: - Date Range: This Week

    @Test("'this week' extracts date range from start of current week to now")
    func thisWeekDateRange() throws {
        let result = SearchQueryParser.parse("this week updates")
        let range = try #require(result.filters.dateRange)

        let now = Date()
        // Start should be on or before today
        #expect(range.start <= now)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(range.start < range.end)
        // The start should be within the past 7 days at most
        #expect(now.timeIntervalSince(range.start) <= 7 * 86400 + 1)
        #expect(result.text == "")
    }

    // MARK: - Date Range: Last Month

    @Test("'last month' extracts date range covering past 30 days")
    func lastMonthDateRange() throws {
        let result = SearchQueryParser.parse("last month expenses")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let expectedStart = calendar.startOfDay(for: thirtyDaysAgo)

        #expect(abs(range.start.timeIntervalSince(expectedStart)) < 2)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(result.text == "expenses")
    }

    // MARK: - Date Range: This Month

    @Test("'this month' extracts date range from start of current month to now")
    func thisMonthDateRange() throws {
        let result = SearchQueryParser.parse("this month summary")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let expectedStart = calendar.date(from: components)!

        #expect(abs(range.start.timeIntervalSince(expectedStart)) < 2)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(result.text == "summary")
    }

    // MARK: - Attachment Filter

    @Test("'with attachments' sets hasAttachment to true")
    func withAttachments() {
        let result = SearchQueryParser.parse("with attachments")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "")
    }

    @Test("'has attachment' sets hasAttachment to true")
    func hasAttachment() {
        let result = SearchQueryParser.parse("has attachment important")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "important")
    }

    @Test("'with files' sets hasAttachment to true")
    func withFiles() {
        let result = SearchQueryParser.parse("with files contract")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "contract")
    }

    // MARK: - Category Filter

    @Test("'promotions' extracts category filter")
    func promotionsCategory() {
        let result = SearchQueryParser.parse("promotions deals")
        #expect(result.filters.category == .promotions)
        #expect(result.text == "deals")
    }

    @Test("'social' extracts category filter")
    func socialCategory() {
        let result = SearchQueryParser.parse("social notifications")
        #expect(result.filters.category == .social)
        #expect(result.text == "notifications")
    }

    @Test("'forums' extracts category filter")
    func forumsCategory() {
        let result = SearchQueryParser.parse("forums discussion")
        #expect(result.filters.category == .forums)
        #expect(result.text == "discussion")
    }

    @Test("'primary' extracts category filter")
    func primaryCategory() {
        let result = SearchQueryParser.parse("primary messages")
        #expect(result.filters.category == .primary)
        #expect(result.text == "messages")
    }

    @Test("'updates' extracts category filter")
    func updatesCategory() {
        let result = SearchQueryParser.parse("updates billing")
        #expect(result.filters.category == .updates)
        #expect(result.text == "billing")
    }

    // MARK: - Read Status

    @Test("'unread' sets isRead to false")
    func unreadStatus() {
        let result = SearchQueryParser.parse("unread from sarah")
        #expect(result.filters.isRead == false)
        #expect(result.filters.sender == "sarah")
        #expect(result.text == "")
    }

    @Test("'read' sets isRead to true")
    func readStatus() {
        let result = SearchQueryParser.parse("read invoices")
        #expect(result.filters.isRead == true)
        #expect(result.text == "invoices")
    }

    // MARK: - Combined Filters

    @Test("Multiple filters combine: sender + date + attachment")
    func combinedSenderDateAttachment() {
        let result = SearchQueryParser.parse("from john last week with attachments")
        #expect(result.filters.sender == "john")
        #expect(result.filters.dateRange != nil)
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "")
    }

    @Test("Multiple filters combine: unread + sender + category")
    func combinedUnreadSenderCategory() {
        let result = SearchQueryParser.parse("unread promotions from john")
        #expect(result.filters.sender == "john")
        #expect(result.filters.category == .promotions)
        #expect(result.filters.isRead == false)
        #expect(result.text == "")
    }

    @Test("All filters active triggers hasActiveFilters")
    func hasActiveFiltersWhenSet() {
        let result = SearchQueryParser.parse("from alice yesterday with attachments promotions unread")
        #expect(result.filters.hasActiveFilters)
    }

    // MARK: - Scope

    @Test("Default scope is allMail")
    func defaultScopeIsAllMail() {
        let result = SearchQueryParser.parse("test query")
        #expect(result.scope == .allMail)
    }

    @Test("Scope is preserved when explicitly set to currentFolder")
    func scopePreservedCurrentFolder() {
        let result = SearchQueryParser.parse("test query", scope: .currentFolder(folderId: "INBOX"))
        #expect(result.scope == .currentFolder(folderId: "INBOX"))
        #expect(result.text == "test query")
    }

    // MARK: - Case Insensitivity

    @Test("'FROM' is case insensitive for sender extraction")
    func caseInsensitiveSender() {
        let result = SearchQueryParser.parse("FROM john WITH ATTACHMENTS")
        #expect(result.filters.sender == "john")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "")
    }

    @Test("'YESTERDAY' is case insensitive for date extraction")
    func caseInsensitiveDate() {
        let result = SearchQueryParser.parse("YESTERDAY notes")
        #expect(result.filters.dateRange != nil)
        #expect(result.text == "notes")
    }

    @Test("'UNREAD' is case insensitive for read status")
    func caseInsensitiveReadStatus() {
        let result = SearchQueryParser.parse("UNREAD messages")
        #expect(result.filters.isRead == false)
        #expect(result.text == "messages")
    }

    @Test("Mixed case 'From' works for sender")
    func mixedCaseSender() {
        let result = SearchQueryParser.parse("From alice@test.com report")
        #expect(result.filters.sender == "alice@test.com")
        #expect(result.text == "report")
    }

    // MARK: - Month-Based Date Patterns

    @Test("'in march' extracts date range for that month")
    func inMonthDateRange() throws {
        let result = SearchQueryParser.parse("in march expenses")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let monthComponent = calendar.component(.month, from: range.start)
        #expect(monthComponent == 3)
        // The range should span approximately one month
        let daySpan = calendar.dateComponents([.day], from: range.start, to: range.end).day!
        #expect(daySpan >= 28 && daySpan <= 31)
        #expect(result.text == "expenses")
    }

    @Test("'before june' extracts date range ending at start of June")
    func beforeMonthDateRange() throws {
        let result = SearchQueryParser.parse("before june records")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let endMonth = calendar.component(.month, from: range.end)
        #expect(endMonth == 6)
        // Start should be far in the past (10 years back)
        #expect(range.start < range.end)
        #expect(result.text == "records")
    }

    @Test("'after january' extracts date range from start of January to now")
    func afterMonthDateRange() throws {
        let result = SearchQueryParser.parse("after january reports")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let now = Date()
        let startMonth = calendar.component(.month, from: range.start)
        #expect(startMonth == 1)
        #expect(abs(range.end.timeIntervalSince(now)) < 5)
        #expect(result.text == "reports")
    }

    @Test("Abbreviated month names work: 'in jan', 'before feb'")
    func abbreviatedMonthNames() throws {
        let result = SearchQueryParser.parse("in jan budget")
        let range = try #require(result.filters.dateRange)

        let calendar = Calendar.current
        let monthComponent = calendar.component(.month, from: range.start)
        #expect(monthComponent == 1)
        #expect(result.text == "budget")
    }

    // MARK: - Edge Cases

    @Test("Extra whitespace is collapsed in remaining text")
    func collapseExtraWhitespace() {
        let result = SearchQueryParser.parse("  budget   report  from alice  ")
        #expect(result.filters.sender == "alice")
        #expect(result.text == "budget report")
    }

    @Test("Query with only filters produces empty text")
    func onlyFiltersProducesEmptyText() {
        let result = SearchQueryParser.parse("from john with attachments")
        #expect(result.filters.sender == "john")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "")
    }

    @Test("'promotion' singular also matches promotions category")
    func singularPromotionCategory() {
        let result = SearchQueryParser.parse("promotion deals")
        #expect(result.filters.category == .promotions)
        #expect(result.text == "deals")
    }

    @Test("'has attachments' plural also works")
    func hasAttachmentsPlural() {
        let result = SearchQueryParser.parse("has attachments report")
        #expect(result.filters.hasAttachment == true)
        #expect(result.text == "report")
    }

    @Test("'forum' singular also matches forums category")
    func singularForumCategory() {
        let result = SearchQueryParser.parse("forum discussions")
        #expect(result.filters.category == .forums)
        #expect(result.text == "discussions")
    }

    @Test("No false positive: 'from' inside a word is not extracted")
    func noFalsePositiveFromInWord() {
        // "from" at start is a keyword, but embedded words like "platform" shouldn't trigger
        let result = SearchQueryParser.parse("platform migration")
        #expect(result.filters.sender == nil)
        #expect(result.text == "platform migration")
    }

    @Test("hasActiveFilters is false when no filters set")
    func hasActiveFiltersFalseWhenEmpty() {
        let result = SearchQueryParser.parse("just text query")
        #expect(!result.filters.hasActiveFilters)
    }

    @Test("hasActiveFilters is true when any single filter set")
    func hasActiveFiltersTrueWithSingleFilter() {
        let senderResult = SearchQueryParser.parse("from alice")
        #expect(senderResult.filters.hasActiveFilters)

        let attachmentResult = SearchQueryParser.parse("with attachments")
        #expect(attachmentResult.filters.hasActiveFilters)

        let readResult = SearchQueryParser.parse("unread")
        #expect(readResult.filters.hasActiveFilters)
    }
}
