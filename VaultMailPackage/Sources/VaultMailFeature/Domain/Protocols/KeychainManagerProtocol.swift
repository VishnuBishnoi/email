import Foundation

/// Protocol for secure storage of OAuth tokens in Keychain.
///
/// Implementations MUST use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// protection level (AC-F-03). Tokens are scoped by account ID.
///
/// Spec ref: Account Management spec FR-ACCT-04
public protocol KeychainManagerProtocol: Sendable {
    /// Store an OAuth token for an account.
    func store(_ token: OAuthToken, for accountId: String) async throws
    /// Retrieve an OAuth token for an account, or nil if not found.
    func retrieve(for accountId: String) async throws -> OAuthToken?
    /// Delete an OAuth token for an account.
    func delete(for accountId: String) async throws
    /// Update an existing OAuth token for an account.
    func update(_ token: OAuthToken, for accountId: String) async throws
}
