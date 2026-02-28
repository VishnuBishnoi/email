import SwiftUI

/// Smart reply suggestion chips for reply composition.
///
/// Displays up to 3 horizontally scrollable suggestion buttons.
/// Tapping a suggestion inserts its text into the body for editing.
/// Hidden entirely when no suggestions are available (no error shown).
///
/// Spec ref: Email Composer FR-COMP-03
struct SmartReplyChipView: View {
    @Environment(ThemeProvider.self) private var theme

    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(replies, id: \.self) { reply in
                    Button {
                        onSelect(reply)
                    } label: {
                        Text(reply)
                            .font(theme.typography.bodyMedium)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.colors.accent)
                    .accessibilityLabel("Smart reply: \(reply)")
                }
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.sm)
        }
    }
}

// MARK: - Previews

#Preview("With Suggestions") {
    SmartReplyChipView(
        replies: ["Thanks!", "Sounds good!", "I'll take a look."],
        onSelect: { _ in }
    )
    .environment(ThemeProvider())
}

#Preview("Single Suggestion") {
    SmartReplyChipView(
        replies: ["Got it, thanks!"],
        onSelect: { _ in }
    )
    .environment(ThemeProvider())
}
