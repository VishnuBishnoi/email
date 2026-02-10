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

/// Inline search content overlay for the thread list (Apple Mail style).
///
/// Contains a custom search bar TextField at the top, and displays search
/// results using the same ThreadRowView as the inbox for a unified look.
/// Replaces the thread list content when search is active — no navigation
/// transition, the search bar appears in-place.
///
/// MV pattern: receives all state as let properties and bindings.
/// Business logic (search execution, filter merging, Thread lookup) lives in parent.
///
/// Spec ref: FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-09
struct SearchContentView: View {
    @Binding var searchText: String
    let viewState: SearchViewState
    @Binding var filters: SearchFilters
    @Binding var isCurrentFolderScope: Bool
    let currentFolderName: String?
    let threads: [PrivateMailFeature.Thread]
    let searchResults: [SearchResult]
    let recentSearches: [String]
    let onSelectRecentSearch: (String) -> Void
    let onClearRecentSearches: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Scope picker (All Mail / Current Folder)
            if currentFolderName != nil {
                scopePicker
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            // Filter chips (visible when filters or query active)
            if filters.hasActiveFilters || !searchText.isEmpty {
                SearchFilterChipsView(filters: $filters)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            Divider()

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
        #if os(iOS)
        .background(Color(.systemBackground))
        #endif
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.body)

                TextField("Search emails", text: $searchText)
                    .focused($isTextFieldFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    #endif
                    .accessibilityLabel("Search emails")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            #endif

            Button("Cancel") {
                onDismiss()
            }
            .font(.body)
            .accessibilityLabel("Cancel search")
        }
    }

    // MARK: - Scope Picker

    private var scopePicker: some View {
        Picker("Search scope", selection: $isCurrentFolderScope) {
            Text("All Mailboxes")
                .tag(false)
            if let name = currentFolderName {
                Text(name)
                    .tag(true)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Search scope")
    }

    // MARK: - Results List (uses same ThreadRowView with highlights)

    @ViewBuilder
    private var searchResultsList: some View {
        // First-wins: keep highest-scored result per thread (results are pre-sorted by score)
        let resultMap = Dictionary(searchResults.map { ($0.threadId, $0) }, uniquingKeysWith: { first, _ in first })
        List(threads, id: \.id) { thread in
            NavigationLink(value: thread.id) {
                if let result = resultMap[thread.id], !searchText.isEmpty {
                    HighlightedThreadRowView(
                        thread: thread,
                        highlightedSubject: result.subject,
                        highlightedSnippet: result.snippet,
                        queryText: searchText
                    )
                } else {
                    ThreadRowView(thread: thread)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }
}
