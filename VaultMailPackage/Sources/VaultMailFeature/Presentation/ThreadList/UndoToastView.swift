import SwiftUI

/// A floating bottom toast overlay for undoable thread actions.
///
/// Displays a message describing the action taken (e.g. "Thread archived")
/// alongside an "Undo" button. Auto-dismisses after 5 seconds if the user
/// does not tap Undo.
///
/// Spec ref: Thread List spec FR-TL-03
struct UndoToastView: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        HStack {
            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button(action: onUndo) {
                Text("Undo")
                    .font(theme.typography.titleSmall)
            }
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.md)
        .background(.thinMaterial, in: theme.shapes.mediumRect)
        .padding(.horizontal, theme.spacing.lg)
        .padding(.bottom, theme.spacing.lg)
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Tap Undo to reverse this action.")
    }
}

// MARK: - Previews

#Preview("Undo Toast — Archive") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15)
            .ignoresSafeArea()

        UndoToastView(
            message: "Thread archived",
            onUndo: {},
            onDismiss: {}
        )
    }
    .environment(ThemeProvider())
}

#Preview("Undo Toast — Delete") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15)
            .ignoresSafeArea()

        UndoToastView(
            message: "3 threads deleted",
            onUndo: {},
            onDismiss: {}
        )
    }
    .environment(ThemeProvider())
}

#Preview("Undo Toast — Move") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15)
            .ignoresSafeArea()

        UndoToastView(
            message: "Thread moved to Spam",
            onUndo: {},
            onDismiss: {}
        )
    }
    .environment(ThemeProvider())
}
