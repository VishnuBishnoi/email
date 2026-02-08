import SwiftUI

/// Placeholder view for search screen (future feature).
///
/// Shows a simple search interface placeholder.
/// Will be replaced with full SearchView in a future milestone.
///
/// Spec ref: Thread List spec FR-TL-05
struct SearchPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Search Emails")
                .font(.headline)

            Text("Search coming soon")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        SearchPlaceholder()
    }
}
