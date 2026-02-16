import SwiftUI

/// Full-screen error view displayed when the SwiftData ModelContainer
/// fails to initialise at app launch.
///
/// Provides the user with a clear, non-technical explanation and a
/// contact-support mailto link so they can report the problem.
///
/// This view replaces the previous `fatalError` crash path, ensuring the
/// app never terminates without giving the user actionable feedback.
public struct DatabaseErrorView: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Unable to Open Database")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("VaultMail was unable to set up its local database. This may be caused by low storage space or a corrupted data file.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Technical detail (collapsible)
            DisclosureGroup("Technical Details") {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .tint(.secondary)

            if let url = URL(string: "mailto:support@appripe.com?subject=VaultMail%20Database%20Error&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: url) {
                    Label("Contact Support", systemImage: "envelope")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Database error. VaultMail was unable to open its local database. \(message)")
    }
}

// MARK: - Previews

#Preview("Database Error") {
    DatabaseErrorView(message: "ModelContainer init failed: NSError Domain=NSCocoaErrorDomain Code=134060")
}
