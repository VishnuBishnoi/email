import SwiftUI

/// Zero-state view showing recent searches when the search bar is empty.
///
/// Displays up to 10 recent searches with tap-to-execute and a clear all button.
/// When no recent searches exist, shows an informational empty state.
///
/// Spec ref: FR-SEARCH-09, AC-S-10
struct RecentSearchesView: View {
    @Environment(ThemeProvider.self) private var theme

    let recentSearches: [String]
    let onSelectSearch: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        if recentSearches.isEmpty {
            ContentUnavailableView(
                "Search Emails",
                systemImage: "magnifyingglass",
                description: Text("Search by keyword, sender, date, or natural language")
            )
        } else {
            List {
                Section {
                    ForEach(recentSearches, id: \.self) { search in
                        Button {
                            onSelectSearch(search)
                        } label: {
                            HStack(spacing: theme.spacing.sm) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .font(theme.typography.bodyMedium)

                                Text(search)
                                    .font(theme.typography.bodyMedium)
                                    .foregroundStyle(theme.colors.textPrimary)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recent search: \(search)")
                        .accessibilityHint("Double tap to search for \(search)")
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") {
                            onClearAll()
                        }
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.accent)
                        .accessibilityLabel("Clear all recent searches")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent searches list")
        }
    }
}
