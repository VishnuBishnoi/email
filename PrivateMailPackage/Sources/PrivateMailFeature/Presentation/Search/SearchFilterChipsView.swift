import SwiftUI

/// Horizontal scrollable filter chips for search refinement.
///
/// Shows active filters as removable capsule chips. Tapping a chip
/// removes that filter and triggers a re-search via binding update.
///
/// Spec ref: FR-SEARCH-02, AC-S-03
struct SearchFilterChipsView: View {
    @Binding var filters: SearchFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let sender = filters.sender {
                    filterChip(
                        label: "From: \(sender)",
                        icon: "person.fill"
                    ) {
                        filters.sender = nil
                    }
                }

                if filters.dateRange != nil {
                    filterChip(
                        label: "Date Range",
                        icon: "calendar"
                    ) {
                        filters.dateRange = nil
                    }
                }

                if filters.hasAttachment == true {
                    filterChip(
                        label: "Has Attachment",
                        icon: "paperclip"
                    ) {
                        filters.hasAttachment = nil
                    }
                }

                if let category = filters.category {
                    filterChip(
                        label: category.rawValue.capitalized,
                        icon: "tag.fill"
                    ) {
                        filters.category = nil
                    }
                }

                if let isRead = filters.isRead {
                    filterChip(
                        label: isRead ? "Read" : "Unread",
                        icon: isRead ? "envelope.open" : "envelope.badge"
                    ) {
                        filters.isRead = nil
                    }
                }

                if let folder = filters.folder {
                    filterChip(
                        label: "Folder: \(folder)",
                        icon: "folder.fill"
                    ) {
                        filters.folder = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active search filters")
    }

    // MARK: - Chip Component

    @ViewBuilder
    private func filterChip(
        label: String,
        icon: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(label)")
        .accessibilityHint("Double tap to remove this filter")
        .accessibilityAddTraits(.isButton)
    }
}
