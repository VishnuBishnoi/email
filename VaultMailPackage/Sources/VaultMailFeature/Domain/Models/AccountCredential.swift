import Foundation

/// Unified credential type stored in Keychain per account.
///
/// Replaces direct `OAuthToken` storage to support both OAuth and
/// app-password authentication flows.
///
/// - `.oauth(OAuthToken)`: For Gmail, Outlook — stored as full token.
/// - `.password(String)`: For Yahoo, iCloud, custom IMAP — app password.
///
/// Spec ref: FR-MPROV-06 (App Password Authentication)
public enum AccountCredential: Sendable, Codable, Equatable {
    case oauth(OAuthToken)
    case password(String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case oauthToken
        case appPassword
    }

    private enum CredentialType: String, Codable {
        case oauth
        case password
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CredentialType.self, forKey: .type)

        switch type {
        case .oauth:
            let token = try container.decode(OAuthToken.self, forKey: .oauthToken)
            self = .oauth(token)
        case .password:
            let pw = try container.decode(String.self, forKey: .appPassword)
            self = .password(pw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .oauth(let token):
            try container.encode(CredentialType.oauth, forKey: .type)
            try container.encode(token, forKey: .oauthToken)
        case .password(let pw):
            try container.encode(CredentialType.password, forKey: .type)
            try container.encode(pw, forKey: .appPassword)
        }
    }

    // MARK: - Convenience

    /// The OAuth token if this is an OAuth credential, `nil` for password.
    public var oauthToken: OAuthToken? {
        switch self {
        case .oauth(let token): return token
        case .password: return nil
        }
    }

    /// Whether the credential needs refresh (only applies to OAuth).
    public var needsRefresh: Bool {
        switch self {
        case .oauth(let token): return token.isExpired || token.isNearExpiry
        case .password: return false
        }
    }
}
