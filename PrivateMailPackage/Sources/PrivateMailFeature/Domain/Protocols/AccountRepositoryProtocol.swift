import Foundation

/// Repository protocol for account management operations.
///
/// Implementations live in the Data layer. The Domain layer depends only
/// on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Foundation spec Section 6
public protocol AccountRepositoryProtocol: Sendable {
    /// Add a new account with its configuration.
    func addAccount(_ account: Account) async throws
    /// Remove an account and all associated data (FR-FOUND-03 cascade).
    func removeAccount(id: String) async throws
    /// Retrieve all configured accounts.
    func getAccounts() async throws -> [Account]
    /// Update an existing account's configuration.
    func updateAccount(_ account: Account) async throws
}
