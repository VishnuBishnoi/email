import SwiftUI

/// A floating bottom toast overlay for error feedback on thread actions.
///
/// Displays a red-tinted error message with an exclamation icon.
/// Auto-dismisses after 4 seconds. Follows the same visual pattern as
/// `UndoToastView` for consistency.
///
/// Spec ref: Thread List spec FR-TL-03 (Phase 6 error toast)
struct ErrorToastView: View {
    let message: String
    let onDismiss: () -> Void

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.listRowSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.destructive)
                .accessibilityHidden(true)

            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(theme.typography.caption)
                    .bold()
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.md)
        .background(.thinMaterial, in: theme.shapes.mediumRect)
        .overlay(
            theme.shapes.mediumRect
                .strokeBorder(theme.colors.destructive.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, theme.spacing.lg)
        .padding(.bottom, theme.spacing.lg)
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message). Tap to dismiss.")
    }
}

// MARK: - Previews

#Preview("Error Toast — Archive Failed") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15)
            .ignoresSafeArea()

        ErrorToastView(
            message: "Failed to archive thread",
            onDismiss: {}
        )
    }
    .environment(ThemeProvider())
}

#Preview("Error Toast — Delete Failed") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15)
            .ignoresSafeArea()

        ErrorToastView(
            message: "Failed to delete threads",
            onDismiss: {}
        )
    }
    .environment(ThemeProvider())
}
