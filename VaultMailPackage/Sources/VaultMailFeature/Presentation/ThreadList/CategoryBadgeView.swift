import SwiftUI

/// Colored pill badge displaying an AI category label.
/// Hidden for uncategorized or nil category.
///
/// Spec ref: Thread List spec FR-TL-01
struct CategoryBadgeView: View {
    let category: AICategory?

    var body: some View {
        if let category, category != .uncategorized {
            Text(category.displayLabel)
                .font(.caption2)
                .foregroundStyle(category.badgeForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(category.badgeBackground, in: Capsule())
                .accessibilityLabel(Text("\(category.displayLabel) category"))
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

    /// Background color for the category badge.
    var badgeBackground: Color {
        switch self {
        case .primary: .blue.opacity(0.15)
        case .social: .green.opacity(0.15)
        case .promotions: .orange.opacity(0.15)
        case .updates: .purple.opacity(0.15)
        case .forums: .teal.opacity(0.15)
        case .uncategorized: .gray.opacity(0.15)
        }
    }

    /// Foreground (text) color for the category badge.
    var badgeForeground: Color {
        switch self {
        case .primary: .blue
        case .social: .green
        case .promotions: .orange
        case .updates: .purple
        case .forums: .teal
        case .uncategorized: .gray
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
    .padding()
}

#Preview("Nil Category") {
    CategoryBadgeView(category: nil)
        .padding()
}

#Preview("Single - Promotions") {
    CategoryBadgeView(category: .promotions)
        .padding()
}
