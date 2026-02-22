import SwiftUI

/// Plain text body editor with formatting toolbar.
///
/// Provides bold, italic, and link buttons that insert Markdown-style
/// syntax. Users don't type raw Markdown — the toolbar handles it.
///
/// Spec ref: Email Composer FR-COMP-01
struct BodyEditorView: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
            formattingToolbar

            Divider()

            TextEditor(text: $text)
                .font(theme.typography.bodyLarge)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, theme.spacing.md)
                .accessibilityLabel("Email body")
        }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: theme.spacing.lg) {
            Button {
                insertMarkdown(prefix: "**", suffix: "**", placeholder: "bold text")
            } label: {
                Image(systemName: "bold")
                    .font(theme.typography.bodyLarge)
            }
            .accessibilityLabel("Bold")

            Button {
                insertMarkdown(prefix: "*", suffix: "*", placeholder: "italic text")
            } label: {
                Image(systemName: "italic")
                    .font(theme.typography.bodyLarge)
            }
            .accessibilityLabel("Italic")

            Button {
                insertMarkdown(prefix: "[", suffix: "](url)", placeholder: "link text")
            } label: {
                Image(systemName: "link")
                    .font(theme.typography.bodyLarge)
            }
            .accessibilityLabel("Insert link")

            Spacer()
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.sm)
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
        .environment(ThemeProvider())
}

#Preview("With Content") {
    BodyEditorView(text: .constant("Hello,\n\nThis is a test email with some content.\n\nBest regards"))
        .environment(ThemeProvider())
}
