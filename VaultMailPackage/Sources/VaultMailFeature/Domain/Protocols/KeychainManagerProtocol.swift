import Foundation

/// Protocol for secure storage of account credentials in Keychain.
///
/// Implementations MUST use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// protection level (AC-F-03). Credentials are scoped by account ID.
///
/// Supports both OAuth tokens and app passwords via `AccountCredential`.
/// Legacy `OAuthToken` methods are provided for backward compatibility.
///
/// Spec ref: Account Management spec FR-ACCT-04
///           Multi-provider spec FR-MPROV-06
public protocol KeychainManagerProtocol: Sendable {
    // MARK: - AccountCredential API (primary)

    /// Store an account credential (OAuth token or app password) for an account.
    func storeCredential(_ credential: AccountCredential, for accountId: String) async throws
    /// Retrieve an account credential for an account, or nil if not found.
    func retrieveCredential(for accountId: String) async throws -> AccountCredential?
    /// Delete a credential for an account.
    func deleteCredential(for accountId: String) async throws
    /// Update an existing credential for an account.
    func updateCredential(_ credential: AccountCredential, for accountId: String) async throws

    // MARK: - Legacy OAuthToken API (backward compat)

    /// Store an OAuth token for an account.
    func store(_ token: OAuthToken, for accountId: String) async throws
    /// Retrieve an OAuth token for an account, or nil if not found.
    func retrieve(for accountId: String) async throws -> OAuthToken?
    /// Delete an OAuth token for an account.
    func delete(for accountId: String) async throws
    /// Update an existing OAuth token for an account.
    func update(_ token: OAuthToken, for accountId: String) async throws
}

/// Default implementations: legacy OAuthToken API delegates to AccountCredential API.
extension KeychainManagerProtocol {
    public func store(_ token: OAuthToken, for accountId: String) async throws {
        try await storeCredential(.oauth(token), for: accountId)
    }

    public func retrieve(for accountId: String) async throws -> OAuthToken? {
        guard let credential = try await retrieveCredential(for: accountId) else { return nil }
        switch credential {
        case .oauth(let token): return token
        case .password: return nil
        }
    }

    public func delete(for accountId: String) async throws {
        try await deleteCredential(for: accountId)
    }

    public func update(_ token: OAuthToken, for accountId: String) async throws {
        try await updateCredential(.oauth(token), for: accountId)
    }
}
