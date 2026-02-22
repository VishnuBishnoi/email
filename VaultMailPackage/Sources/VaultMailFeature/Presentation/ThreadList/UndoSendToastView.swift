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

    @Environment(ThemeProvider.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: theme.spacing.sm) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)

                Text("Sending in \(remainingSeconds)s...")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                Button(action: onUndo) {
                    Text("Undo")
                        .font(theme.typography.titleSmall)
                        .foregroundStyle(theme.colors.accent)
                }
            }

            // Progress bar (always shown; replaces animation for Reduce Motion)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.colors.surfaceElevated)
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.accent)
                            .frame(width: max(0, geo.size.width * progressFraction), height: 3)
                    }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.md)
        .background(.regularMaterial, in: theme.shapes.mediumRect)
        .vmShadow(theme.shapes.shadowElevated)
        .padding(.horizontal, theme.spacing.lg)
        .padding(.bottom, theme.spacing.lg)
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
    .environment(ThemeProvider())
}

#Preview("15 Seconds") {
    VStack {
        Spacer()
        UndoSendToastView(remainingSeconds: 15, onUndo: {})
    }
    .environment(ThemeProvider())
}
