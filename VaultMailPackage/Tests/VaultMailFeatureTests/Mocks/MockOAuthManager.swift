import Foundation
@testable import VaultMailFeature

/// Controllable mock of OAuthManagerProtocol for testing.
final class MockOAuthManager: OAuthManagerProtocol, @unchecked Sendable {
    var provider: ProviderIdentifier = .gmail
    var authenticateResult: Result<OAuthToken, Error> = .failure(OAuthError.authenticationCancelled)
    var refreshResult: Result<OAuthToken, Error> = .failure(OAuthError.maxRetriesExceeded)
    var authenticateCallCount = 0
    var refreshCallCount = 0

    func authenticate() async throws -> OAuthToken {
        authenticateCallCount += 1
        return try authenticateResult.get()
    }

    func refreshToken(_ token: OAuthToken) async throws -> OAuthToken {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    func formatXOAUTH2String(email: String, accessToken: String) -> String {
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(authString.utf8).base64EncodedString()
    }
}
