import SwiftUI

/// Horizontal scrollable tab bar for AI category filtering.
///
/// Displays an "All" tab plus one tab per visible category from
/// `SettingsStore.categoryTabVisibility`. Each tab shows its unread
/// badge count. The selected tab uses accent background; others use
/// secondary background.
///
/// Hidden when the selected folder is Outbox (virtual, no categories).
///
/// Spec ref: Thread List FR-TL-02, Settings FR-SET-01 Appearance
struct CategoryTabBar: View {
    @Environment(SettingsStore.self) private var settings

    /// The currently selected category (nil = "All").
    @Binding var selectedCategory: String?

    /// Unread counts keyed by AICategory rawValue (nil key = total).
    let unreadCounts: [String?: Int]

    // MARK: - Derived State

    /// Ordered list of visible categories based on settings.
    private var visibleCategories: [AICategory] {
        AICategory.allCases.filter { category in
            // forums and uncategorized are not togglable in settings
            guard category != .uncategorized, category != .forums else { return false }
            return settings.categoryTabVisibility[category.rawValue] ?? false
        }
    }

    /// Total unread count across all categories (for the "All" tab).
    private var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" tab
                categoryTab(
                    label: "All",
                    isSelected: selectedCategory == nil,
                    unreadCount: totalUnreadCount
                ) {
                    selectedCategory = nil
                }

                // Category tabs
                ForEach(visibleCategories, id: \.self) { category in
                    categoryTab(
                        label: category.displayLabel,
                        isSelected: selectedCategory == category.rawValue,
                        unreadCount: unreadCounts[category.rawValue] ?? 0
                    ) {
                        selectedCategory = category.rawValue
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category filter tabs")
    }

    // MARK: - Tab Button

    private func categoryTab(
        label: String,
        isSelected: Bool,
        unreadCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) category\(unreadCount > 0 ? ", \(unreadCount) unread" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("All Selected") {
    CategoryTabBar(
        selectedCategory: .constant(nil),
        unreadCounts: [
            AICategory.primary.rawValue: 5,
            AICategory.social.rawValue: 3,
            AICategory.promotions.rawValue: 12,
            AICategory.updates.rawValue: 1,
        ]
    )
    .environment(SettingsStore())
}

#Preview("Social Selected") {
    CategoryTabBar(
        selectedCategory: .constant(AICategory.social.rawValue),
        unreadCounts: [
            AICategory.primary.rawValue: 5,
            AICategory.social.rawValue: 3,
        ]
    )
    .environment(SettingsStore())
}

#Preview("No Unread") {
    CategoryTabBar(
        selectedCategory: .constant(nil),
        unreadCounts: [:]
    )
    .environment(SettingsStore())
}
