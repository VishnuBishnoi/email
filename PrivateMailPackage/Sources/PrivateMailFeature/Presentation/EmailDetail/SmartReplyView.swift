import SwiftUI

/// Horizontal scrollable row of AI-generated smart reply suggestion chips.
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Replies", systemImage: "bolt.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        chipButton(for: suggestion)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Smart reply suggestions")
    }

    // MARK: - Chip

    private func chipButton(for suggestion: String) -> some View {
        Button {
            onTap(suggestion)
        } label: {
            Text(suggestion)
                .font(.subheadline)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reply suggestion: \(suggestion)")
    }
}

// MARK: - Previews

#Preview("With Suggestions") {
    SmartReplyView(
        suggestions: [
            "Sounds good!",
            "Let me check and get back to you.",
            "Thanks for the update."
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
                        "I'll take a look.",
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
