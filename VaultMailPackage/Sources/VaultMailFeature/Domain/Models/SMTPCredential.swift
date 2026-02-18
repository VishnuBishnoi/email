import Foundation

/// Credential for authenticating with an SMTP server.
///
/// Mirrors `IMAPCredential` — same two mechanisms, same parameters.
///
/// - `.xoauth2`: For OAuth providers (Gmail, Outlook)
/// - `.plain`: For app-password providers (Yahoo, iCloud, custom)
///
/// Spec ref: FR-MPROV-02, FR-MPROV-03
public enum SMTPCredential: Sendable, Equatable {
    /// XOAUTH2 authentication with user email and OAuth access token.
    case xoauth2(email: String, accessToken: String)

    /// SASL PLAIN authentication with username and app password.
    case plain(username: String, password: String)
}
