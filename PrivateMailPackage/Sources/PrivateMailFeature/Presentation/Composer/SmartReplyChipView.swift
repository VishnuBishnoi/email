import SwiftUI

/// Smart reply suggestion chips for reply composition.
///
/// Displays up to 3 horizontally scrollable suggestion buttons.
/// Tapping a suggestion inserts its text into the body for editing.
/// Hidden entirely when no suggestions are available (no error shown).
///
/// Spec ref: Email Composer FR-COMP-03
struct SmartReplyChipView: View {
    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button {
                        onSelect(reply)
                    } label: {
                        Text(reply)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("Smart reply: \(reply)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Previews

#Preview("With Suggestions") {
    SmartReplyChipView(
        replies: ["Thanks!", "Sounds good!", "I'll take a look."],
        onSelect: { _ in }
    )
}

#Preview("Single Suggestion") {
    SmartReplyChipView(
        replies: ["Got it, thanks!"],
        onSelect: { _ in }
    )
}
