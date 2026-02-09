import SwiftUI

/// Countdown toast with Undo button for the undo-send feature.
///
/// Displayed as an overlay on ThreadListView when `UndoSendManager`
/// has an active countdown. Dismisses automatically when the
/// countdown reaches zero.
///
/// Accessibility: the toast announces the countdown and the Undo
/// button. Reduce Motion: uses simple progress bar instead of
/// animated transitions.
///
/// Spec ref: Email Composer FR-COMP-02, NFR-COMP-03
struct UndoSendToastView: View {
    let remainingSeconds: Int
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Sending in \(remainingSeconds)s...")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onUndo) {
                    Text("Undo")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Progress bar (always shown; replaces animation for Reduce Motion)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tertiary)
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: max(0, geo.size.width * progressFraction), height: 3)
                    }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending email in \(remainingSeconds) seconds. Tap undo to cancel.")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Progress fraction (1.0 → 0.0 as countdown progresses).
    /// Note: We don't know the total, so this is a rough estimate.
    /// The manager provides remainingSeconds; we approximate progress.
    private var progressFraction: CGFloat {
        // Use remainingSeconds as a simple indicator
        // Max undo delay is 30s
        CGFloat(remainingSeconds) / 30.0
    }
}

// MARK: - Previews

#Preview("5 Seconds") {
    VStack {
        Spacer()
        UndoSendToastView(remainingSeconds: 5, onUndo: {})
    }
}

#Preview("15 Seconds") {
    VStack {
        Spacer()
        UndoSendToastView(remainingSeconds: 15, onUndo: {})
    }
}
