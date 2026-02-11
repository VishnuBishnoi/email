import Foundation
import Security

/// Keychain-based secure storage for OAuth tokens.
///
/// Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for maximum
/// security. Tokens are JSON-encoded and scoped per account ID.
///
/// Spec ref: Account Management spec FR-ACCT-04, AC-F-03
public actor KeychainManager: KeychainManagerProtocol {

    private let service: String

    /// Creates a KeychainManager with a configurable service name.
    /// - Parameter service: Keychain service identifier. Defaults to production value.
    ///   Use a unique value in tests for isolation.
    public init(service: String = "com.vaultmail.oauth") {
        self.service = service
    }

    // MARK: - KeychainManagerProtocol

    public func store(_ token: OAuthToken, for accountId: String) async throws {
        let data = try encode(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]

        // Delete any existing item first to avoid errSecDuplicateItem
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status)
        }
    }

    public func retrieve(for accountId: String) async throws -> OAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unableToRetrieve(status)
        }

        return try decode(data)
    }

    public func delete(for accountId: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Ignore "not found" — deleting something that doesn't exist is fine
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    public func update(_ token: OAuthToken, for accountId: String) async throws {
        // Delete + store is simpler and safer than SecItemUpdate for JSON blobs
        try await delete(for: accountId)
        try await store(token, for: accountId)
    }

    // MARK: - Encoding

    private func encode(_ token: OAuthToken) throws -> Data {
        do {
            return try JSONEncoder().encode(token)
        } catch {
            throw KeychainError.encodingFailed
        }
    }

    private func decode(_ data: Data) throws -> OAuthToken {
        do {
            return try JSONDecoder().decode(OAuthToken.self, from: data)
        } catch {
            throw KeychainError.decodingFailed
        }
    }
}
