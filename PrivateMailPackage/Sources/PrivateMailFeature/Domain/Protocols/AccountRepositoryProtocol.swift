import Foundation

/// Repository protocol for account management operations.
///
/// Isolated to `@MainActor` because SwiftData `@Model` types are not
/// `Sendable` and must be accessed on the main actor.
///
/// Implementations live in the Data layer. The Domain layer depends only
/// on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Foundation spec Section 6, Account Management spec FR-ACCT-01..05
@MainActor
public protocol AccountRepositoryProtocol {
    /// Add a new account with its configuration.
    func addAccount(_ account: Account) async throws
    /// Remove an account and all associated data (FR-FOUND-03 cascade).
    func removeAccount(id: String) async throws
    /// Retrieve all configured accounts.
    func getAccounts() async throws -> [Account]
    /// Update an existing account's configuration.
    func updateAccount(_ account: Account) async throws
    /// Refresh the OAuth token for an account (FR-ACCT-04).
    /// On max retries exhausted, sets account.isActive = false.
    func refreshToken(for accountId: String) async throws -> OAuthToken
}
