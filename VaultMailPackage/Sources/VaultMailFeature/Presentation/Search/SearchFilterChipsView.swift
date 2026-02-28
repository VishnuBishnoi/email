import SwiftUI

/// Horizontal scrollable filter chips for search refinement.
///
/// Shows active filters as removable capsule chips. Tapping a chip
/// removes that filter and triggers a re-search via binding update.
///
/// Spec ref: FR-SEARCH-02, AC-S-03
struct SearchFilterChipsView: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var filters: SearchFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
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
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: icon)
                    .font(theme.typography.labelSmall)
                Text(label)
                    .font(theme.typography.caption)
                Image(systemName: "xmark.circle.fill")
                    .font(theme.typography.labelSmall)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.horizontal, theme.spacing.listRowSpacing)
            .padding(.vertical, theme.spacing.chipVertical)
            .background(theme.colors.surfaceElevated, in: theme.shapes.capsuleShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(label)")
        .accessibilityHint("Double tap to remove this filter")
        .accessibilityAddTraits(.isButton)
    }
}
