import Foundation

/// Errors from OAuth 2.0 operations.
///
/// Spec ref: Account Management spec FR-ACCT-03, FR-ACCT-04
public enum OAuthError: Error, LocalizedError, Sendable {
    case authenticationCancelled
    case invalidAuthorizationCode
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case invalidResponse
    case maxRetriesExceeded
    case networkError(String)
    case noRefreshToken

    public var errorDescription: String? {
        switch self {
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .invalidAuthorizationCode:
            "Invalid authorization code received."
        case .tokenExchangeFailed(let reason):
            "Token exchange failed: \(reason)"
        case .tokenRefreshFailed(let reason):
            "Token refresh failed: \(reason)"
        case .invalidResponse:
            "Invalid response from OAuth server."
        case .maxRetriesExceeded:
            "Maximum retry attempts exceeded. Please re-authenticate."
        case .networkError(let reason):
            "Network error: \(reason)"
        case .noRefreshToken:
            "No refresh token available."
        }
    }
}
