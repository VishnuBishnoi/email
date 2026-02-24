import SwiftUI

/// Plain text body editor (rich text removed).
struct BodyEditorView: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Write your message...")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityLabel("Email body")
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Previews

#Preview("Empty") {
    BodyEditorView(text: .constant(""))
}

#Preview("With Content") {
    BodyEditorView(text: .constant("Hello,\n\nThis is a test email with some content.\n\nBest regards"))
}
