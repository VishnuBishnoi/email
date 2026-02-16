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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
}
