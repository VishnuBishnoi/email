import Foundation
import Security

/// Keychain-based secure storage for account credentials.
///
/// Automatically selects the best keychain backend:
/// - **Data Protection keychain** (`kSecUseDataProtectionKeychain`) when the app
///   is properly signed with a development team. This is the modern iOS-style
///   keychain that never shows password prompts on macOS.
/// - **Legacy login keychain** when the app uses ad-hoc signing (e.g. CLI builds).
///   Legacy keychain calls may show a macOS password prompt. To prevent these
///   blocking prompts from freezing the actor, all SecItem calls are dispatched
///   to a background queue.
///
/// The backend is detected once at init by probing a test write to the Data
/// Protection keychain. If it fails with `errSecMissingEntitlement` (-34018),
/// the manager falls back to the legacy keychain for the session.
///
/// Credentials are JSON-encoded `AccountCredential` values (OAuth tokens or
/// app passwords) scoped per account ID.
///
/// Spec ref: Account Management spec FR-ACCT-04, AC-F-03
///           Multi-provider spec FR-MPROV-06
public actor KeychainManager: KeychainManagerProtocol {

    private let service: String

    /// Whether to use the Data Protection keychain (`true`) or legacy (`false`).
    private let useDataProtection: Bool

    /// Dedicated queue for SecItem calls that may block (legacy keychain prompts).
    private nonisolated let secItemQueue = DispatchQueue(label: "com.vaultmail.keychain", qos: .userInitiated)

    /// Creates a KeychainManager with a configurable service name.
    /// - Parameter service: Keychain service identifier. Defaults to production value.
    ///   Use a unique value in tests for isolation.
    public init(service: String = "com.vaultmail.oauth") {
        self.service = service
        self.useDataProtection = Self.probeDataProtectionKeychain(service: service)
    }

    // MARK: - AccountCredential API (primary)

    public func storeCredential(_ credential: AccountCredential, for accountId: String) async throws {
        let data = try encodeCredential(credential)
        let svc = service
        let useDp = useDataProtection

        let status: OSStatus = await withCheckedContinuation { continuation in
            secItemQueue.async {
                var deleteQuery = Self.makeQuery(service: svc, accountId: accountId, useDataProtection: useDp)
                SecItemDelete(deleteQuery as CFDictionary)

                var addQuery = Self.makeQuery(service: svc, accountId: accountId, useDataProtection: useDp)
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                addQuery[kSecValueData as String] = data

                let result = SecItemAdd(addQuery as CFDictionary, nil)
                continuation.resume(returning: result)
            }
        }

        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status)
        }
    }

    public func retrieveCredential(for accountId: String) async throws -> AccountCredential? {
        let svc = service
        let useDp = useDataProtection

        let (status, data): (OSStatus, Data?) = await withCheckedContinuation { continuation in
            secItemQueue.async {
                var query = Self.makeQuery(service: svc, accountId: accountId, useDataProtection: useDp)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne

                var result: AnyObject?
                let st = SecItemCopyMatching(query as CFDictionary, &result)
                continuation.resume(returning: (st, result as? Data))
            }
        }

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data else {
            throw KeychainError.unableToRetrieve(status)
        }

        return try decodeCredential(data)
    }

    public func deleteCredential(for accountId: String) async throws {
        let svc = service
        let useDp = useDataProtection

        let status: OSStatus = await withCheckedContinuation { continuation in
            secItemQueue.async {
                let query = Self.makeQuery(service: svc, accountId: accountId, useDataProtection: useDp)
                let st = SecItemDelete(query as CFDictionary)
                continuation.resume(returning: st)
            }
        }

        // Ignore "not found" — deleting something that doesn't exist is fine
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    public func updateCredential(_ credential: AccountCredential, for accountId: String) async throws {
        // Delete + store is simpler and safer than SecItemUpdate for JSON blobs
        try await deleteCredential(for: accountId)
        try await storeCredential(credential, for: accountId)
    }

    // MARK: - Query Builder (static, Sendable-safe)

    /// Builds a base keychain query dictionary.
    /// Static so it can be called from `@Sendable` closures without capturing `self`.
    private static func makeQuery(service: String, accountId: String, useDataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    // MARK: - Data Protection Probe

    /// Probes whether the Data Protection keychain is usable.
    ///
    /// Attempts a test write/delete cycle. If `SecItemAdd` returns
    /// `errSecMissingEntitlement` (-34018), the app lacks proper signing
    /// and we fall back to the legacy keychain.
    private static func probeDataProtectionKeychain(service: String) -> Bool {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        // iOS always uses Data Protection keychain
        return true
        #else
        let testAccount = "__keychain_probe_\(UUID().uuidString)"
        let testData = Data("probe".utf8)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: testAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: testData,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            // Clean up the probe item
            query.removeValue(forKey: kSecValueData as String)
            query.removeValue(forKey: kSecAttrAccessible as String)
            SecItemDelete(query as CFDictionary)
            return true
        }

        // -34018 = errSecMissingEntitlement — Data Protection not available
        return false
        #endif
    }

    // MARK: - Encoding

    nonisolated private func encodeCredential(_ credential: AccountCredential) throws -> Data {
        do {
            return try JSONEncoder().encode(credential)
        } catch {
            throw KeychainError.encodingFailed
        }
    }

    /// Decodes credential data with backward compatibility.
    ///
    /// Tries `AccountCredential` first. If that fails, falls back to decoding
    /// as a legacy `OAuthToken` and wraps it as `.oauth(token)`.
    /// This ensures existing Keychain entries from pre-multi-provider versions
    /// continue to work without manual migration.
    nonisolated private func decodeCredential(_ data: Data) throws -> AccountCredential {
        // Try new format first
        if let credential = try? JSONDecoder().decode(AccountCredential.self, from: data) {
            return credential
        }

        // Fall back to legacy OAuthToken format
        do {
            let token = try JSONDecoder().decode(OAuthToken.self, from: data)
            return .oauth(token)
        } catch {
            throw KeychainError.decodingFailed
        }
    }
}
