import SwiftUI

/// Colored pill badge displaying an AI category label.
/// Hidden for uncategorized or nil category.
///
/// Spec ref: Thread List spec FR-TL-01
struct CategoryBadgeView: View {
    let category: AICategory?

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        if let category, category != .uncategorized {
            Text(category.displayLabel)
                .font(theme.typography.labelSmall)
                .foregroundStyle(categoryForeground(category))
                .padding(.horizontal, theme.spacing.chipHorizontal)
                .padding(.vertical, theme.spacing.xs)
                .background(categoryBackground(category), in: Capsule())
                .accessibilityLabel(Text("\(category.displayLabel) category"))
        }
    }

    private func categoryForeground(_ category: AICategory) -> Color {
        switch category {
        case .primary: theme.colors.categoryPrimary
        case .social: theme.colors.categorySocial
        case .promotions: theme.colors.categoryPromotions
        case .updates: theme.colors.categoryUpdates
        case .forums: theme.colors.categoryForums
        case .uncategorized: theme.colors.categoryUncategorized
        }
    }

    private func categoryBackground(_ category: AICategory) -> Color {
        switch category {
        case .primary: theme.colors.categoryPrimaryMuted
        case .social: theme.colors.categorySocialMuted
        case .promotions: theme.colors.categoryPromotionsMuted
        case .updates: theme.colors.categoryUpdatesMuted
        case .forums: theme.colors.categoryForumsMuted
        case .uncategorized: theme.colors.categoryUncategorizedMuted
        }
    }
}

// MARK: - AICategory Badge Styling

extension AICategory {
    /// User-facing display label for the badge.
    var displayLabel: String {
        switch self {
        case .primary: "Primary"
        case .social: "Social"
        case .promotions: "Promotions"
        case .updates: "Updates"
        case .forums: "Forums"
        case .uncategorized: "Uncategorized"
        }
    }
}

// MARK: - Previews

#Preview("All Categories") {
    VStack(spacing: 8) {
        ForEach(AICategory.allCases, id: \.self) { category in
            CategoryBadgeView(category: category)
        }
    }
    .environment(ThemeProvider())
    .padding()
}

#Preview("Nil Category") {
    CategoryBadgeView(category: nil)
        .environment(ThemeProvider())
        .padding()
}

#Preview("Single - Promotions") {
    CategoryBadgeView(category: .promotions)
        .environment(ThemeProvider())
        .padding()
}
