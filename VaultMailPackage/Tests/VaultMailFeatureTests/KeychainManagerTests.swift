import Foundation
import Security
import Testing
@testable import VaultMailFeature

/// Returns `true` when the Keychain is accessible in the current
/// test environment. On iOS Simulator SPM test bundles without
/// entitlements, `SecItemAdd` returns -34018 (`errSecMissingEntitlement`).
private func keychainAvailable() -> Bool {
    let accountId = UUID().uuidString
    let probe: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.vaultmail.test.probe",
        kSecAttrAccount as String: accountId,
        kSecValueData as String: Data("probe".utf8),
    ]

    let status = SecItemAdd(probe as CFDictionary, nil)

    if status == errSecSuccess || status == errSecDuplicateItem {
        // Clean up the probe entry
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vaultmail.test.probe",
            kSecAttrAccount as String: accountId,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        return true
    }

    return false
}

/// Verify KeychainManager CRUD operations (AC-F-03).
///
/// These tests interact with the real Keychain. On iOS Simulator the
/// SPM test runner lacks entitlements (OSStatus -34018), so the entire
/// suite is disabled when the Keychain is unavailable.
/// Run via `swift test` on macOS for full Keychain coverage.
@Suite("Keychain Manager", .enabled(if: keychainAvailable(), "Keychain not accessible — run via `swift test` on macOS"))
struct KeychainManagerTests {

    /// Use a unique service name to isolate test data from production.
    private let testService = "com.vaultmail.test.\(UUID().uuidString)"

    private func makeManager() -> KeychainManager {
        KeychainManager(service: testService)
    }

    private func makeToken(
        accessToken: String = "access-123",
        refreshToken: String = "refresh-456"
    ) -> OAuthToken {
        OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Store and Retrieve

    @Test("Store and retrieve token successfully")
    func storeAndRetrieve() async throws {
        let manager = makeManager()
        let token = makeToken()
        let accountId = "test-account-\(UUID().uuidString)"

        try await manager.store(token, for: accountId)

        let retrieved = try await manager.retrieve(for: accountId)
        #expect(retrieved != nil)
        #expect(retrieved?.accessToken == "access-123")
        #expect(retrieved?.refreshToken == "refresh-456")

        // Cleanup
        try await manager.delete(for: accountId)
    }

    // MARK: - Update

    @Test("Update token replaces existing value")
    func updateToken() async throws {
        let manager = makeManager()
        let accountId = "test-account-\(UUID().uuidString)"

        let original = makeToken(accessToken: "original")
        try await manager.store(original, for: accountId)

        let updated = makeToken(accessToken: "updated")
        try await manager.update(updated, for: accountId)

        let retrieved = try await manager.retrieve(for: accountId)
        #expect(retrieved?.accessToken == "updated")

        // Cleanup
        try await manager.delete(for: accountId)
    }

    // MARK: - Delete

    @Test("Delete token makes it unretrievable")
    func deleteToken() async throws {
        let manager = makeManager()
        let accountId = "test-account-\(UUID().uuidString)"

        let token = makeToken()
        try await manager.store(token, for: accountId)
        try await manager.delete(for: accountId)

        let retrieved = try await manager.retrieve(for: accountId)
        #expect(retrieved == nil)
    }

    // MARK: - Not Found

    @Test("Retrieve non-existent token returns nil")
    func retrieveNonExistent() async throws {
        let manager = makeManager()

        let retrieved = try await manager.retrieve(for: "non-existent-\(UUID().uuidString)")
        #expect(retrieved == nil)
    }

    @Test("Delete non-existent token does not throw")
    func deleteNonExistent() async throws {
        let manager = makeManager()

        // Should not throw
        try await manager.delete(for: "non-existent-\(UUID().uuidString)")
    }

    // MARK: - Store Duplicate

    @Test("Storing token for existing account updates it")
    func storeDuplicate() async throws {
        let manager = makeManager()
        let accountId = "test-account-\(UUID().uuidString)"

        let first = makeToken(accessToken: "first")
        try await manager.store(first, for: accountId)

        let second = makeToken(accessToken: "second")
        try await manager.store(second, for: accountId)

        let retrieved = try await manager.retrieve(for: accountId)
        #expect(retrieved?.accessToken == "second")

        // Cleanup
        try await manager.delete(for: accountId)
    }

    // MARK: - Account Isolation

    @Test("Tokens are scoped by account ID")
    func accountIsolation() async throws {
        let manager = makeManager()
        let accountA = "test-account-a-\(UUID().uuidString)"
        let accountB = "test-account-b-\(UUID().uuidString)"

        try await manager.store(makeToken(accessToken: "token-a"), for: accountA)
        try await manager.store(makeToken(accessToken: "token-b"), for: accountB)

        let retrievedA = try await manager.retrieve(for: accountA)
        let retrievedB = try await manager.retrieve(for: accountB)

        #expect(retrievedA?.accessToken == "token-a")
        #expect(retrievedB?.accessToken == "token-b")

        // Cleanup
        try await manager.delete(for: accountA)
        try await manager.delete(for: accountB)
    }
}
