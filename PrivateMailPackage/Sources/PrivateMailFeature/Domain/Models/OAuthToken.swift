import Foundation

/// OAuth 2.0 token representation.
///
/// Stored exclusively in Keychain — never persisted in SwiftData (AC-SEC-02).
///
/// Spec ref: Account Management spec FR-ACCT-04
public struct OAuthToken: Sendable, Codable, Equatable {
    /// Access token for IMAP/SMTP authentication
    public let accessToken: String
    /// Refresh token for obtaining new access tokens
    public let refreshToken: String
    /// Absolute expiration timestamp
    public let expiresAt: Date
    /// Token type (always "Bearer")
    public let tokenType: String
    /// Granted OAuth scope
    public let scope: String

    /// Whether the token has expired.
    public var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Whether the token is within 5 minutes of expiry.
    public var isNearExpiry: Bool {
        Date().addingTimeInterval(AppConstants.tokenRefreshBuffer) >= expiresAt
    }

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        tokenType: String = "Bearer",
        scope: String = AppConstants.oauthScope
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
    }
}
