import Foundation
@testable import VaultMailFeature

/// In-memory mock of KeychainManagerProtocol for testing.
actor MockKeychainManager: KeychainManagerProtocol {
    var storage: [String: OAuthToken] = [:]
    var storeCallCount = 0
    var retrieveCallCount = 0
    var deleteCallCount = 0
    var updateCallCount = 0
    var shouldThrowOnStore = false
    var shouldThrowOnRetrieve = false
    var shouldThrowOnDelete = false

    func store(_ token: OAuthToken, for accountId: String) async throws {
        storeCallCount += 1
        if shouldThrowOnStore {
            throw KeychainError.unableToStore(-1)
        }
        storage[accountId] = token
    }

    func retrieve(for accountId: String) async throws -> OAuthToken? {
        retrieveCallCount += 1
        if shouldThrowOnRetrieve {
            throw KeychainError.unableToRetrieve(-1)
        }
        return storage[accountId]
    }

    func delete(for accountId: String) async throws {
        deleteCallCount += 1
        if shouldThrowOnDelete {
            throw KeychainError.unableToDelete(-1)
        }
        storage.removeValue(forKey: accountId)
    }

    func update(_ token: OAuthToken, for accountId: String) async throws {
        updateCallCount += 1
        storage[accountId] = token
    }
}
