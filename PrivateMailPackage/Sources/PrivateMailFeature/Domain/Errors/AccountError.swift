import Foundation

/// Errors from account repository operations.
///
/// Spec ref: Account Management spec FR-ACCT-01, FR-ACCT-05
public enum AccountError: Error, LocalizedError, Sendable {
    case notFound(String)
    case duplicateAccount(String)
    case keychainFailure(KeychainError)
    case oauthFailure(OAuthError)
    case persistenceFailed(String)
    case imapValidationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            "Account not found: \(id)"
        case .duplicateAccount(let email):
            "An account with email \(email) already exists."
        case .keychainFailure(let error):
            "Keychain error: \(error.localizedDescription)"
        case .oauthFailure(let error):
            "OAuth error: \(error.localizedDescription)"
        case .persistenceFailed(let reason):
            "Persistence error: \(reason)"
        case .imapValidationFailed(let reason):
            "Couldn't connect to Gmail. \(reason)"
        }
    }
}
