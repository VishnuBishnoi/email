import SwiftUI

/// Card displaying an AI-generated summary of an email thread.
/// Shows a loading state while the summary is being generated,
/// the summary text once available, or hides entirely when idle.
struct AISummaryView: View {
    let summary: String?
    let isLoading: Bool

    // MARK: - Body

    var body: some View {
        if isLoading && summary == nil {
            loadingCard
        } else if let summary, !summary.isEmpty {
            summaryCard(summary)
                .transition(.opacity)
        }
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Summarizing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Card

    private func summaryCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Summary", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI-generated thread summary")
        .accessibilityValue(text)
    }
}

// MARK: - Previews

#Preview("Loading") {
    AISummaryView(summary: nil, isLoading: true)
        .padding()
}

#Preview("Summary Available") {
    AISummaryView(
        summary: "This thread discusses the Q4 budget proposal. Key points include a 15% increase in marketing spend and a new hire for the engineering team.",
        isLoading: false
    )
    .padding()
}

#Preview("Hidden - Idle") {
    AISummaryView(summary: nil, isLoading: false)
        .padding()
}

#Preview("Animated Appearance") {
    struct AnimatedPreview: View {
        @State private var summary: String?

        var body: some View {
            VStack {
                AISummaryView(summary: summary, isLoading: summary == nil)
                    .animation(.easeIn(duration: 0.3), value: summary)

                Button("Show Summary") {
                    summary = "The team agreed to move forward with the revised timeline. Next steps include updating the project plan by Friday."
                }
                .padding(.top)
            }
            .padding()
        }
    }

    return AnimatedPreview()
}
