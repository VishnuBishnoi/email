import Foundation
import Testing
@testable import VaultMailFeature

@Suite("ManageAccountsUseCase")
struct ManageAccountsUseCaseTests {

    // MARK: - Helpers

    private static func makeToken(accessToken: String = "test-access", refreshToken: String = "test-refresh") -> OAuthToken {
        OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    /// Creates a use case with mock dependencies and a fixed email resolver.
    @MainActor
    private static func makeSUT(
        email: String = "user@gmail.com",
        oauthResult: Result<OAuthToken, Error>? = nil,
        shouldThrowOnAdd: Bool = false
    ) -> (ManageAccountsUseCase, MockAccountRepository, MockOAuthManager, MockKeychainManager) {
        let repo = MockAccountRepository()
        repo.shouldThrowOnAdd = shouldThrowOnAdd
        let oauth = MockOAuthManager()
        oauth.authenticateResult = oauthResult ?? .success(makeToken())
        let keychain = MockKeychainManager()

        let resolver: EmailResolver = { _ in email }

        let useCase = ManageAccountsUseCase(
            repository: repo,
            oauthManager: oauth,
            keychainManager: keychain,
            resolveEmail: resolver
        )
        return (useCase, repo, oauth, keychain)
    }

    // MARK: - addAccountViaOAuth

    @Test("addAccountViaOAuth creates account with Gmail defaults")
    @MainActor
    func addAccountHappyPath() async throws {
        let (useCase, repo, oauth, keychain) = Self.makeSUT(email: "test@gmail.com")

        let account = try await useCase.addAccountViaOAuth()

        #expect(account.email == "test@gmail.com")
        #expect(account.displayName == "test")
        #expect(account.imapHost == AppConstants.gmailImapHost)
        #expect(account.imapPort == AppConstants.gmailImapPort)
        #expect(account.smtpHost == AppConstants.gmailSmtpHost)
        #expect(account.smtpPort == AppConstants.gmailSmtpPort)
        #expect(account.isActive == true)
        #expect(account.syncWindowDays == AppConstants.defaultSyncWindowDays)

        // Verify OAuth was called
        #expect(oauth.authenticateCallCount == 1)

        // Verify token stored in Keychain
        let storedToken = await keychain.storage[account.id]
        #expect(storedToken != nil)
        #expect(storedToken?.accessToken == "test-access")

        // Verify account persisted in repository
        #expect(repo.accounts.count == 1)
        #expect(repo.addCallCount == 1)
    }

    @Test("addAccountViaOAuth throws when OAuth is cancelled")
    @MainActor
    func addAccountOAuthCancelled() async throws {
        let (useCase, _, _, _) = Self.makeSUT(
            oauthResult: .failure(OAuthError.authenticationCancelled)
        )

        await #expect(throws: OAuthError.self) {
            _ = try await useCase.addAccountViaOAuth()
        }
    }

    @Test("addAccountViaOAuth throws when OAuth network fails")
    @MainActor
    func addAccountOAuthNetworkError() async throws {
        let (useCase, _, _, _) = Self.makeSUT(
            oauthResult: .failure(OAuthError.networkError("No internet"))
        )

        await #expect(throws: OAuthError.self) {
            _ = try await useCase.addAccountViaOAuth()
        }
    }

    @Test("addAccountViaOAuth throws on duplicate email")
    @MainActor
    func addAccountDuplicate() async throws {
        let (useCase, repo, _, _) = Self.makeSUT(email: "existing@gmail.com")

        // Pre-populate with existing account
        let existing = Account(email: "existing@gmail.com", displayName: "Existing")
        repo.accounts.append(existing)

        await #expect(throws: AccountError.self) {
            _ = try await useCase.addAccountViaOAuth()
        }
    }

    @Test("addAccountViaOAuth rolls back Keychain on persistence failure")
    @MainActor
    func addAccountRollsBackKeychain() async throws {
        let (useCase, _, _, keychain) = Self.makeSUT(shouldThrowOnAdd: true)

        await #expect(throws: Error.self) {
            _ = try await useCase.addAccountViaOAuth()
        }

        // Keychain should have been cleaned up (store then delete)
        let storeCount = await keychain.storeCallCount
        let deleteCount = await keychain.deleteCallCount
        #expect(storeCount == 1)
        #expect(deleteCount == 1)
        let storageCount = await keychain.storage.count
        #expect(storageCount == 0)
    }

    // MARK: - removeAccount

    @Test("removeAccount returns true when last account removed")
    @MainActor
    func removeLastAccount() async throws {
        let (useCase, repo, _, _) = Self.makeSUT()

        let account = Account(id: "acc-1", email: "user@gmail.com", displayName: "User")
        repo.accounts.append(account)

        let wasLast = try await useCase.removeAccount(id: "acc-1")

        #expect(wasLast == true)
        #expect(repo.accounts.isEmpty)
        #expect(repo.removeCallCount == 1)
    }

    @Test("removeAccount returns false when accounts remain")
    @MainActor
    func removeNonLastAccount() async throws {
        let (useCase, repo, _, _) = Self.makeSUT()

        repo.accounts.append(Account(id: "acc-1", email: "a@gmail.com", displayName: "A"))
        repo.accounts.append(Account(id: "acc-2", email: "b@gmail.com", displayName: "B"))

        let wasLast = try await useCase.removeAccount(id: "acc-1")

        #expect(wasLast == false)
        #expect(repo.accounts.count == 1)
    }

    @Test("removeAccount throws for non-existent account")
    @MainActor
    func removeAccountNotFound() async throws {
        let (useCase, _, _, _) = Self.makeSUT()

        await #expect(throws: AccountError.self) {
            _ = try await useCase.removeAccount(id: "nonexistent")
        }
    }

    // MARK: - getAccounts

    @Test("getAccounts returns all accounts sorted by email")
    @MainActor
    func getAccountsSorted() async throws {
        let (useCase, repo, _, _) = Self.makeSUT()

        repo.accounts.append(Account(email: "z@gmail.com", displayName: "Z"))
        repo.accounts.append(Account(email: "a@gmail.com", displayName: "A"))

        let accounts = try await useCase.getAccounts()

        #expect(accounts.count == 2)
        #expect(accounts[0].email == "a@gmail.com")
        #expect(accounts[1].email == "z@gmail.com")
    }

    // MARK: - updateAccount

    @Test("updateAccount delegates to repository")
    @MainActor
    func updateAccountDelegates() async throws {
        let (useCase, repo, _, _) = Self.makeSUT()

        let account = Account(id: "acc-1", email: "user@gmail.com", displayName: "User")
        repo.accounts.append(account)

        account.displayName = "Updated Name"
        account.syncWindowDays = 7

        try await useCase.updateAccount(account)

        #expect(repo.updateCallCount == 1)
        #expect(repo.accounts.first?.displayName == "Updated Name")
        #expect(repo.accounts.first?.syncWindowDays == 7)
    }

    // MARK: - reAuthenticateAccount

    @Test("reAuthenticateAccount re-activates inactive account")
    @MainActor
    func reAuthenticateAccount() async throws {
        let (useCase, repo, oauth, keychain) = Self.makeSUT()

        let account = Account(id: "acc-1", email: "user@gmail.com", displayName: "User", isActive: false)
        repo.accounts.append(account)

        try await useCase.reAuthenticateAccount(id: "acc-1")

        // OAuth was called
        #expect(oauth.authenticateCallCount == 1)

        // Token updated in Keychain
        let updateCount = await keychain.updateCallCount
        #expect(updateCount == 1)

        // Account is now active
        #expect(repo.accounts.first?.isActive == true)
        #expect(repo.updateCallCount == 1)
    }

    @Test("reAuthenticateAccount throws for non-existent account")
    @MainActor
    func reAuthenticateAccountNotFound() async throws {
        let (useCase, _, _, _) = Self.makeSUT()

        await #expect(throws: AccountError.self) {
            try await useCase.reAuthenticateAccount(id: "nonexistent")
        }
    }

    // MARK: - IMAP Validation Failure Rollback

    private final class FailingConnectionProvider: ConnectionProviding, @unchecked Sendable {
        func checkoutConnection(
            accountId: String,
            host: String,
            port: Int,
            email: String,
            accessToken: String
        ) async throws -> any IMAPClientProtocol {
            throw NSError(domain: "IMAP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {}
    }

    @Test("addAccountViaOAuth rolls back on IMAP validation failure")
    @MainActor
    func addAccountIMAPValidationFailureRollsBack() async throws {
        let repo = MockAccountRepository()
        let oauth = MockOAuthManager()
        oauth.authenticateResult = .success(Self.makeToken())
        let keychain = MockKeychainManager()
        let failingProvider = FailingConnectionProvider()

        let useCase = ManageAccountsUseCase(
            repository: repo,
            oauthManager: oauth,
            keychainManager: keychain,
            connectionProvider: failingProvider,
            resolveEmail: { _ in "test@gmail.com" }
        )

        await #expect(throws: AccountError.self) {
            _ = try await useCase.addAccountViaOAuth()
        }

        // Account should have been rolled back (added then removed)
        #expect(repo.addCallCount == 1)
        #expect(repo.removeCallCount == 1)
        #expect(repo.accounts.isEmpty)

        // Keychain should have been cleaned up (store then delete)
        let storeCount = await keychain.storeCallCount
        let deleteCount = await keychain.deleteCallCount
        #expect(storeCount == 1)
        #expect(deleteCount == 1)
        let storageCount = await keychain.storage.count
        #expect(storageCount == 0)
    }
}
