import Foundation
@testable import VaultMailFeature

/// In-memory mock of KeychainManagerProtocol for testing.
///
/// Stores `AccountCredential` values (supports both OAuth and password).
/// Also maintains backward-compatible `OAuthToken` storage view for legacy tests.
actor MockKeychainManager: KeychainManagerProtocol {
    var credentialStorage: [String: AccountCredential] = [:]
    var storeCallCount = 0
    var retrieveCallCount = 0
    var deleteCallCount = 0
    var updateCallCount = 0
    var storeCredentialCallCount = 0
    var retrieveCredentialCallCount = 0
    var deleteCredentialCallCount = 0
    var updateCredentialCallCount = 0
    var shouldThrowOnStore = false
    var shouldThrowOnRetrieve = false
    var shouldThrowOnDelete = false

    // MARK: - AccountCredential API (primary)

    func storeCredential(_ credential: AccountCredential, for accountId: String) async throws {
        storeCredentialCallCount += 1
        storeCallCount += 1
        if shouldThrowOnStore {
            throw KeychainError.unableToStore(-1)
        }
        credentialStorage[accountId] = credential
    }

    func retrieveCredential(for accountId: String) async throws -> AccountCredential? {
        retrieveCredentialCallCount += 1
        retrieveCallCount += 1
        if shouldThrowOnRetrieve {
            throw KeychainError.unableToRetrieve(-1)
        }
        return credentialStorage[accountId]
    }

    func deleteCredential(for accountId: String) async throws {
        deleteCredentialCallCount += 1
        deleteCallCount += 1
        if shouldThrowOnDelete {
            throw KeychainError.unableToDelete(-1)
        }
        credentialStorage.removeValue(forKey: accountId)
    }

    func updateCredential(_ credential: AccountCredential, for accountId: String) async throws {
        updateCredentialCallCount += 1
        updateCallCount += 1
        credentialStorage[accountId] = credential
    }

    // MARK: - Convenience for tests

    /// Backward-compatible storage accessor (returns OAuthToken if stored as .oauth).
    var storage: [String: OAuthToken] {
        var result: [String: OAuthToken] = [:]
        for (key, credential) in credentialStorage {
            if case .oauth(let token) = credential {
                result[key] = token
            }
        }
        return result
    }

    /// Convenience to store an OAuthToken directly (wraps as .oauth).
    func storeToken(_ token: OAuthToken, for accountId: String) async throws {
        try await storeCredential(.oauth(token), for: accountId)
    }

    /// Convenience to store an app password directly.
    func storePassword(_ password: String, for accountId: String) async throws {
        try await storeCredential(.password(password), for: accountId)
    }
}
