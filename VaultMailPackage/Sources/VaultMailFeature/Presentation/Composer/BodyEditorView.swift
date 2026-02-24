import SwiftUI

/// Plain text body editor (rich text removed).
struct BodyEditorView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String

    private var editorSurface: Color {
        colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.15) : .white
    }

    private var editorPrimaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var editorSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.black.opacity(0.56)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Write your message...")
                    .font(.body)
                    .foregroundStyle(editorSecondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(editorPrimaryText)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityLabel("Email body")
        }
        .background(editorSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.colors.border.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - Previews

#Preview("Empty") {
    BodyEditorView(text: .constant(""))
}

#Preview("With Content") {
    BodyEditorView(text: .constant("Hello,\n\nThis is a test email with some content.\n\nBest regards"))
}
