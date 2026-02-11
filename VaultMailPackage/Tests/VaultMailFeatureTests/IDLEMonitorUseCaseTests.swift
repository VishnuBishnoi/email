import Foundation
import Testing
@testable import VaultMailFeature

@Suite("IDLEMonitorUseCase Tests")
@MainActor
struct IDLEMonitorUseCaseTests {

    // MARK: - Mock Connection Provider

    /// Simple mock that returns the same MockIMAPClient.
    private final class MockConnectionProvider: ConnectionProviding, @unchecked Sendable {
        let client: MockIMAPClient
        var checkoutCount = 0
        var checkinCount = 0
        var shouldThrowOnCheckout = false

        init(client: MockIMAPClient) {
            self.client = client
        }

        func checkoutConnection(
            accountId: String,
            host: String,
            port: Int,
            email: String,
            accessToken: String
        ) async throws -> any IMAPClientProtocol {
            checkoutCount += 1
            if shouldThrowOnCheckout {
                throw NSError(domain: "IDLETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection checkout failed"])
            }
            return client
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {
            checkinCount += 1
        }
    }

    // MARK: - Helpers

    private let accountRepo = MockAccountRepository()
    private let keychainManager = MockKeychainManager()
    private let mockIMAPClient = MockIMAPClient()

    private var connectionProvider: MockConnectionProvider {
        MockConnectionProvider(client: mockIMAPClient)
    }

    private func createAccount(
        id: String = "acc-1",
        email: String = "test@gmail.com",
        isActive: Bool = true
    ) -> Account {
        let account = Account(
            id: id,
            email: email,
            displayName: "Test",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587,
            isActive: isActive
        )
        return account
    }

    private func addAccountWithToken(_ account: Account) async throws {
        accountRepo.accounts.append(account)
        let token = OAuthToken(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await keychainManager.store(token, for: account.id)
    }

    // MARK: - Tests

    @Test("Monitor emits .newMail when IDLE callback fires")
    func monitorEmitsNewMail() async throws {
        let account = createAccount()
        try await addAccountWithToken(account)

        let provider = connectionProvider
        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "INBOX")

        // Give the IDLE setup a moment to register
        try await Task.sleep(for: .milliseconds(100))

        // Simulate new mail
        mockIMAPClient.simulateNewMail()

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
            if events.count >= 1 { break }
        }

        #expect(events.contains(.newMail))
        #expect(mockIMAPClient.startIDLECallCount == 1)
        #expect(mockIMAPClient.selectFolderCallCount == 1)
        #expect(mockIMAPClient.lastSelectedPath == "INBOX")
    }

    @Test("Monitor emits .disconnected when account not found")
    func monitorAccountNotFound() async throws {
        // Don't add any accounts
        let provider = connectionProvider
        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: "nonexistent", folderImapPath: "INBOX")

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events == [.disconnected])
        #expect(mockIMAPClient.startIDLECallCount == 0)
    }

    @Test("Monitor emits .disconnected when no token found")
    func monitorNoToken() async throws {
        let account = createAccount()
        accountRepo.accounts.append(account)
        // Don't store a token

        let provider = connectionProvider
        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "INBOX")

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events == [.disconnected])
    }

    @Test("Monitor emits .disconnected when IDLE start fails")
    func monitorIDLEStartFails() async throws {
        let account = createAccount()
        try await addAccountWithToken(account)

        mockIMAPClient.startIDLEError = .connectionFailed("IDLE failed")

        let provider = connectionProvider
        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "INBOX")

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events == [.disconnected])
    }

    @Test("Monitor checks in connection when selectFolder throws")
    func monitorChecksInConnectionOnSelectFolderFailure() async throws {
        let account = createAccount()
        try await addAccountWithToken(account)

        let provider = connectionProvider
        let failingClient = provider.client
        failingClient.selectFolderResult = .failure(.commandFailed("SELECT failed"))

        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "INBOX")

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events == [.disconnected])
        #expect(provider.checkoutCount == 1)
        // Connection must be returned even though selectFolder threw
        // Give the deferred Task a moment to execute
        try await Task.sleep(for: .milliseconds(100))
        #expect(provider.checkinCount == 1)
    }

    @Test("Monitor selects correct folder before starting IDLE")
    func monitorSelectsFolder() async throws {
        let account = createAccount()
        try await addAccountWithToken(account)

        let provider = connectionProvider
        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "[Gmail]/Sent Mail")

        // Give setup a moment
        try await Task.sleep(for: .milliseconds(100))

        // Verify folder was selected before IDLE started
        #expect(mockIMAPClient.selectFolderCallCount == 1)
        #expect(mockIMAPClient.lastSelectedPath == "[Gmail]/Sent Mail")

        // Cancel the stream to clean up
        _ = stream // keep reference
    }

    @Test("Monitor emits .disconnected when connection checkout fails")
    func monitorConnectionCheckoutFails() async throws {
        let account = createAccount()
        try await addAccountWithToken(account)

        let provider = connectionProvider
        provider.shouldThrowOnCheckout = true

        let sut = IDLEMonitorUseCase(
            connectionProvider: provider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        let stream = sut.monitor(accountId: account.id, folderImapPath: "INBOX")

        var events: [IDLEEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events == [.disconnected])
        #expect(provider.checkoutCount == 1)
        // No checkin needed since checkout failed
        #expect(provider.checkinCount == 0)
    }
}
