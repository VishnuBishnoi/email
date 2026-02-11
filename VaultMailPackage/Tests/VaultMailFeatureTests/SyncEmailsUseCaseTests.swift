import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for SyncEmailsUseCase — the email sync orchestration layer.
///
/// Uses MockAccountRepository, MockEmailRepository, MockKeychainManager,
/// and a MockConnectionProvider that returns MockIMAPClient.
@Suite("SyncEmailsUseCase Tests")
@MainActor
struct SyncEmailsUseCaseTests {

    // MARK: - Mock Connection Provider

    /// Simple mock that always returns the same MockIMAPClient.
    private final class MockConnectionProvider: ConnectionProviding, @unchecked Sendable {
        let client: MockIMAPClient
        var checkoutCount = 0
        var checkinCount = 0

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
            return client
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {
            checkinCount += 1
        }
    }

    // MARK: - Helpers

    private let accountRepo = MockAccountRepository()
    private let emailRepo = MockEmailRepository()
    private let keychainManager = MockKeychainManager()
    private let mockIMAPClient = MockIMAPClient()

    private var connectionProvider: MockConnectionProvider {
        MockConnectionProvider(client: mockIMAPClient)
    }

    private var sut: SyncEmailsUseCase {
        SyncEmailsUseCase(
            accountRepository: accountRepo,
            emailRepository: emailRepo,
            keychainManager: keychainManager,
            connectionPool: connectionProvider
        )
    }

    private func createAccount(
        id: String = "acc-1",
        email: String = "test@gmail.com",
        isActive: Bool = true
    ) -> Account {
        let account = Account(
            email: email,
            displayName: "Test",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587
        )
        // Override auto-generated ID for test determinism
        // Account uses UUID, but we can use it as-is since we reference account.id
        account.isActive = isActive
        return account
    }

    private func addAccountToRepo(_ account: Account) async throws {
        try await accountRepo.addAccount(account)
    }

    private func createInboxFolder(accountId: String) -> Folder {
        let folder = Folder(
            name: "Inbox",
            imapPath: "INBOX",
            totalCount: 0,
            folderType: FolderType.inbox.rawValue,
            uidValidity: 1
        )
        return folder
    }

    // MARK: - Account Validation

    @Test("syncAccount throws accountNotFound for missing account")
    func syncAccountNotFound() async {
        let useCase = sut
        await #expect(throws: SyncError.self) {
            _ = try await useCase.syncAccount(accountId: "nonexistent")
        }
    }

    @Test("syncAccount throws accountInactive for deactivated account")
    func syncAccountInactive() async throws {
        let account = createAccount()
        account.isActive = false
        try await addAccountToRepo(account)

        let useCase = sut
        await #expect(throws: SyncError.self) {
            _ = try await useCase.syncAccount(accountId: account.id)
        }
    }

    // MARK: - Folder Sync

    @Test("syncAccount creates folders from IMAP folder list")
    func syncAccountCreatesFolders() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        // Configure mock IMAP to return Gmail folders
        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 100,
                messageCount: 42
            ),
            IMAPFolderInfo(
                name: "Sent Mail",
                imapPath: "[Gmail]/Sent Mail",
                attributes: ["\\Sent"],
                uidValidity: 200,
                messageCount: 10
            )
        ])
        // Empty search results (no emails to sync)
        mockIMAPClient.selectFolderResult = .success((uidValidity: 100, messageCount: 0))
        mockIMAPClient.searchUIDsResult = .success([])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Verify folders were saved
        #expect(emailRepo.saveFolderCallCount >= 2)
    }

    @Test("syncAccount skips non-syncable folders like All Mail")
    func syncAccountSkipsAllMail() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 5
            ),
            IMAPFolderInfo(
                name: "All Mail",
                imapPath: "[Gmail]/All Mail",
                attributes: ["\\All"],
                uidValidity: 1,
                messageCount: 1000
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 0))
        mockIMAPClient.searchUIDsResult = .success([])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Only Inbox should be saved (All Mail is not syncable)
        // The folder save count tells us how many folders were synced
        let savedFolders = emailRepo.folders
        let allMailFolder = savedFolders.first(where: { $0.imapPath == "[Gmail]/All Mail" })
        #expect(allMailFolder == nil)
    }

    // MARK: - Email Sync

    @Test("syncAccount fetches and persists new emails")
    func syncAccountFetchesEmails() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        let inboxFolder = IMAPFolderInfo(
            name: "Inbox",
            imapPath: "INBOX",
            attributes: ["\\Inbox"],
            uidValidity: 1,
            messageCount: 2
        )
        mockIMAPClient.listFoldersResult = .success([inboxFolder])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 2))
        mockIMAPClient.searchUIDsResult = .success([101, 102])

        let now = Date()
        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 101,
                messageId: "<msg-101@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Alice <alice@example.com>",
                to: ["test@gmail.com"],
                subject: "Hello",
                date: now,
                flags: ["\\Seen"]
            ),
            IMAPEmailHeader(
                uid: 102,
                messageId: "<msg-102@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Bob <bob@example.com>",
                to: ["test@gmail.com"],
                subject: "World",
                date: now,
                flags: []
            )
        ])

        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 101, plainText: "Hello body", htmlText: nil),
            IMAPEmailBody(uid: 102, plainText: "World body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Two emails should have been saved
        #expect(emailRepo.saveEmailCallCount == 2)
        // Two EmailFolder joins should have been created
        #expect(emailRepo.saveEmailFolderCallCount == 2)
        // At least one thread should have been saved
        #expect(emailRepo.saveThreadCallCount >= 1)
    }

    @Test("syncAccount filters out already-synced UIDs")
    func syncAccountFiltersSyncedUIDs() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        // Pre-populate a folder with an existing email at UID 101
        let folder = createInboxFolder(accountId: account.id)
        folder.account = account
        emailRepo.folders.append(folder)

        let existingEmail = Email(
            id: "existing-1",
            accountId: account.id,
            threadId: "thread-1",
            messageId: "<msg-101@gmail.com>",
            fromAddress: "alice@example.com",
            fromName: "Alice",
            toAddresses: "[\"test@gmail.com\"]",
            subject: "Hello",
            dateReceived: Date(),
            isRead: true
        )
        // Create an EmailFolder join for UID 101
        let ef = EmailFolder(imapUID: 101)
        ef.email = existingEmail
        ef.folder = folder
        existingEmail.emailFolders.append(ef)
        emailRepo.emails.append(existingEmail)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 2
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 2))
        // Server reports UIDs 101 and 102, but 101 is already synced
        mockIMAPClient.searchUIDsResult = .success([101, 102])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 102,
                messageId: "<msg-102@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Bob <bob@example.com>",
                to: ["test@gmail.com"],
                subject: "New email",
                date: Date(),
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 102, plainText: "New body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Only the new email (UID 102) should have been saved
        // saveEmailCallCount includes both initial + sync
        let newlySaved = emailRepo.saveEmailCallCount
        #expect(newlySaved == 1)
    }

    // MARK: - Threading

    @Test("threading groups emails by inReplyTo")
    func threadingByInReplyTo() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 2
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 2))
        mockIMAPClient.searchUIDsResult = .success([201, 202])

        let now = Date()
        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 201,
                messageId: "<original@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Alice <alice@example.com>",
                to: ["test@gmail.com"],
                subject: "Thread starter",
                date: now.addingTimeInterval(-3600),
                flags: []
            ),
            IMAPEmailHeader(
                uid: 202,
                messageId: "<reply@gmail.com>",
                inReplyTo: "<original@gmail.com>",
                references: "<original@gmail.com>",
                from: "Bob <bob@example.com>",
                to: ["test@gmail.com"],
                subject: "Re: Thread starter",
                date: now,
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 201, plainText: "Original", htmlText: nil),
            IMAPEmailBody(uid: 202, plainText: "Reply", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Both emails should end up in the same thread
        let savedEmails = emailRepo.emails
        let threadIds = Set(savedEmails.map(\.threadId))
        #expect(threadIds.count == 1, "Both emails should share the same threadId")
    }

    @Test("threading creates separate threads for unrelated emails")
    func threadingSeparateThreads() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 2
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 2))
        mockIMAPClient.searchUIDsResult = .success([301, 302])

        let now = Date()
        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 301,
                messageId: "<standalone1@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Alice <alice@example.com>",
                to: ["test@gmail.com"],
                subject: "Topic A",
                date: now,
                flags: []
            ),
            IMAPEmailHeader(
                uid: 302,
                messageId: "<standalone2@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Bob <bob@example.com>",
                to: ["test@gmail.com"],
                subject: "Topic B",
                date: now,
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 301, plainText: "Body A", htmlText: nil),
            IMAPEmailBody(uid: 302, plainText: "Body B", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        let savedEmails = emailRepo.emails
        let threadIds = Set(savedEmails.map(\.threadId))
        #expect(threadIds.count == 2, "Unrelated emails should have different threadIds")
    }

    // MARK: - Account Metadata

    @Test("syncAccount updates account.lastSyncDate")
    func syncAccountUpdatesLastSyncDate() async throws {
        let account = createAccount()
        #expect(account.lastSyncDate == nil)
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        #expect(accountRepo.updateCallCount >= 1)
    }

    // MARK: - IMAP Flags

    @Test("syncAccount maps IMAP flags to email properties")
    func syncAccountMapsFlags() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 1
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([401])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 401,
                messageId: "<flagged@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "sender@example.com",
                to: ["test@gmail.com"],
                subject: "Flagged email",
                date: Date(),
                flags: ["\\Seen", "\\Flagged", "\\Draft"]
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 401, plainText: "Body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        let savedEmail = emailRepo.emails.first
        #expect(savedEmail?.isRead == true, "\\Seen flag → isRead=true")
        #expect(savedEmail?.isStarred == true, "\\Flagged flag → isStarred=true")
        #expect(savedEmail?.isDraft == true, "\\Draft flag → isDraft=true")
    }

    // MARK: - syncFolder

    @Test("syncFolder throws folderNotFound for missing folder")
    func syncFolderNotFound() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        let useCase = sut
        await #expect(throws: SyncError.self) {
            _ = try await useCase.syncFolder(accountId: account.id, folderId: "nonexistent")
        }
    }

    // MARK: - Contact Cache Population

    @Test("syncAccount populates contact cache from email headers")
    func syncAccountPopulatesContacts() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 1
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([601])

        let now = Date()
        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 601,
                messageId: "<contact-test@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Alice Smith <alice@example.com>",
                to: ["test@gmail.com", "bob@example.com"],
                subject: "Contact test",
                date: now,
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 601, plainText: "Body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Should have upserted contacts for: alice@example.com, test@gmail.com, bob@example.com
        #expect(emailRepo.upsertContactCallCount >= 3)

        // Verify contact entries were stored
        let emails = emailRepo.contactEntries.map(\.emailAddress).sorted()
        #expect(emails.contains("alice@example.com"))
        #expect(emails.contains("bob@example.com"))
        #expect(emails.contains("test@gmail.com"))

        // Verify display name was extracted from From header
        let alice = emailRepo.contactEntries.first(where: { $0.emailAddress == "alice@example.com" })
        #expect(alice?.displayName == "Alice Smith")
    }

    @Test("syncAccount deduplicates contacts within a single email")
    func syncAccountDeduplicatesContacts() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 1
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([701])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 701,
                messageId: "<dedup-test@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "Alice <alice@example.com>",
                to: ["alice@example.com"], // Same as From — should not duplicate
                subject: "Self-send",
                date: Date(),
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 701, plainText: "Body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncAccount(accountId: account.id)

        // Only 1 upsert because alice@example.com appears in both From and To
        #expect(emailRepo.upsertContactCallCount == 1)
    }

    // MARK: - syncFolder

    @Test("syncFolder syncs emails for a single folder")
    func syncFolderSyncsEmails() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        // Pre-populate the folder in the repo
        let folder = createInboxFolder(accountId: account.id)
        folder.account = account
        emailRepo.folders.append(folder)

        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([501])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 501,
                messageId: "<folder-sync@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "sender@example.com",
                to: ["test@gmail.com"],
                subject: "Folder sync test",
                date: Date(),
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 501, plainText: "Body", htmlText: nil)
        ])

        let useCase = sut
        try await useCase.syncFolder(accountId: account.id, folderId: folder.id)

        #expect(emailRepo.saveEmailCallCount == 1)
        #expect(emailRepo.saveEmailFolderCallCount == 1)
    }

    // MARK: - syncAccountInboxFirst

    @Test("syncAccountInboxFirst syncs inbox then remaining folders")
    func syncAccountInboxFirstSyncsAll() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 1
            ),
            IMAPFolderInfo(
                name: "Sent Mail",
                imapPath: "[Gmail]/Sent Mail",
                attributes: ["\\Sent"],
                uidValidity: 2,
                messageCount: 1
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([801])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 801,
                messageId: "<inbox-first@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "sender@example.com",
                to: ["test@gmail.com"],
                subject: "Inbox first test",
                date: Date(),
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 801, plainText: "Body", htmlText: nil)
        ])

        var callbackInvoked = false
        var callbackEmailCount = 0

        let useCase = sut
        let allEmails = try await useCase.syncAccountInboxFirst(accountId: account.id) { inboxEmails in
            callbackInvoked = true
            callbackEmailCount = inboxEmails.count
        }

        #expect(callbackInvoked, "onInboxSynced callback should be invoked")
        #expect(callbackEmailCount >= 1, "Callback should receive inbox emails")
        #expect(!allEmails.isEmpty, "Should return synced emails")
    }

    @Test("syncAccountInboxFirst callback receives inbox emails")
    func syncAccountInboxFirstCallbackEmails() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Inbox",
                imapPath: "INBOX",
                attributes: ["\\Inbox"],
                uidValidity: 1,
                messageCount: 1
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 1))
        mockIMAPClient.searchUIDsResult = .success([901])

        mockIMAPClient.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 901,
                messageId: "<callback-test@gmail.com>",
                inReplyTo: nil,
                references: nil,
                from: "alice@example.com",
                to: ["test@gmail.com"],
                subject: "Callback test",
                date: Date(),
                flags: []
            )
        ])
        mockIMAPClient.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 901, plainText: "Body", htmlText: nil)
        ])

        var receivedEmails: [Email] = []

        let useCase = sut
        _ = try await useCase.syncAccountInboxFirst(accountId: account.id) { inboxEmails in
            receivedEmails = inboxEmails
        }

        #expect(receivedEmails.count == 1)
        #expect(receivedEmails.first?.subject == "Callback test")
    }

    @Test("syncAccountInboxFirst with no inbox still syncs remaining folders")
    func syncAccountInboxFirstNoInbox() async throws {
        let account = createAccount()
        try await addAccountToRepo(account)

        // Only Sent, no Inbox
        mockIMAPClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Sent Mail",
                imapPath: "[Gmail]/Sent Mail",
                attributes: ["\\Sent"],
                uidValidity: 1,
                messageCount: 0
            )
        ])
        mockIMAPClient.selectFolderResult = .success((uidValidity: 1, messageCount: 0))
        mockIMAPClient.searchUIDsResult = .success([])

        var callbackInvoked = false

        let useCase = sut
        _ = try await useCase.syncAccountInboxFirst(accountId: account.id) { _ in
            callbackInvoked = true
        }

        #expect(!callbackInvoked, "Callback should NOT be invoked when there is no inbox folder")
    }

    @Test("syncAccountInboxFirst updates lastSyncDate")
    func syncAccountInboxFirstUpdatesLastSyncDate() async throws {
        let account = createAccount()
        #expect(account.lastSyncDate == nil)
        try await addAccountToRepo(account)

        mockIMAPClient.listFoldersResult = .success([])

        let useCase = sut
        _ = try await useCase.syncAccountInboxFirst(accountId: account.id) { _ in }

        #expect(accountRepo.updateCallCount >= 1)
    }

    @Test("syncAccountInboxFirst throws for missing account")
    func syncAccountInboxFirstAccountNotFound() async {
        let useCase = sut
        await #expect(throws: SyncError.self) {
            _ = try await useCase.syncAccountInboxFirst(accountId: "nonexistent") { _ in }
        }
    }
}
