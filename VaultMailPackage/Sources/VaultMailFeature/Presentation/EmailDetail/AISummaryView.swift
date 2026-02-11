import SwiftUI

/// On-demand AI summary card for an email thread.
///
/// Displays a "Summarize" button that the user taps to generate the summary.
/// Shows a loading spinner while generating, then the summary text.
/// Only visible when an AI model is available (`isAvailable == true`).
///
/// Spec ref: FR-ED-02
struct AISummaryView: View {
    let summary: String?
    let isLoading: Bool
    let isAvailable: Bool
    let onRequestSummary: () -> Void

    // MARK: - Body

    var body: some View {
        if let summary, !summary.isEmpty {
            summaryCard(summary)
                .transition(.opacity)
        } else if isLoading {
            loadingCard
        } else if isAvailable {
            requestButton
        }
    }

    // MARK: - Request Button

    private var requestButton: some View {
        Button(action: onRequestSummary) {
            Label("Summarize with AI", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .accessibilityLabel("Summarize this conversation with AI")
        .accessibilityHint("Double tap to generate an AI summary")
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Summarizing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Generating AI summary")
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

#Preview("Request Button") {
    AISummaryView(summary: nil, isLoading: false, isAvailable: true, onRequestSummary: {})
        .padding()
}

#Preview("Loading") {
    AISummaryView(summary: nil, isLoading: true, isAvailable: true, onRequestSummary: {})
        .padding()
}

#Preview("Summary Available") {
    AISummaryView(
        summary: "This thread discusses the Q4 budget proposal. Key points include a 15% increase in marketing spend and a new hire for the engineering team.",
        isLoading: false,
        isAvailable: true,
        onRequestSummary: {}
    )
    .padding()
}

#Preview("Hidden - No AI") {
    AISummaryView(summary: nil, isLoading: false, isAvailable: false, onRequestSummary: {})
        .padding()
}

#Preview("Interactive") {
    struct InteractivePreview: View {
        @State private var summary: String?
        @State private var isLoading = false

        var body: some View {
            VStack {
                AISummaryView(
                    summary: summary,
                    isLoading: isLoading,
                    isAvailable: true,
                    onRequestSummary: {
                        isLoading = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            summary = "The team agreed to move forward with the revised timeline."
                            isLoading = false
                        }
                    }
                )
                .animation(.easeIn(duration: 0.3), value: summary)
            }
            .padding()
        }
    }

    return InteractivePreview()
}
