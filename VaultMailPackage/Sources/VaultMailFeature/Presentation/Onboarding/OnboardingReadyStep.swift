import SwiftUI

/// Onboarding Step 5: Feature tour and completion.
///
/// Displays a brief feature tour of key app capabilities (swipe gestures,
/// AI categorization, smart reply, search) and a "Go to Inbox" button
/// to complete onboarding.
///
/// Spec ref: FR-OB-01 step 5
struct OnboardingReadyStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're all set!")
                .font(.title.bold())

            Text("Here's what you can do with VaultMail")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
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
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

/// A single feature tour row with icon, title, and description.
struct FeatureTourItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.bold())
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingReadyStep {
        // Complete
    }
}
