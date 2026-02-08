import Foundation
import SwiftData

/// SwiftData-backed implementation of AccountRepositoryProtocol.
///
/// Manages account CRUD operations and integrates with Keychain for
/// token storage and OAuthManager for token refresh.
///
/// Spec ref: Account Management spec FR-ACCT-01..05, AC-F-09
@MainActor
public final class AccountRepositoryImpl: AccountRepositoryProtocol {

    private let modelContainer: ModelContainer
    private let keychainManager: KeychainManagerProtocol
    private let oauthManager: OAuthManagerProtocol

    /// Single shared context for all operations. Safe because this class is @MainActor.
    private var context: ModelContext {
        modelContainer.mainContext
    }

    public init(
        modelContainer: ModelContainer,
        keychainManager: KeychainManagerProtocol,
        oauthManager: OAuthManagerProtocol
    ) {
        self.modelContainer = modelContainer
        self.keychainManager = keychainManager
        self.oauthManager = oauthManager
    }

    // MARK: - AccountRepositoryProtocol

    public func addAccount(_ account: Account) async throws {


        // Check for duplicate email
        let email = account.email
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.email == email }
        )
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor)
        if !existing.isEmpty {
            throw AccountError.duplicateAccount(email)
        }

        context.insert(account)
        try context.save()
    }

    public func removeAccount(id: String) async throws {


        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let account = try context.fetch(descriptor).first else {
            throw AccountError.notFound(id)
        }

        // Delete Keychain tokens (FR-ACCT-05)
        try await keychainManager.delete(for: id)

        // Delete threads for this account (Thread stores accountId as a field,
        // not a relationship, so it won't cascade from Account deletion).
        // Thread cascade handles Email → EmailFolder + Attachment cleanup.
        let threadDescriptor = FetchDescriptor<Thread>(
            predicate: #Predicate { $0.accountId == id }
        )
        let threads = try context.fetch(threadDescriptor)
        for thread in threads {
            context.delete(thread)
        }

        // Delete account — SwiftData cascade handles folders → emailFolders (FR-FOUND-03)
        context.delete(account)
        try context.save()
    }

    public func getAccounts() async throws -> [Account] {


        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.email)]
        )

        return try context.fetch(descriptor)
    }

    public func updateAccount(_ account: Account) async throws {


        let id = account.id
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let existing = try context.fetch(descriptor).first else {
            throw AccountError.notFound(id)
        }

        existing.displayName = account.displayName
        existing.syncWindowDays = account.syncWindowDays
        existing.isActive = account.isActive
        existing.imapHost = account.imapHost
        existing.imapPort = account.imapPort
        existing.smtpHost = account.smtpHost
        existing.smtpPort = account.smtpPort

        try context.save()
    }

    public func refreshToken(for accountId: String) async throws -> OAuthToken {
        // Retrieve current token
        guard let currentToken = try await keychainManager.retrieve(for: accountId) else {
            throw AccountError.keychainFailure(.itemNotFound)
        }

        // If not expired or near-expiry, return as-is
        if !currentToken.isExpired && !currentToken.isNearExpiry {
            return currentToken
        }

        // Attempt refresh with retry
        do {
            let newToken = try await oauthManager.refreshToken(currentToken)
            try await keychainManager.update(newToken, for: accountId)
            return newToken
        } catch let error as OAuthError where error == .maxRetriesExceeded {
            // Deactivate account on max retries (FR-ACCT-04)
            try await deactivateAccount(id: accountId)
            throw AccountError.oauthFailure(error)
        }
    }

    // MARK: - Private

    private func deactivateAccount(id: String) async throws {


        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let account = try context.fetch(descriptor).first else { return }

        account.isActive = false
        try context.save()
    }
}

// MARK: - OAuthError Equatable

extension OAuthError: Equatable {
    public static func == (lhs: OAuthError, rhs: OAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.authenticationCancelled, .authenticationCancelled),
             (.invalidAuthorizationCode, .invalidAuthorizationCode),
             (.invalidResponse, .invalidResponse),
             (.maxRetriesExceeded, .maxRetriesExceeded),
             (.noRefreshToken, .noRefreshToken):
            true
        case (.tokenExchangeFailed(let a), .tokenExchangeFailed(let b)),
             (.tokenRefreshFailed(let a), .tokenRefreshFailed(let b)),
             (.networkError(let a), .networkError(let b)):
            a == b
        default:
            false
        }
    }
}
