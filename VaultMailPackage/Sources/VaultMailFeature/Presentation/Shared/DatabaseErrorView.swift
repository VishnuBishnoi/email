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
    @Environment(ThemeProvider.self) private var theme
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: theme.spacing.xxl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.colors.destructive)
                .accessibilityHidden(true)

            Text("Unable to Open Database")
                .font(theme.typography.displaySmall)
                .multilineTextAlignment(.center)

            Text("VaultMail was unable to set up its local database. This may be caused by low storage space or a corrupted data file.")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.spacing.xxxl)

            // Technical detail (collapsible)
            DisclosureGroup("Technical Details") {
                Text(message)
                    .font(theme.typography.captionMono)
                    .foregroundStyle(theme.colors.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, theme.spacing.xs)
            }
            .padding(.horizontal, theme.spacing.xxxl)
            .tint(theme.colors.textSecondary)

            if let url = URL(string: "mailto:support@appripe.com?subject=VaultMail%20Database%20Error&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: url) {
                    Label("Contact Support", systemImage: "envelope")
                        .font(theme.typography.titleMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, theme.spacing.xxxl)
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
        .environment(ThemeProvider())
}
