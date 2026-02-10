import SwiftUI

/// Vertical list of AI-generated smart reply suggestion chips.
/// Each chip is tappable and triggers the provided callback with the suggestion text.
/// Hides entirely when no suggestions are available.
struct SmartReplyView: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    // MARK: - Body

    var body: some View {
        if !suggestions.isEmpty {
            suggestionContent
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Content

    private var suggestionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with AI icon
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)

                Text("Quick Replies")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Vertical stack of suggestion chips
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    chipButton(for: suggestion)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.7))
                    .padding(.top, 3)

                Text(suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
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
}

#Preview("Empty") {
    SmartReplyView(
        suggestions: [],
        onTap: { _ in }
    )
    .padding()
}

#Preview("Single Suggestion") {
    SmartReplyView(
        suggestions: ["Got it, thanks!"],
        onTap: { _ in }
    )
    .padding()
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
}
