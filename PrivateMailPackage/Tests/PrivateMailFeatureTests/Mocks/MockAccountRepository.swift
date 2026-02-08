import Foundation
@testable import PrivateMailFeature

/// In-memory mock of AccountRepositoryProtocol for testing use cases.
@MainActor
final class MockAccountRepository: AccountRepositoryProtocol {
    var accounts: [Account] = []
    var addCallCount = 0
    var removeCallCount = 0
    var getCallCount = 0
    var updateCallCount = 0
    var refreshCallCount = 0
    var shouldThrowOnAdd = false
    var shouldThrowOnRemove = false
    var shouldThrowOnUpdate = false
    var addError: Error = AccountError.persistenceFailed("mock error")
    var removeError: Error = AccountError.notFound("mock")

    func addAccount(_ account: Account) async throws {
        addCallCount += 1
        if shouldThrowOnAdd {
            throw addError
        }
        // Check for duplicate email (mirrors real implementation)
        if accounts.contains(where: { $0.email == account.email }) {
            throw AccountError.duplicateAccount(account.email)
        }
        accounts.append(account)
    }

    func removeAccount(id: String) async throws {
        removeCallCount += 1
        if shouldThrowOnRemove {
            throw removeError
        }
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountError.notFound(id)
        }
        accounts.remove(at: index)
    }

    func getAccounts() async throws -> [Account] {
        getCallCount += 1
        return accounts.sorted { $0.email < $1.email }
    }

    func updateAccount(_ account: Account) async throws {
        updateCallCount += 1
        if shouldThrowOnUpdate {
            throw AccountError.notFound(account.id)
        }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw AccountError.notFound(account.id)
        }
        accounts[index] = account
    }

    func refreshToken(for accountId: String) async throws -> OAuthToken {
        refreshCallCount += 1
        return OAuthToken(
            accessToken: "refreshed-access",
            refreshToken: "refreshed-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}
