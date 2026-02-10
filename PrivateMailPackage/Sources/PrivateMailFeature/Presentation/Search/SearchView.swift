import SwiftUI
import SwiftData

/// Main search view with search bar, scope picker, filter chips, and results.
///
/// MV pattern: uses @State for view state, @Environment for dependencies,
/// .task(id:) for debounced search execution. No ViewModel.
///
/// Spec ref: FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-03, FR-SEARCH-09, AC-S-01
struct SearchView: View {
    let searchUseCase: SearchEmailsUseCase
    let aiEngineResolver: AIEngineResolver?

    // MARK: - State

    @State private var searchText = ""
    @State private var filters = SearchFilters()
    @State private var results: [SearchResult] = []
    @State private var viewState: ViewState = .idle
    @State private var recentSearches: [String] = []

    enum ViewState: Equatable {
        /// Zero-state with recent searches
        case idle
        /// Loading spinner
        case searching
        /// Showing results
        case results
        /// No results found
        case empty
    }

    // MARK: - Constants

    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 10

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips (below search bar, visible when filters or query active)
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
                    onSelectSearch: { query in
                        searchText = query
                    },
                    onClearAll: {
                        recentSearches = []
                        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
                    }
                )

            case .searching:
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Searching for emails")

            case .results:
                resultsList

            case .empty:
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search emails")
        .task(id: DebounceTrigger(text: searchText, filters: filters)) {
            // 300ms debounce via task cancellation
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
        .onAppear {
            loadRecentSearches()
        }
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        List(results) { result in
            NavigationLink(value: result.threadId) {
                SearchResultRowView(result: result, query: searchText)
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }

    // MARK: - Search Execution

    private func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        // Return to idle when query and filters are empty
        if trimmed.isEmpty && !filters.hasActiveFilters {
            viewState = .idle
            results = []
            return
        }

        viewState = .searching

        // Parse natural language query
        var query = SearchQueryParser.parse(trimmed, scope: .allMail)
        // Merge manual filter chips with NL-parsed filters
        query.filters = mergeFilters(parsed: query.filters, manual: filters)

        // Resolve AI engine for semantic search (nil-safe graceful degradation)
        let engine: (any AIEngineProtocol)?
        if let resolver = aiEngineResolver {
            engine = await resolver.resolveGenerativeEngine()
        } else {
            engine = nil
        }

        // Execute hybrid search
        let searchResults = await searchUseCase.execute(query: query, engine: engine)

        guard !Task.isCancelled else { return }

        results = searchResults
        viewState = searchResults.isEmpty ? .empty : .results

        // Save to recent searches
        if !trimmed.isEmpty {
            saveRecentSearch(trimmed)
        }
    }

    /// Merges manually-applied filter chips with filters extracted from NL parsing.
    /// Manual filters take priority over parsed ones.
    private func mergeFilters(parsed: SearchFilters, manual: SearchFilters) -> SearchFilters {
        SearchFilters(
            sender: manual.sender ?? parsed.sender,
            dateRange: manual.dateRange ?? parsed.dateRange,
            hasAttachment: manual.hasAttachment ?? parsed.hasAttachment,
            folder: manual.folder ?? parsed.folder,
            category: manual.category ?? parsed.category,
            isRead: manual.isRead ?? parsed.isRead
        )
    }

    // MARK: - Recent Searches Persistence

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }

    private func saveRecentSearch(_ query: String) {
        var searches = recentSearches
        searches.removeAll { $0 == query }
        searches.insert(query, at: 0)
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }
}

// MARK: - Debounce Trigger

/// Equatable trigger for .task(id:) — changes to any field cancel the
/// previous task and start a new debounced search.
private struct DebounceTrigger: Equatable {
    let text: String
    let filters: SearchFilters
}
