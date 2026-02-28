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
    @Environment(ThemeProvider.self) private var theme
    @Binding var searchText: String
    let viewState: SearchViewState
    @Binding var filters: SearchFilters
    @Binding var isCurrentFolderScope: Bool
    let currentFolderName: String?
    let threads: [VaultMailFeature.Thread]
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
                .padding(.top, theme.spacing.sm)
                .padding(.bottom, theme.spacing.xs)

            // Scope picker (All Mail / Current Folder)
            if currentFolderName != nil {
                scopePicker
                    .padding(.horizontal)
                    .padding(.vertical, theme.spacing.xs)
            }

            // Filter chips (visible when filters or query active)
            if filters.hasActiveFilters || !searchText.isEmpty {
                SearchFilterChipsView(filters: $filters)
                    .padding(.horizontal)
                    .padding(.vertical, theme.spacing.xs)
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
        .background(theme.colors.background)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: theme.spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.textSecondary)
                    .font(theme.typography.bodyLarge)

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
                            .foregroundStyle(theme.colors.textSecondary)
                            .font(theme.typography.bodyLarge)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.sm)
            .background(theme.colors.surfaceElevated, in: theme.shapes.smallRect)

            Button("Cancel") {
                onDismiss()
            }
            .font(theme.typography.bodyLarge)
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
