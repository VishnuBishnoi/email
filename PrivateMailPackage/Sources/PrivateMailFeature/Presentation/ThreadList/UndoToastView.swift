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

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
}
