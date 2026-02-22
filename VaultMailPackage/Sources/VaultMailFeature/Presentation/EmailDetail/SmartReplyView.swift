import SwiftUI

/// Vertical list of AI-generated smart reply suggestion chips.
/// Each chip is tappable and triggers the provided callback with the suggestion text.
/// Hides entirely when no suggestions are available.
struct SmartReplyView: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    @Environment(ThemeProvider.self) private var theme

    // MARK: - Body

    var body: some View {
        if !suggestions.isEmpty {
            suggestionContent
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Content

    private var suggestionContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing.listRowSpacing) {
            // Header with AI icon
            HStack(spacing: theme.spacing.chipVertical) {
                Image(systemName: "sparkles")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.aiAccent)

                Text("Quick Replies")
                    .font(theme.typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.horizontal, theme.spacing.xs)

            // Vertical stack of suggestion chips
            VStack(spacing: theme.spacing.sm) {
                ForEach(suggestions, id: \.self) { suggestion in
                    chipButton(for: suggestion)
                }
            }
        }
        .padding(theme.spacing.md)
        .background(
            RoundedRectangle(cornerRadius: theme.shapes.large)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.shapes.large)
                .strokeBorder(
                    LinearGradient(
                        colors: [theme.colors.aiAccentMuted, theme.colors.accent.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI-generated reply suggestions")
    }

    // MARK: - Chip

    private func chipButton(for suggestion: String) -> some View {
        Button {
            onTap(suggestion)
        } label: {
            HStack(alignment: .top, spacing: theme.spacing.listRowSpacing) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(theme.typography.labelSmall)
                    .foregroundStyle(theme.colors.aiAccent.opacity(0.7))
                    .padding(.top, 3)

                Text(suggestion)
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.listRowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: theme.shapes.smallRect)
            .overlay(
                theme.shapes.smallRect
                    .strokeBorder(theme.colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reply with: \(suggestion)")
        .accessibilityHint("Tap to open composer with this reply")
    }
}

// MARK: - Previews

#Preview("With Suggestions") {
    SmartReplyView(
        suggestions: [
            "Sounds good! I'll be there.",
            "Let me check my schedule and get back to you by tomorrow.",
            "Thanks for the update — could you share more details?"
        ],
        onTap: { _ in }
    )
    .padding()
    .environment(ThemeProvider())
}

#Preview("Empty") {
    SmartReplyView(
        suggestions: [],
        onTap: { _ in }
    )
    .padding()
    .environment(ThemeProvider())
}

#Preview("Single Suggestion") {
    SmartReplyView(
        suggestions: ["Got it, thanks!"],
        onTap: { _ in }
    )
    .padding()
    .environment(ThemeProvider())
}

#Preview("Long Suggestions") {
    SmartReplyView(
        suggestions: [
            "Great news! Looking forward to our discussion on this topic next week.",
            "I appreciate the information. However, I need some time to review the proposal before making a decision.",
            "Could you clarify the timeline and budget expectations for this project?"
        ],
        onTap: { _ in }
    )
    .padding()
    .environment(ThemeProvider())
}

#Preview("Animated Appearance") {
    struct AnimatedPreview: View {
        @State private var suggestions: [String] = []

        var body: some View {
            VStack {
                SmartReplyView(
                    suggestions: suggestions,
                    onTap: { text in
                        print("Selected: \(text)")
                    }
                )
                .animation(.easeIn(duration: 0.3), value: suggestions)

                Button("Load Suggestions") {
                    suggestions = [
                        "Sounds great!",
                        "I'll take a look and get back to you.",
                        "Can we discuss tomorrow?"
                    ]
                }
                .padding(.top)
            }
            .padding()
        }
    }

    return AnimatedPreview()
        .environment(ThemeProvider())
}
