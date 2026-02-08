import SwiftUI

/// Placeholder view for email composer (future feature).
///
/// Shows a simple "Compose Email" message with dismiss button.
/// Will be replaced with full EmailComposerView in a future milestone.
///
/// Spec ref: Thread List spec FR-TL-05
struct ComposerPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    /// Account email to compose from (defaults to selected account)
    let fromAccount: String?

    init(fromAccount: String? = nil) {
        self.fromAccount = fromAccount
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Compose Email")
                    .font(.headline)

                if let fromAccount {
                    Text("From: \(fromAccount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Composer coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("New Email")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ComposerPlaceholder(fromAccount: "user@gmail.com")
}
