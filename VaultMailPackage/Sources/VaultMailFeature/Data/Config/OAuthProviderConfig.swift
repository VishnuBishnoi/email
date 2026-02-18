import Foundation

/// OAuth 2.0 provider configuration for multi-provider support.
///
/// Encapsulates all OAuth-specific settings (client ID, endpoints, scopes)
/// per provider. The `OAuthManager` accepts this config at init instead of
/// being hardcoded to Google.
///
/// Spec ref: FR-MPROV-07 (OAuthManager Refactoring)
public struct OAuthProviderConfig: Sendable, Equatable {
    /// Which provider this config is for.
    public let provider: ProviderIdentifier
    /// OAuth 2.0 client ID.
    public let clientId: String
    /// Authorization endpoint URL.
    public let authEndpoint: String
    /// Token exchange/refresh endpoint URL.
    public let tokenEndpoint: String
    /// OAuth scope string.
    public let scope: String
    /// URL scheme registered in Info.plist for redirect.
    public let redirectScheme: String
    /// Whether to use PKCE (Google requires it, Microsoft supports it).
    public let usesPKCE: Bool

    public init(
        provider: ProviderIdentifier,
        clientId: String,
        authEndpoint: String,
        tokenEndpoint: String,
        scope: String,
        redirectScheme: String,
        usesPKCE: Bool = true
    ) {
        self.provider = provider
        self.clientId = clientId
        self.authEndpoint = authEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scope = scope
        self.redirectScheme = redirectScheme
        self.usesPKCE = usesPKCE
    }

    // MARK: - Static Configs

    /// Google OAuth configuration using existing AppConstants.
    public static func google(clientId: String) -> OAuthProviderConfig {
        OAuthProviderConfig(
            provider: .gmail,
            clientId: clientId,
            authEndpoint: AppConstants.googleAuthEndpoint,
            tokenEndpoint: AppConstants.googleTokenEndpoint,
            scope: AppConstants.oauthScope,
            redirectScheme: AppConstants.oauthRedirectScheme,
            usesPKCE: true
        )
    }

    /// Microsoft OAuth configuration (placeholder — blocked on OQ-01 Azure AD client ID).
    ///
    /// When the Azure AD client ID is available:
    /// - Fill in real `clientId`
    /// - Email resolution via `id_token` JWT claims (NOT Graph API)
    /// - XOAUTH2 format identical to Gmail
    /// - SMTP uses STARTTLS on port 587
    public static func microsoft(clientId: String) -> OAuthProviderConfig {
        OAuthProviderConfig(
            provider: .outlook,
            clientId: clientId,
            authEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            scope: "https://outlook.office365.com/IMAP.AccessAsUser.All https://outlook.office365.com/SMTP.Send offline_access openid email",
            redirectScheme: AppConstants.oauthRedirectScheme,
            usesPKCE: true
        )
    }
}
