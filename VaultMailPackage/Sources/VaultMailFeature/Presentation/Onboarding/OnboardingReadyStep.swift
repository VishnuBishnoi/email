import SwiftUI

/// Onboarding Step 5: Feature tour and completion.
///
/// Displays a brief feature tour of key app capabilities (swipe gestures,
/// AI categorization, smart reply, search) and a "Go to Inbox" button
/// to complete onboarding.
///
/// Spec ref: FR-OB-01 step 5
struct OnboardingReadyStep: View {
    @Environment(ThemeProvider.self) private var theme
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(theme.colors.success)
                .accessibilityHidden(true)

            Text("You're all set!")
                .font(theme.typography.displaySmall)

            Text("Here's what you can do with VaultMail")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)

            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                FeatureTourItem(
                    icon: "hand.draw.fill",
                    title: "Swipe Gestures",
                    description: "Swipe left to delete, right to archive"
                )
                FeatureTourItem(
                    icon: "sparkles",
                    title: "Smart Categories",
                    description: "AI-powered email categorization"
                )
                FeatureTourItem(
                    icon: "text.bubble.fill",
                    title: "Smart Reply",
                    description: "AI-generated reply suggestions"
                )
                FeatureTourItem(
                    icon: "magnifyingglass",
                    title: "Search",
                    description: "Find any email instantly"
                )
            }
            .padding(.horizontal)

            Spacer()

            Button("Go to Inbox") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("goToInboxButton")
        }
        .padding(.horizontal, theme.spacing.xxxl)
        .padding(.bottom, 40)
    }
}

/// A single feature tour row with icon, title, and description.
struct FeatureTourItem: View {
    @Environment(ThemeProvider.self) private var theme
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(theme.typography.displaySmall)
                .foregroundStyle(theme.colors.accent)
                .frame(width: theme.spacing.xxxl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title)
                    .font(theme.typography.titleMedium)
                Text(description)
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingReadyStep {
        // Complete
    }
    .environment(ThemeProvider())
}
