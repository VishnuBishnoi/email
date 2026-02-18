import Foundation
import Testing
@testable import VaultMailFeature

@Suite("DownloadAttachmentUseCase")
@MainActor
struct DownloadAttachmentUseCaseTests {

    private static func makeSUT() -> (DownloadAttachmentUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = DownloadAttachmentUseCase(repository: repo)
        return (useCase, repo)
    }

    // MARK: - Mock Connection Provider

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
            security: ConnectionSecurity,
            credential: IMAPCredential
        ) async throws -> any IMAPClientProtocol {
            checkoutCount += 1
            return client
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {
            checkinCount += 1
        }
    }

    private static func makeIMAPSUT() -> (
        DownloadAttachmentUseCase,
        MockEmailRepository,
        MockAccountRepository,
        MockKeychainManager,
        MockIMAPClient,
        MockConnectionProvider
    ) {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let imapClient = MockIMAPClient()
        let connectionProvider = MockConnectionProvider(client: imapClient)

        let useCase = DownloadAttachmentUseCase(
            repository: repo,
            connectionProvider: connectionProvider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        return (useCase, repo, accountRepo, keychainManager, imapClient, connectionProvider)
    }

    // MARK: - securityWarning

    @Test("securityWarning returns warning for .exe files")
    func securityWarningExe() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "malware.exe")
        #expect(warning == "This file is a Windows executable.")
    }

    @Test("securityWarning returns warning for .zip files")
    func securityWarningZip() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "archive.zip")
        #expect(warning == "This archive may contain executable files.")
    }

    @Test("securityWarning returns warning for .sh files")
    func securityWarningSh() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "install.sh")
        #expect(warning == "This file can run code on your Mac.")
    }

    @Test("securityWarning returns nil for safe file types")
    func securityWarningNilForSafe() {
        let (sut, _) = Self.makeSUT()
        #expect(sut.securityWarning(for: "document.pdf") == nil)
        #expect(sut.securityWarning(for: "photo.jpg") == nil)
        #expect(sut.securityWarning(for: "readme.txt") == nil)
    }

    @Test("securityWarning handles .tar.gz compound extension")
    func securityWarningTarGz() {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: "backup.tar.gz")
        #expect(warning == "This archive may contain executable files.")
    }

    @Test("securityWarning for all dangerous extensions", arguments: [
        ("virus.bat", "This file is a Windows executable."),
        ("script.cmd", "This file is a Windows executable."),
        ("tool.com", "This file is a Windows executable."),
        ("setup.msi", "This file is a Windows executable."),
        ("MyApp.app", "This file can run code on your Mac."),
        ("run.command", "This file can run code on your Mac."),
        ("install.pkg", "This file can run code on your Mac."),
        ("disk.dmg", "This file can run code on your Mac."),
        ("code.js", "This file is a script that can run code."),
        ("macro.vbs", "This file is a script that can run code."),
        ("auto.wsf", "This file is a script that can run code."),
        ("screen.scr", "This file is a script that can run code."),
        ("data.rar", "This archive may contain executable files."),
        ("data.7z", "This archive may contain executable files."),
        ("app.apk", "This file is an Android application package.")
    ])
    func securityWarningAllDangerous(filename: String, expectedWarning: String) {
        let (sut, _) = Self.makeSUT()
        let warning = sut.securityWarning(for: filename)
        #expect(warning == expectedWarning)
    }

    @Test("securityWarning is case-insensitive")
    func securityWarningCaseInsensitive() {
        let (sut, _) = Self.makeSUT()
        #expect(sut.securityWarning(for: "MALWARE.EXE") == "This file is a Windows executable.")
        #expect(sut.securityWarning(for: "Archive.ZIP") == "This archive may contain executable files.")
    }

    // MARK: - requiresCellularWarning

    @Test("requiresCellularWarning returns true for >= 25MB")
    func cellularWarningTrue() {
        let (sut, _) = Self.makeSUT()
        let threshold = 25 * 1024 * 1024
        #expect(sut.requiresCellularWarning(sizeBytes: threshold) == true)
        #expect(sut.requiresCellularWarning(sizeBytes: threshold + 1) == true)
    }

    @Test("requiresCellularWarning returns false for < 25MB")
    func cellularWarningFalse() {
        let (sut, _) = Self.makeSUT()
        let threshold = 25 * 1024 * 1024
        #expect(sut.requiresCellularWarning(sizeBytes: threshold - 1) == false)
        #expect(sut.requiresCellularWarning(sizeBytes: 0) == false)
        #expect(sut.requiresCellularWarning(sizeBytes: 1024) == false)
    }

    // MARK: - Fallback Download (no IMAP)

    @Test("download without IMAP dependencies uses fallback path")
    func downloadFallback() async throws {
        let (sut, repo) = Self.makeSUT()
        let attachment = Attachment(filename: "test.pdf", mimeType: "application/pdf", sizeBytes: 1024)

        let path = try await sut.download(attachment: attachment)

        #expect(attachment.isDownloaded == true)
        #expect(attachment.localPath == path)
        #expect(repo.saveAttachmentCallCount == 1)
        #expect(path.contains("test.pdf"))
    }

    // MARK: - IMAP Download (base64)

    @Test("download via IMAP fetches body part and decodes base64")
    func downloadIMAPBase64() async throws {
        let (sut, repo, accountRepo, keychainManager, imapClient, connectionProvider) = Self.makeIMAPSUT()

        // Set up account and token
        let account = Account(
            id: "acc-1",
            email: "test@gmail.com",
            displayName: "Test"
        )
        accountRepo.accounts.append(account)
        let token = OAuthToken(
            accessToken: "mock-token",
            refreshToken: "mock-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await keychainManager.store(token, for: account.id)

        // Set up email with folder
        let email = Email(
            accountId: account.id,
            threadId: "thread-1",
            messageId: "<msg1@test.com>",
            fromAddress: "sender@test.com",
            subject: "Test"
        )
        let folder = Folder(name: "Inbox", imapPath: "INBOX")
        let emailFolder = EmailFolder(imapUID: 42)
        emailFolder.email = email
        emailFolder.folder = folder
        email.emailFolders = [emailFolder]

        // Set up attachment with body section
        let attachment = Attachment(
            filename: "report.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            bodySection: "1.2",
            transferEncoding: "base64"
        )
        attachment.email = email

        // Configure IMAP mock to return base64-encoded data
        let originalData = "Hello, World!".data(using: .utf8)!
        let base64String = originalData.base64EncodedString()
        imapClient.fetchBodyPartResult = .success(base64String.data(using: .utf8)!)

        let path = try await sut.download(attachment: attachment)

        // Verify IMAP interactions
        #expect(imapClient.selectFolderCallCount == 1)
        #expect(imapClient.lastSelectedPath == "INBOX")
        #expect(imapClient.fetchBodyPartCallCount == 1)
        #expect(imapClient.lastFetchBodyPartUID == 42)
        #expect(imapClient.lastFetchBodyPartSection == "1.2")

        // Verify attachment state
        #expect(attachment.isDownloaded == true)
        #expect(attachment.localPath == path)
        #expect(repo.saveAttachmentCallCount == 1)

        // Verify connection was returned
        #expect(connectionProvider.checkoutCount == 1)
        // checkin happens in defer Task, may not complete immediately

        // Clean up downloaded file
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - IMAP Download (7bit)

    @Test("download via IMAP handles 7bit encoding (raw passthrough)")
    func downloadIMAP7Bit() async throws {
        let (sut, _, accountRepo, keychainManager, imapClient, _) = Self.makeIMAPSUT()

        let account = Account(id: "acc-1", email: "test@gmail.com", displayName: "Test")
        accountRepo.accounts.append(account)
        let token = OAuthToken(accessToken: "tok", refreshToken: "ref", expiresAt: Date().addingTimeInterval(3600))
        try await keychainManager.store(token, for: account.id)

        let email = Email(accountId: account.id, threadId: "t-1", messageId: "<m1>", fromAddress: "a@b.com", subject: "S")
        let folder = Folder(name: "Inbox", imapPath: "INBOX")
        let emailFolder = EmailFolder(imapUID: 10)
        emailFolder.email = email
        emailFolder.folder = folder
        email.emailFolders = [emailFolder]

        let attachment = Attachment(
            filename: "plain.txt",
            mimeType: "text/plain",
            sizeBytes: 50,
            bodySection: "1",
            transferEncoding: "7BIT"
        )
        attachment.email = email

        let rawData = "Plain text content".data(using: .utf8)!
        imapClient.fetchBodyPartResult = .success(rawData)

        let path = try await sut.download(attachment: attachment)

        // 7BIT should pass data through unchanged
        let downloadedData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(downloadedData == rawData)

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - IMAP Download Errors

    @Test("download throws when account not found")
    func downloadAccountNotFound() async throws {
        let (sut, _, _, _, _, _) = Self.makeIMAPSUT()
        // No accounts in repo

        let email = Email(accountId: "missing", threadId: "t-1", messageId: "<m1>", fromAddress: "a@b.com", subject: "S")
        let folder = Folder(name: "Inbox", imapPath: "INBOX")
        let emailFolder = EmailFolder(imapUID: 10)
        emailFolder.email = email
        emailFolder.folder = folder
        email.emailFolders = [emailFolder]

        let attachment = Attachment(
            filename: "test.pdf",
            mimeType: "application/pdf",
            bodySection: "1.1"
        )
        attachment.email = email

        await #expect(throws: EmailDetailError.self) {
            try await sut.download(attachment: attachment)
        }
    }

    @Test("download throws when IMAP fetch fails")
    func downloadIMAPFetchFails() async throws {
        let (sut, _, accountRepo, keychainManager, imapClient, _) = Self.makeIMAPSUT()

        let account = Account(id: "acc-1", email: "test@gmail.com", displayName: "Test")
        accountRepo.accounts.append(account)
        let token = OAuthToken(accessToken: "tok", refreshToken: "ref", expiresAt: Date().addingTimeInterval(3600))
        try await keychainManager.store(token, for: account.id)

        let email = Email(accountId: account.id, threadId: "t-1", messageId: "<m1>", fromAddress: "a@b.com", subject: "S")
        let folder = Folder(name: "Inbox", imapPath: "INBOX")
        let emailFolder = EmailFolder(imapUID: 10)
        emailFolder.email = email
        emailFolder.folder = folder
        email.emailFolders = [emailFolder]

        let attachment = Attachment(
            filename: "test.pdf",
            mimeType: "application/pdf",
            bodySection: "1.1",
            transferEncoding: "base64"
        )
        attachment.email = email

        imapClient.fetchBodyPartResult = .failure(.connectionFailed("Network error"))

        await #expect(throws: EmailDetailError.self) {
            try await sut.download(attachment: attachment)
        }
    }

    // MARK: - IMAP Download (QUOTED-PRINTABLE)

    @Test("download via IMAP decodes QUOTED-PRINTABLE encoding")
    func downloadIMAPQuotedPrintable() async throws {
        let (sut, _, accountRepo, keychainManager, imapClient, _) = Self.makeIMAPSUT()

        let account = Account(id: "acc-1", email: "test@gmail.com", displayName: "Test")
        accountRepo.accounts.append(account)
        let token = OAuthToken(accessToken: "tok", refreshToken: "ref", expiresAt: Date().addingTimeInterval(3600))
        try await keychainManager.store(token, for: account.id)

        let email = Email(accountId: account.id, threadId: "t-1", messageId: "<m1>", fromAddress: "a@b.com", subject: "S")
        let folder = Folder(name: "Inbox", imapPath: "INBOX")
        let emailFolder = EmailFolder(imapUID: 20)
        emailFolder.email = email
        emailFolder.folder = folder
        email.emailFolders = [emailFolder]

        let attachment = Attachment(
            filename: "message.txt",
            mimeType: "text/plain",
            sizeBytes: 50,
            bodySection: "1",
            transferEncoding: "QUOTED-PRINTABLE"
        )
        attachment.email = email

        // QP-encoded data: "=48=65=6C=6C=6F" decodes to "Hello"
        let qpEncoded = "=48=65=6C=6C=6F"
        imapClient.fetchBodyPartResult = .success(qpEncoded.data(using: .utf8)!)

        let path = try await sut.download(attachment: attachment)

        let downloadedData = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = String(data: downloadedData, encoding: .utf8)
        #expect(decoded == "Hello")
        #expect(attachment.isDownloaded == true)

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }
}
