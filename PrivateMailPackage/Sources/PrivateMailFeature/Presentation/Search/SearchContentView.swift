import SwiftUI

/// Search view state shared between ThreadListView and SearchContentView.
///
/// Spec ref: FR-SEARCH-01
enum SearchViewState: Equatable {
    /// Zero-state with recent searches
    case idle
    /// Loading spinner
    case searching
    /// Showing results
    case results
    /// No results found
    case empty
}

/// Inline search content overlay for the thread list.
///
/// Renders search results, recent searches, filter chips, loading spinner,
/// or empty state based on the current search state. Designed to replace
/// the thread list content inside ThreadListView when search is active.
///
/// MV pattern: receives all state as let properties and bindings.
/// Business logic (search execution, filter merging) lives in the parent.
///
/// Spec ref: FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-09
struct SearchContentView: View {
    let viewState: SearchViewState
    let searchText: String
    @Binding var filters: SearchFilters
    let results: [SearchResult]
    let recentSearches: [String]
    let onSelectRecentSearch: (String) -> Void
    let onClearRecentSearches: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips (visible when filters or query active)
            if filters.hasActiveFilters || !searchText.isEmpty {
                SearchFilterChipsView(filters: $filters)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            // Content based on state
            switch viewState {
            case .idle:
                RecentSearchesView(
                    recentSearches: recentSearches,
                    onSelectSearch: onSelectRecentSearch,
                    onClearAll: onClearRecentSearches
                )

            case .searching:
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Searching for emails")

            case .results:
                searchResultsList

            case .empty:
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Results List

    @ViewBuilder
    private var searchResultsList: some View {
        List(results) { result in
            NavigationLink(value: result.threadId) {
                SearchResultRowView(result: result, query: searchText)
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }
}
