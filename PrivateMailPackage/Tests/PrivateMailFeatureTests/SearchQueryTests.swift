import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("SearchQuery & SearchFilters")
struct SearchQueryTests {

    // MARK: - SearchFilters.hasActiveFilters

    @Test("hasActiveFilters returns false when all filters are nil")
    func hasActiveFiltersAllNil() {
        let filters = SearchFilters()
        #expect(filters.hasActiveFilters == false)
    }

    @Test("hasActiveFilters returns true when sender is set")
    func hasActiveFiltersSenderSet() {
        let filters = SearchFilters(sender: "alice")
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when dateRange is set")
    func hasActiveFiltersDateRangeSet() {
        let range = DateRange(start: Date(), end: Date().addingTimeInterval(86400))
        let filters = SearchFilters(dateRange: range)
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when hasAttachment is set")
    func hasActiveFiltersHasAttachmentSet() {
        let filters = SearchFilters(hasAttachment: true)
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when folder is set")
    func hasActiveFiltersFolderSet() {
        let filters = SearchFilters(folder: "INBOX")
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when category is set")
    func hasActiveFiltersCategorySet() {
        let filters = SearchFilters(category: .social)
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when isRead is set")
    func hasActiveFiltersIsReadSet() {
        let filters = SearchFilters(isRead: false)
        #expect(filters.hasActiveFilters == true)
    }

    @Test("hasActiveFilters returns true when multiple filters are set")
    func hasActiveFiltersMultipleSet() {
        let filters = SearchFilters(sender: "alice", isRead: true)
        #expect(filters.hasActiveFilters == true)
    }

    // MARK: - SearchQuery defaults

    @Test("default scope is allMail")
    func defaultScopeIsAllMail() {
        let query = SearchQuery(text: "test")
        #expect(query.scope == .allMail)
    }

    @Test("default filters have no active filters")
    func defaultFiltersEmpty() {
        let query = SearchQuery(text: "test")
        #expect(query.filters.hasActiveFilters == false)
    }

    // MARK: - SearchScope equality

    @Test("SearchScope.allMail equals allMail")
    func allMailEquality() {
        #expect(SearchScope.allMail == SearchScope.allMail)
    }

    @Test("SearchScope.currentFolder equality matches on folderId")
    func currentFolderEquality() {
        let a = SearchScope.currentFolder(folderId: "folder-1")
        let b = SearchScope.currentFolder(folderId: "folder-1")
        let c = SearchScope.currentFolder(folderId: "folder-2")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - SearchFilters Equatable

    @Test("SearchFilters Equatable compares all fields")
    func filtersEquatable() {
        let a = SearchFilters(sender: "alice", isRead: true)
        let b = SearchFilters(sender: "alice", isRead: true)
        let c = SearchFilters(sender: "bob", isRead: true)
        #expect(a == b)
        #expect(a != c)
    }
}
