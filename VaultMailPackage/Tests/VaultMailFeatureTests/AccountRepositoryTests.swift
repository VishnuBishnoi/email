import Foundation
import SwiftData
import Testing
@testable import VaultMailFeature

/// Verify AccountRepositoryImpl CRUD and cascade operations (AC-F-09, AC-SEC-03).
@Suite("Account Repository")
struct AccountRepositoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.createForTesting()
    }

    private func makeToken(
        accessToken: String = "access-token",
        expired: Bool = false
    ) -> OAuthToken {
        OAuthToken(
            accessToken: accessToken,
            refreshToken: "refresh-token",
            expiresAt: expired
                ? Date().addingTimeInterval(-60)
                : Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Add Account

    @Test("addAccount persists account in SwiftData")
    @MainActor
    func addAccountPersists() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let mockOAuth = MockOAuthManager()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: mockOAuth
        )

        let account = Account(email: "test@gmail.com", displayName: "Test User")
        try await repo.addAccount(account)

        let accounts = try await repo.getAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.email == "test@gmail.com")
    }

    @Test("addAccount rejects duplicate email")
    @MainActor
    func addAccountDuplicate() async throws {
        let container = try makeContainer()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: MockKeychainManager(),
            oauthManager: MockOAuthManager()
        )

        let account1 = Account(email: "test@gmail.com", displayName: "User 1")
        try await repo.addAccount(account1)

        let account2 = Account(email: "test@gmail.com", displayName: "User 2")
        await #expect(throws: AccountError.self) {
            try await repo.addAccount(account2)
        }
    }

    // MARK: - Get Accounts

    @Test("getAccounts returns all accounts sorted by email")
    @MainActor
    func getAccountsSorted() async throws {
        let container = try makeContainer()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: MockKeychainManager(),
            oauthManager: MockOAuthManager()
        )

        try await repo.addAccount(Account(email: "charlie@gmail.com", displayName: "Charlie"))
        try await repo.addAccount(Account(email: "alice@gmail.com", displayName: "Alice"))
        try await repo.addAccount(Account(email: "bob@gmail.com", displayName: "Bob"))

        let accounts = try await repo.getAccounts()
        #expect(accounts.count == 3)
        #expect(accounts[0].email == "alice@gmail.com")
        #expect(accounts[1].email == "bob@gmail.com")
        #expect(accounts[2].email == "charlie@gmail.com")
    }

    // MARK: - Remove Account

    @Test("removeAccount deletes account from SwiftData")
    @MainActor
    func removeAccountDeletesFromSwiftData() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: MockOAuthManager()
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        try await repo.removeAccount(id: account.id)

        let accounts = try await repo.getAccounts()
        #expect(accounts.isEmpty)
    }

    @Test("removeAccount deletes Keychain tokens")
    @MainActor
    func removeAccountDeletesKeychain() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: MockOAuthManager()
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        // Store a token for this account
        try await mockKeychain.store(makeToken(), for: account.id)

        try await repo.removeAccount(id: account.id)

        let deleteCount = await mockKeychain.deleteCallCount
        #expect(deleteCount == 1, "Keychain delete should be called on account removal")

        let token = try await mockKeychain.retrieve(for: account.id)
        #expect(token == nil, "Token should be deleted from Keychain")
    }

    @Test("removeAccount with cascade deletes child data")
    @MainActor
    func removeAccountCascade() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mockKeychain = MockKeychainManager()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: MockOAuthManager()
        )

        // Build a full hierarchy
        let account = Account(email: "cascade@gmail.com", displayName: "Cascade Test")
        context.insert(account)

        let folder = Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue)
        folder.account = account
        context.insert(folder)

        let thread = Thread(accountId: account.id, subject: "Test")
        context.insert(thread)

        let email = Email(
            accountId: account.id,
            threadId: thread.id,
            messageId: "<msg@test.com>",
            fromAddress: "sender@test.com",
            subject: "Test"
        )
        email.thread = thread
        context.insert(email)

        let emailFolder = EmailFolder(imapUID: 42)
        emailFolder.email = email
        emailFolder.folder = folder
        context.insert(emailFolder)

        let attachment = VaultMailFeature.Attachment(
            filename: "file.txt",
            mimeType: "text/plain",
            sizeBytes: 100
        )
        attachment.email = email
        context.insert(attachment)

        try context.save()

        // Remove account
        try await repo.removeAccount(id: account.id)

        // Verify all children deleted
        let verifyContext = ModelContext(container)
        let folders = try verifyContext.fetch(FetchDescriptor<Folder>())
        let emails = try verifyContext.fetch(FetchDescriptor<Email>())
        let emailFolders = try verifyContext.fetch(FetchDescriptor<EmailFolder>())
        let attachments = try verifyContext.fetch(FetchDescriptor<VaultMailFeature.Attachment>())

        #expect(folders.isEmpty, "Folders should be cascade deleted")
        #expect(emails.isEmpty, "Emails should be cascade deleted")
        #expect(emailFolders.isEmpty, "EmailFolders should be cascade deleted")
        #expect(attachments.isEmpty, "Attachments should be cascade deleted")
    }

    @Test("removeAccount throws for non-existent account")
    @MainActor
    func removeAccountNotFound() async throws {
        let container = try makeContainer()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: MockKeychainManager(),
            oauthManager: MockOAuthManager()
        )

        await #expect(throws: AccountError.self) {
            try await repo.removeAccount(id: "non-existent")
        }
    }

    // MARK: - Update Account

    @Test("updateAccount persists changes")
    @MainActor
    func updateAccountPersists() async throws {
        let container = try makeContainer()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: MockKeychainManager(),
            oauthManager: MockOAuthManager()
        )

        let account = Account(email: "test@gmail.com", displayName: "Original")
        try await repo.addAccount(account)

        // Create a modified copy
        let updated = Account(
            id: account.id,
            email: "test@gmail.com",
            displayName: "Updated Name",
            syncWindowDays: 60
        )
        try await repo.updateAccount(updated)

        let accounts = try await repo.getAccounts()
        #expect(accounts.first?.displayName == "Updated Name")
        #expect(accounts.first?.syncWindowDays == 60)
    }

    // MARK: - Refresh Token

    @Test("refreshToken returns existing token when not expired")
    @MainActor
    func refreshTokenReturnsExistingWhenValid() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let mockOAuth = MockOAuthManager()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: mockOAuth
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        let token = makeToken()
        try await mockKeychain.store(token, for: account.id)

        let result = try await repo.refreshToken(for: account.id)
        #expect(result.accessToken == "access-token")
        #expect(mockOAuth.refreshCallCount == 0, "Should not call OAuth refresh for valid token")
    }

    @Test("refreshToken calls OAuthManager for expired token")
    @MainActor
    func refreshTokenCallsOAuthForExpired() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let mockOAuth = MockOAuthManager()

        let newToken = makeToken(accessToken: "new-access-token")
        mockOAuth.refreshResult = .success(newToken)

        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: mockOAuth
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        let expiredToken = makeToken(expired: true)
        try await mockKeychain.store(expiredToken, for: account.id)

        let result = try await repo.refreshToken(for: account.id)
        #expect(result.accessToken == "new-access-token")
        #expect(mockOAuth.refreshCallCount == 1)

        let storedToken = try await mockKeychain.retrieve(for: account.id)
        #expect(storedToken?.accessToken == "new-access-token", "New token should be stored in Keychain")
    }

    @Test("refreshToken deactivates account on max retries")
    @MainActor
    func refreshTokenDeactivatesOnMaxRetries() async throws {
        let container = try makeContainer()
        let mockKeychain = MockKeychainManager()
        let mockOAuth = MockOAuthManager()
        mockOAuth.refreshResult = .failure(OAuthError.maxRetriesExceeded)

        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: mockKeychain,
            oauthManager: mockOAuth
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        let expiredToken = makeToken(expired: true)
        try await mockKeychain.store(expiredToken, for: account.id)

        await #expect(throws: AccountError.self) {
            try await repo.refreshToken(for: account.id)
        }

        // Verify account is deactivated
        let accounts = try await repo.getAccounts()
        #expect(accounts.first?.isActive == false, "Account should be deactivated on max retries")
    }

    @Test("refreshToken throws when no token in Keychain")
    @MainActor
    func refreshTokenThrowsNoToken() async throws {
        let container = try makeContainer()
        let repo = AccountRepositoryImpl(
            modelContainer: container,
            keychainManager: MockKeychainManager(),
            oauthManager: MockOAuthManager()
        )

        let account = Account(email: "test@gmail.com", displayName: "Test")
        try await repo.addAccount(account)

        await #expect(throws: AccountError.self) {
            try await repo.refreshToken(for: account.id)
        }
    }
}
