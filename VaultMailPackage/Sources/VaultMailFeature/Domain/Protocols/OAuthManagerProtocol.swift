import Foundation

/// Protocol for OAuth 2.0 authentication and token management.
///
/// Implementations MUST support Gmail OAuth with PKCE via
/// ASWebAuthenticationSession (AC-F-04).
///
/// Spec ref: Account Management spec FR-ACCT-03, FR-ACCT-04
public protocol OAuthManagerProtocol: Sendable {
    /// Authenticate a user via OAuth 2.0 with PKCE.
    /// Presents a system browser for Google login and consent.
    func authenticate() async throws -> OAuthToken

    /// Refresh an expired access token using the refresh token.
    /// Retries up to 3 times with exponential backoff (FR-ACCT-04).
    func refreshToken(_ token: OAuthToken) async throws -> OAuthToken

    /// Format an XOAUTH2 SASL authentication string for IMAP/SMTP.
    /// Used by the email sync layer for Gmail authentication.
    func formatXOAUTH2String(email: String, accessToken: String) -> String
}
