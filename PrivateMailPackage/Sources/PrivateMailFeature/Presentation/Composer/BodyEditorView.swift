import SwiftUI

/// Plain text body editor with formatting toolbar.
///
/// Provides bold, italic, and link buttons that insert Markdown-style
/// syntax. Users don't type raw Markdown — the toolbar handles it.
///
/// Spec ref: Email Composer FR-COMP-01
struct BodyEditorView: View {
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
            formattingToolbar

            Divider()

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .accessibilityLabel("Email body")
        }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 16) {
            Button {
                insertMarkdown(prefix: "**", suffix: "**", placeholder: "bold text")
            } label: {
                Image(systemName: "bold")
                    .font(.body)
            }
            .accessibilityLabel("Bold")

            Button {
                insertMarkdown(prefix: "*", suffix: "*", placeholder: "italic text")
            } label: {
                Image(systemName: "italic")
                    .font(.body)
            }
            .accessibilityLabel("Italic")

            Button {
                insertMarkdown(prefix: "[", suffix: "](url)", placeholder: "link text")
            } label: {
                Image(systemName: "link")
                    .font(.body)
            }
            .accessibilityLabel("Insert link")

            Spacer()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Markdown Insertion

    private func insertMarkdown(prefix: String, suffix: String, placeholder: String) {
        // Insert at the end of current text (cursor position tracking
        // requires UITextView interaction which adds complexity;
        // append-based approach works well for V1)
        if text.isEmpty {
            text = "\(prefix)\(placeholder)\(suffix)"
        } else {
            text += "\(prefix)\(placeholder)\(suffix)"
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    BodyEditorView(text: .constant(""))
}

#Preview("With Content") {
    BodyEditorView(text: .constant("Hello,\n\nThis is a test email with some content.\n\nBest regards"))
}
