import Foundation
import Testing
@testable import VaultMailFeature

@Suite("ComposeEmailUseCase")
@MainActor
struct ComposeEmailUseCaseTests {

    // MARK: - Helpers

    private static func makeSUT() -> (ComposeEmailUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient
        )
        return (useCase, repo)
    }

    private static func makeSendSUT() -> (
        ComposeEmailUseCase, MockEmailRepository,
        MockAccountRepository, MockKeychainManager, MockSMTPClient
    ) {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient
        )
        return (useCase, repo, accountRepo, keychainManager, smtpClient)
    }

    /// Creates a standard account + token + queued email for executeSend tests.
    private static func setupSendScenario(
        repo: MockEmailRepository,
        accountRepo: MockAccountRepository,
        keychainManager: MockKeychainManager,
        accountId: String = "acc1",
        emailId: String? = nil,
        toAddresses: String = "[\"to@test.com\"]",
        sendRetryCount: Int = 0
    ) async -> Email {
        let account = Account(id: accountId, email: "me@test.com", displayName: "Me")
        accountRepo.accounts.append(account)

        let token = OAuthToken(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try! await keychainManager.store(token, for: accountId)

        // Create Drafts and Sent folders
        let draftsFolder = Folder(name: "Drafts", imapPath: "[Gmail]/Drafts", totalCount: 0, folderType: FolderType.drafts.rawValue, uidValidity: 1)
        draftsFolder.account = account
        let sentFolder = Folder(name: "Sent", imapPath: "[Gmail]/Sent Mail", totalCount: 0, folderType: FolderType.sent.rawValue, uidValidity: 1)
        sentFolder.account = account
        repo.folders = [draftsFolder, sentFolder]

        let email = Email(
            accountId: accountId,
            threadId: "thread-1",
            messageId: "<send-test@local>",
            fromAddress: "",
            toAddresses: toAddresses,
            subject: "Send Test",
            bodyPlain: "Hello",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        email.sendRetryCount = sendRetryCount

        // Place in drafts
        let ef = EmailFolder(imapUID: 0)
        ef.email = email
        ef.folder = draftsFolder
        email.emailFolders.append(ef)

        repo.emails.append(email)
        return email
    }

    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeEmailContext(
        emailId: String = "email-1",
        accountId: String = "acc1",
        threadId: String = "thread-1",
        messageId: String = "<msg-1@example.com>",
        inReplyTo: String? = nil,
        references: String? = nil,
        fromAddress: String = "sender@example.com",
        fromName: String? = "Sender Name",
        toAddresses: String = "[\"me@example.com\"]",
        ccAddresses: String? = nil,
        bccAddresses: String? = nil,
        subject: String = "Test Subject",
        bodyPlain: String? = "Hello, this is the body.",
        dateSent: Date? = baseDate,
        isDraft: Bool = false,
        attachmentIds: [String] = []
    ) -> ComposerEmailContext {
        ComposerEmailContext(
            emailId: emailId,
            accountId: accountId,
            threadId: threadId,
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references,
            fromAddress: fromAddress,
            fromName: fromName,
            toAddresses: toAddresses,
            ccAddresses: ccAddresses,
            bccAddresses: bccAddresses,
            subject: subject,
            bodyPlain: bodyPlain,
            dateSent: dateSent,
            isDraft: isDraft,
            attachmentIds: attachmentIds
        )
    }

    // MARK: - buildPrefill: New

    @Test("buildPrefill new mode returns empty prefill")
    func buildPrefillNewMode() {
        let (useCase, _) = Self.makeSUT()
        let prefill = useCase.buildPrefill(mode: .new(accountId: "acc1"), userEmail: "me@example.com")

        #expect(prefill.toAddresses.isEmpty)
        #expect(prefill.ccAddresses.isEmpty)
        #expect(prefill.bccAddresses.isEmpty)
        #expect(prefill.subject == "")
        #expect(prefill.bodyPrefix == "")
        #expect(prefill.inReplyTo == nil)
        #expect(prefill.references == nil)
    }

    // MARK: - buildPrefill: Reply

    @Test("buildPrefill reply sets To to original sender")
    func buildPrefillReply() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext()
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.toAddresses == ["sender@example.com"])
        #expect(prefill.ccAddresses.isEmpty)
    }

    @Test("buildPrefill reply adds Re: prefix to subject")
    func buildPrefillReplySubject() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(subject: "Hello")
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.subject == "Re: Hello")
    }

    @Test("buildPrefill reply deduplicates Re: prefix")
    func buildPrefillReplySubjectDedup() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(subject: "Re: Hello")
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.subject == "Re: Hello")
    }

    @Test("buildPrefill reply sets inReplyTo to original messageId")
    func buildPrefillReplyInReplyTo() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(messageId: "<msg-abc@test.com>")
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.inReplyTo == "<msg-abc@test.com>")
    }

    @Test("buildPrefill reply builds references chain")
    func buildPrefillReplyReferences() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(
            messageId: "<msg-2@test.com>",
            references: "<msg-1@test.com>"
        )
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.references == "<msg-1@test.com> <msg-2@test.com>")
    }

    @Test("buildPrefill reply includes quoted body with header")
    func buildPrefillReplyQuotedBody() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(bodyPlain: "Original text")
        let prefill = useCase.buildPrefill(mode: .reply(email: ctx), userEmail: "me@example.com")

        #expect(prefill.bodyPrefix.contains("Sender Name wrote:"))
        #expect(prefill.bodyPrefix.contains("> Original text"))
    }

    // MARK: - buildPrefill: Reply All

    @Test("buildPrefill replyAll includes all recipients minus self")
    func buildPrefillReplyAll() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(
            fromAddress: "sender@example.com",
            toAddresses: "[\"me@example.com\",\"other@example.com\"]",
            ccAddresses: "[\"cc@example.com\"]"
        )
        let prefill = useCase.buildPrefill(mode: .replyAll(email: ctx), userEmail: "me@example.com")

        // To should include sender and other, NOT me
        #expect(prefill.toAddresses.contains("sender@example.com"))
        #expect(prefill.toAddresses.contains("other@example.com"))
        #expect(!prefill.toAddresses.contains("me@example.com"))

        // CC should include cc@example.com, NOT me
        #expect(prefill.ccAddresses.contains("cc@example.com"))
    }

    @Test("buildPrefill replyAll falls back to sender if self is only To recipient")
    func buildPrefillReplyAllSelfOnly() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(
            fromAddress: "sender@example.com",
            toAddresses: "[\"me@example.com\"]"
        )
        let prefill = useCase.buildPrefill(mode: .replyAll(email: ctx), userEmail: "me@example.com")

        // Should have at least the original sender
        #expect(prefill.toAddresses.contains("sender@example.com"))
    }

    @Test("buildPrefill replyAll does not remove addresses that are substrings of self")
    func buildPrefillReplyAllSubstringEdge() {
        let (useCase, _) = Self.makeSUT()
        // "team@example.com" is a substring of "ann+team@example.com" but should NOT be removed
        let ctx = Self.makeEmailContext(
            fromAddress: "sender@example.com",
            toAddresses: "[\"ann+team@example.com\"]",
            ccAddresses: "[\"team@example.com\",\"other@example.com\"]"
        )
        let prefill = useCase.buildPrefill(mode: .replyAll(email: ctx), userEmail: "team@example.com")

        // ann+team@example.com must NOT be filtered out (it's a different address)
        #expect(prefill.toAddresses.contains("ann+team@example.com"))
        // team@example.com (self) should be filtered out from CC
        #expect(!prefill.ccAddresses.contains("team@example.com"))
        // other@example.com should remain in CC
        #expect(prefill.ccAddresses.contains("other@example.com"))
    }

    // MARK: - buildPrefill: Forward

    @Test("buildPrefill forward adds Fwd: prefix")
    func buildPrefillForward() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(subject: "Hello")
        let prefill = useCase.buildPrefill(mode: .forward(email: ctx), userEmail: "me@example.com")

        #expect(prefill.subject == "Fwd: Hello")
        #expect(prefill.toAddresses.isEmpty) // No recipients pre-filled for forward
    }

    @Test("buildPrefill forward deduplicates Fwd: prefix")
    func buildPrefillForwardDedup() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(subject: "Fwd: Hello")
        let prefill = useCase.buildPrefill(mode: .forward(email: ctx), userEmail: "me@example.com")

        #expect(prefill.subject == "Fwd: Hello")
    }

    @Test("buildPrefill forward includes forwarded message header")
    func buildPrefillForwardBody() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(bodyPlain: "Original forwarded text")
        let prefill = useCase.buildPrefill(mode: .forward(email: ctx), userEmail: "me@example.com")

        #expect(prefill.bodyPrefix.contains("Forwarded message"))
        #expect(prefill.bodyPrefix.contains("From: sender@example.com"))
        #expect(prefill.bodyPrefix.contains("Original forwarded text"))
    }

    @Test("buildPrefill forward carries attachment IDs")
    func buildPrefillForwardAttachments() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(attachmentIds: ["att-1", "att-2"])
        let prefill = useCase.buildPrefill(mode: .forward(email: ctx), userEmail: "me@example.com")

        #expect(prefill.forwardedAttachmentIds == ["att-1", "att-2"])
    }

    // MARK: - buildPrefill: Edit Draft

    @Test("buildPrefill editDraft restores all fields")
    func buildPrefillEditDraft() {
        let (useCase, _) = Self.makeSUT()
        let ctx = Self.makeEmailContext(
            toAddresses: "[\"recipient@example.com\"]",
            ccAddresses: "[\"cc@example.com\"]",
            bccAddresses: "[\"bcc@example.com\"]",
            subject: "Draft Subject",
            bodyPlain: "Draft body",
            isDraft: true
        )
        let prefill = useCase.buildPrefill(mode: .editDraft(email: ctx), userEmail: "me@example.com")

        #expect(prefill.toAddresses == ["recipient@example.com"])
        #expect(prefill.ccAddresses == ["cc@example.com"])
        #expect(prefill.bccAddresses == ["bcc@example.com"])
        #expect(prefill.subject == "Draft Subject")
        #expect(prefill.bodyPrefix == "Draft body")
    }

    // MARK: - saveDraft

    @Test("saveDraft creates new email as draft")
    func saveDraftCreatesNew() async throws {
        let (useCase, repo) = Self.makeSUT()

        let draftId = try await useCase.saveDraft(
            draftId: nil,
            accountId: "acc1",
            threadId: nil,
            toAddresses: ["to@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Test Subject",
            bodyPlain: "Test Body",
            inReplyTo: nil,
            references: nil,
            attachments: []
        )

        #expect(!draftId.isEmpty)
        #expect(repo.saveEmailCallCount >= 1)
        #expect(repo.saveThreadCallCount == 1) // New thread created

        // Verify the saved email is a draft
        let email = repo.emails.first { $0.id == draftId }
        #expect(email?.isDraft == true)
        #expect(email?.sendState == SendState.none.rawValue)
        #expect(email?.subject == "Test Subject")
        #expect(email?.bodyPlain == "Test Body")
    }

    @Test("saveDraft updates existing draft")
    func saveDraftUpdatesExisting() async throws {
        let (useCase, repo) = Self.makeSUT()

        // Create a draft first
        let existingEmail = Email(
            accountId: "acc1",
            threadId: "thread-1",
            messageId: "<draft@local>",
            fromAddress: "",
            toAddresses: "[]",
            subject: "Old Subject",
            bodyPlain: "Old Body",
            dateSent: Date(),
            isRead: true,
            isDraft: true,
            sendState: SendState.none.rawValue
        )
        repo.emails.append(existingEmail)

        let draftId = try await useCase.saveDraft(
            draftId: existingEmail.id,
            accountId: "acc1",
            threadId: "thread-1",
            toAddresses: ["new@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Updated Subject",
            bodyPlain: "Updated Body",
            inReplyTo: nil,
            references: nil,
            attachments: []
        )

        #expect(draftId == existingEmail.id)

        // Verify the email was updated
        let updated = repo.emails.first { $0.id == draftId }
        #expect(updated?.subject == "Updated Subject")
        #expect(updated?.bodyPlain == "Updated Body")
    }

    @Test("saveDraft wraps errors as ComposerError.saveDraftFailed")
    func saveDraftError() async {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        await #expect(throws: ComposerError.self) {
            try await useCase.saveDraft(
                draftId: nil,
                accountId: "acc1",
                threadId: nil,
                toAddresses: [],
                ccAddresses: [],
                bccAddresses: [],
                subject: "",
                bodyPlain: "",
                inReplyTo: nil,
                references: nil,
                attachments: []
            )
        }
    }

    // MARK: - queueForSending

    @Test("queueForSending transitions email to queued state")
    func queueForSending() async throws {
        let (useCase, repo) = Self.makeSUT()
        let email = Email(
            accountId: "acc1",
            threadId: "thread-1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: true,
            sendState: SendState.none.rawValue
        )
        repo.emails.append(email)

        try await useCase.queueForSending(emailId: email.id)

        let updated = repo.emails.first { $0.id == email.id }
        #expect(updated?.isDraft == false)
        #expect(updated?.sendState == SendState.queued.rawValue)
        #expect(updated?.sendQueuedDate != nil)
    }

    @Test("queueForSending throws when email not found")
    func queueForSendingNotFound() async {
        let (useCase, _) = Self.makeSUT()

        await #expect(throws: ComposerError.self) {
            try await useCase.queueForSending(emailId: "nonexistent")
        }
    }

    // MARK: - undoSend

    @Test("undoSend reverts email to draft state")
    func undoSend() async throws {
        let (useCase, repo) = Self.makeSUT()
        let email = Email(
            accountId: "acc1",
            threadId: "thread-1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        email.sendQueuedDate = Date()
        repo.emails.append(email)

        try await useCase.undoSend(emailId: email.id)

        let updated = repo.emails.first { $0.id == email.id }
        #expect(updated?.isDraft == true)
        #expect(updated?.sendState == SendState.none.rawValue)
        #expect(updated?.sendQueuedDate == nil)
    }

    @Test("undoSend throws when email not found")
    func undoSendNotFound() async {
        let (useCase, _) = Self.makeSUT()

        await #expect(throws: ComposerError.self) {
            try await useCase.undoSend(emailId: "nonexistent")
        }
    }

    // MARK: - deleteDraft

    @Test("deleteDraft removes email from repository")
    func deleteDraft() async throws {
        let (useCase, repo) = Self.makeSUT()
        let email = Email(
            accountId: "acc1",
            threadId: "thread-1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[]",
            subject: "Draft",
            bodyPlain: "",
            dateSent: Date(),
            isRead: true,
            isDraft: true,
            sendState: SendState.none.rawValue
        )
        repo.emails.append(email)

        try await useCase.deleteDraft(emailId: email.id)

        #expect(repo.deleteEmailCallCount == 1)
        #expect(repo.emails.isEmpty)
    }

    @Test("deleteDraft wraps errors as ComposerError.deleteDraftFailed")
    func deleteDraftError() async {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        await #expect(throws: ComposerError.self) {
            try await useCase.deleteDraft(emailId: "any")
        }
    }

    // MARK: - ComposerMode Identifiable

    @Test("ComposerMode IDs are unique per mode and context")
    func composerModeIds() {
        let ctx = Self.makeEmailContext(emailId: "e1")
        let modes: [ComposerMode] = [
            .new(accountId: "acc1"),
            .reply(email: ctx),
            .replyAll(email: ctx),
            .forward(email: ctx),
            .editDraft(email: ctx),
        ]

        let ids = modes.map(\.id)
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == modes.count)
    }

    @Test("ComposerMode accountId returns correct value")
    func composerModeAccountId() {
        let ctx = Self.makeEmailContext(accountId: "acc-test")
        #expect(ComposerMode.new(accountId: "acc-new").accountId == "acc-new")
        #expect(ComposerMode.reply(email: ctx).accountId == "acc-test")
        #expect(ComposerMode.forward(email: ctx).accountId == "acc-test")
    }

    // MARK: - executeSend

    @Test("executeSend happy path transitions to sent and calls SMTP")
    func executeSendHappyPath() async throws {
        let (useCase, repo, accountRepo, keychainManager, smtpClient) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager
        )

        try await useCase.executeSend(emailId: email.id)

        let updated = repo.emails.first { $0.id == email.id }
        #expect(updated?.sendState == SendState.sent.rawValue)
        #expect(updated?.dateSent != nil)

        let connectCount = await smtpClient.connectCallCount
        #expect(connectCount == 1)
        let sendCount = await smtpClient.sendMessageCallCount
        #expect(sendCount == 1)
        let disconnectCount = await smtpClient.disconnectCallCount
        #expect(disconnectCount == 1)
    }

    @Test("executeSend throws when email not found")
    func executeSendEmailNotFound() async {
        let (useCase, _, _, _, _) = Self.makeSendSUT()

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: "nonexistent")
        }
    }

    @Test("executeSend fails when account not found")
    func executeSendAccountNotFound() async {
        let (useCase, repo, _, _, _) = Self.makeSendSUT()
        // Create email but no account
        let email = Email(
            accountId: "missing-acc",
            threadId: "t1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        repo.emails.append(email)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        #expect(email.sendState == SendState.failed.rawValue)
    }

    @Test("executeSend fails when no token in keychain")
    func executeSendNoToken() async {
        let (useCase, repo, accountRepo, _, _) = Self.makeSendSUT()
        let account = Account(id: "acc1", email: "me@test.com", displayName: "Me")
        accountRepo.accounts.append(account)
        // No token stored in keychain

        let email = Email(
            accountId: "acc1",
            threadId: "t1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        repo.emails.append(email)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        #expect(email.sendState == SendState.failed.rawValue)
    }

    @Test("executeSend refreshes expired token before sending")
    func executeSendTokenRefresh() async throws {
        let (useCase, repo, accountRepo, keychainManager, _) = Self.makeSendSUT()
        let account = Account(id: "acc1", email: "me@test.com", displayName: "Me")
        accountRepo.accounts.append(account)

        // Store an expired token
        let expiredToken = OAuthToken(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(-3600) // expired 1 hour ago
        )
        try await keychainManager.store(expiredToken, for: "acc1")

        let draftsFolder = Folder(name: "Drafts", imapPath: "[Gmail]/Drafts", totalCount: 0, folderType: FolderType.drafts.rawValue, uidValidity: 1)
        let sentFolder = Folder(name: "Sent", imapPath: "[Gmail]/Sent Mail", totalCount: 0, folderType: FolderType.sent.rawValue, uidValidity: 1)
        repo.folders = [draftsFolder, sentFolder]

        let email = Email(
            accountId: "acc1",
            threadId: "t1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        repo.emails.append(email)

        try await useCase.executeSend(emailId: email.id)

        #expect(accountRepo.refreshCallCount == 1)
        #expect(email.sendState == SendState.sent.rawValue)
    }

    @Test("executeSend fails when token refresh fails")
    func executeSendTokenRefreshFails() async {
        let (useCase, repo, accountRepo, keychainManager, _) = Self.makeSendSUT()
        let account = Account(id: "acc1", email: "me@test.com", displayName: "Me")
        accountRepo.accounts.append(account)
        accountRepo.shouldThrowOnRefresh = true

        // Store an expired token
        let expiredToken = OAuthToken(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(-3600)
        )
        try! await keychainManager.store(expiredToken, for: "acc1")

        let email = Email(
            accountId: "acc1",
            threadId: "t1",
            messageId: "<msg@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Test",
            bodyPlain: "Body",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        repo.emails.append(email)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        #expect(email.sendState == SendState.failed.rawValue)
    }

    @Test("executeSend fails when no recipients specified")
    func executeSendNoRecipients() async {
        let (useCase, repo, accountRepo, keychainManager, _) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager,
            toAddresses: "[]"
        )

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        #expect(email.sendState == SendState.failed.rawValue)
    }

    @Test("executeSend retries on SMTP connect failure")
    func executeSendSMTPConnectFails() async {
        let (useCase, repo, accountRepo, keychainManager, smtpClient) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager
        )
        await smtpClient.setThrowOnConnect(true)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        // Should re-queue for retry (not yet at max retries)
        #expect(email.sendRetryCount == 1)
        #expect(email.sendState == SendState.queued.rawValue)
    }

    @Test("executeSend retries on SMTP send failure")
    func executeSendSMTPSendFails() async {
        let (useCase, repo, accountRepo, keychainManager, smtpClient) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager
        )
        await smtpClient.setThrowOnSend(true)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        #expect(email.sendRetryCount == 1)
        #expect(email.sendState == SendState.queued.rawValue)
    }

    @Test("executeSend marks failed after max retries exhausted")
    func executeSendMaxRetries() async {
        let (useCase, repo, accountRepo, keychainManager, smtpClient) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager,
            sendRetryCount: AppConstants.maxSendRetryCount - 1
        )
        await smtpClient.setThrowOnConnect(true)

        await #expect(throws: ComposerError.self) {
            try await useCase.executeSend(emailId: email.id)
        }
        // Max retries reached — should be failed, not re-queued
        #expect(email.sendState == SendState.failed.rawValue)
    }

    // MARK: - recoverStuckSendingEmails

    @Test("recoverStuckSendingEmails transitions sending emails to failed")
    func recoverStuckSendingEmails() async {
        let (useCase, repo) = Self.makeSUT()

        let email1 = Email(
            accountId: "acc1", threadId: "t1", messageId: "<stuck1@local>",
            fromAddress: "", toAddresses: "[]", subject: "Stuck 1", bodyPlain: "",
            dateSent: Date(), isRead: true, isDraft: false,
            sendState: SendState.sending.rawValue
        )
        let email2 = Email(
            accountId: "acc1", threadId: "t2", messageId: "<stuck2@local>",
            fromAddress: "", toAddresses: "[]", subject: "Stuck 2", bodyPlain: "",
            dateSent: Date(), isRead: true, isDraft: false,
            sendState: SendState.sending.rawValue
        )
        repo.emails.append(contentsOf: [email1, email2])

        await useCase.recoverStuckSendingEmails()

        #expect(email1.sendState == SendState.failed.rawValue)
        #expect(email2.sendState == SendState.failed.rawValue)
    }

    @Test("recoverStuckSendingEmails does nothing when no stuck emails")
    func recoverStuckNoStuckEmails() async {
        let (useCase, repo) = Self.makeSUT()

        let normalEmail = Email(
            accountId: "acc1", threadId: "t1", messageId: "<normal@local>",
            fromAddress: "", toAddresses: "[]", subject: "Normal", bodyPlain: "",
            dateSent: Date(), isRead: true, isDraft: false,
            sendState: SendState.sent.rawValue
        )
        repo.emails.append(normalEmail)

        await useCase.recoverStuckSendingEmails()

        // No changes to existing emails
        #expect(normalEmail.sendState == SendState.sent.rawValue)
    }

    // MARK: - SMTP Credential Variation Tests (P3-01)

    /// Mock connection provider for testing IMAP APPEND behavior.
    private final class MockConnectionProvider: ConnectionProviding, @unchecked Sendable {
        let client: MockIMAPClient
        var checkoutCount = 0
        var checkinCount = 0
        var lastCredential: IMAPCredential?
        var lastSecurity: ConnectionSecurity?

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
            lastSecurity = security
            lastCredential = credential
            return client
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {
            checkinCount += 1
        }
    }

    /// Helper to create a send scenario for app-password (PLAIN auth) providers.
    private static func setupAppPasswordSendScenario(
        repo: MockEmailRepository,
        accountRepo: MockAccountRepository,
        keychainManager: MockKeychainManager,
        providerConfig: ProviderConfiguration,
        email: String = "user@icloud.com",
        password: String = "app-password-123"
    ) async -> (Account, Email) {
        let account = Account(
            email: email,
            displayName: "Test User",
            providerConfig: providerConfig
        )
        accountRepo.accounts.append(account)

        try! await keychainManager.storeCredential(.password(password), for: account.id)

        // Create Drafts and Sent folders
        let draftsFolder = Folder(name: "Drafts", imapPath: "Drafts", totalCount: 0, folderType: FolderType.drafts.rawValue, uidValidity: 1)
        draftsFolder.account = account
        let sentFolder = Folder(name: "Sent", imapPath: "Sent Messages", totalCount: 0, folderType: FolderType.sent.rawValue, uidValidity: 1)
        sentFolder.account = account
        repo.folders = [draftsFolder, sentFolder]

        let emailObj = Email(
            accountId: account.id,
            threadId: "thread-plain",
            messageId: "<plain-send@local>",
            fromAddress: "",
            toAddresses: "[\"recipient@example.com\"]",
            subject: "PLAIN Auth Test",
            bodyPlain: "Hello via app password",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )

        // Place in drafts
        let ef = EmailFolder(imapUID: 0)
        ef.email = emailObj
        ef.folder = draftsFolder
        emailObj.emailFolders.append(ef)

        repo.emails.append(emailObj)
        return (account, emailObj)
    }

    @Test("executeSend with iCloud account sends via PLAIN SMTP credential")
    func executeSendICloudPlainCredential() async throws {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient
        )

        let config = ProviderRegistry.provider(for: .icloud)!
        let (_, email) = await Self.setupAppPasswordSendScenario(
            repo: repo,
            accountRepo: accountRepo,
            keychainManager: keychainManager,
            providerConfig: config,
            email: "user@icloud.com",
            password: "abcd-efgh-ijkl-mnop"
        )

        try await useCase.executeSend(emailId: email.id)

        // Verify SMTP client received PLAIN credential
        let lastCredential = await smtpClient.lastConnectCredential
        #expect(lastCredential == .plain(username: "user@icloud.com", password: "abcd-efgh-ijkl-mnop"),
                "iCloud account should use PLAIN SMTP credential")

        // Verify SMTP connected with STARTTLS security (iCloud SMTP uses STARTTLS on port 587)
        let lastSecurity = await smtpClient.lastConnectSecurity
        #expect(lastSecurity == .starttls,
                "iCloud SMTP uses STARTTLS on port 587")

        let lastHost = await smtpClient.lastConnectHost
        #expect(lastHost == "smtp.mail.me.com")

        let lastPort = await smtpClient.lastConnectPort
        #expect(lastPort == 587)

        // Verify email was sent successfully
        #expect(email.sendState == SendState.sent.rawValue)
    }

    @Test("executeSend with Yahoo account sends via PLAIN SMTP credential")
    func executeSendYahooPlainCredential() async throws {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient
        )

        let config = ProviderRegistry.provider(for: .yahoo)!
        let (_, email) = await Self.setupAppPasswordSendScenario(
            repo: repo,
            accountRepo: accountRepo,
            keychainManager: keychainManager,
            providerConfig: config,
            email: "user@yahoo.com",
            password: "yahoo-app-password"
        )

        try await useCase.executeSend(emailId: email.id)

        // Verify SMTP client received PLAIN credential
        let lastCredential = await smtpClient.lastConnectCredential
        #expect(lastCredential == .plain(username: "user@yahoo.com", password: "yahoo-app-password"),
                "Yahoo account should use PLAIN SMTP credential")

        // Verify SMTP connected with TLS security (Yahoo SMTP uses TLS on port 465)
        let lastSecurity = await smtpClient.lastConnectSecurity
        #expect(lastSecurity == .tls,
                "Yahoo SMTP uses TLS on port 465")

        let lastHost = await smtpClient.lastConnectHost
        #expect(lastHost == "smtp.mail.yahoo.com")

        let lastPort = await smtpClient.lastConnectPort
        #expect(lastPort == 465)

        #expect(email.sendState == SendState.sent.rawValue)
    }

    @Test("executeSend with Gmail account sends via XOAUTH2 SMTP credential")
    func executeSendGmailXOAuth2Credential() async throws {
        let (useCase, repo, accountRepo, keychainManager, smtpClient) = Self.makeSendSUT()
        let email = await Self.setupSendScenario(
            repo: repo, accountRepo: accountRepo, keychainManager: keychainManager
        )

        try await useCase.executeSend(emailId: email.id)

        // Verify SMTP client received XOAUTH2 credential
        let lastCredential = await smtpClient.lastConnectCredential
        if case .xoauth2(let email, let token) = lastCredential {
            #expect(email == "me@test.com")
            #expect(token == "valid-token")
        } else {
            Issue.record("Expected .xoauth2 SMTP credential, got \(String(describing: lastCredential))")
        }

        // Gmail uses TLS for SMTP (default account has no explicit security set → defaults to TLS)
        let lastSecurity = await smtpClient.lastConnectSecurity
        #expect(lastSecurity == .tls,
                "Gmail SMTP should use TLS")
    }

    @Test("executeSend with iCloud triggers IMAP APPEND to Sent folder (requiresSentAppend)")
    func executeSendICloudTriggersIMAPAppend() async throws {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let imapClient = MockIMAPClient()
        let connProvider = MockConnectionProvider(client: imapClient)

        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient,
            connectionProvider: connProvider
        )

        let config = ProviderRegistry.provider(for: .icloud)!
        let (_, email) = await Self.setupAppPasswordSendScenario(
            repo: repo,
            accountRepo: accountRepo,
            keychainManager: keychainManager,
            providerConfig: config,
            email: "user@icloud.com",
            password: "icloud-pw"
        )

        // Configure IMAP mock to return a Sent folder for the APPEND
        imapClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Sent Messages",
                imapPath: "Sent Messages",
                attributes: ["\\Sent"],
                uidValidity: 1,
                messageCount: 0
            )
        ])

        try await useCase.executeSend(emailId: email.id)

        // iCloud requires IMAP APPEND — verify it was called
        #expect(connProvider.checkoutCount == 1,
                "Should check out IMAP connection for Sent APPEND")
        #expect(imapClient.appendMessageCallCount == 1,
                "iCloud provider should trigger IMAP APPEND to Sent folder")
        #expect(imapClient.lastAppendPath == "Sent Messages",
                "APPEND should target the Sent folder IMAP path")
        #expect(imapClient.lastAppendFlags == ["\\Seen"],
                "APPENDed message should be marked as Seen")

        // Verify the IMAP connection used PLAIN credential
        #expect(connProvider.lastCredential == .plain(username: "user@icloud.com", password: "icloud-pw"),
                "IMAP APPEND should use PLAIN credential for iCloud")
    }

    @Test("executeSend with Gmail does NOT trigger IMAP APPEND (Gmail auto-copies)")
    func executeSendGmailNoIMAPAppend() async throws {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let imapClient = MockIMAPClient()
        let connProvider = MockConnectionProvider(client: imapClient)

        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient,
            connectionProvider: connProvider
        )

        // Use standard Gmail setup
        let account = Account(id: "acc-gmail", email: "me@gmail.com", displayName: "Me")
        accountRepo.accounts.append(account)

        let token = OAuthToken(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await keychainManager.store(token, for: "acc-gmail")

        let draftsFolder = Folder(name: "Drafts", imapPath: "[Gmail]/Drafts", totalCount: 0, folderType: FolderType.drafts.rawValue, uidValidity: 1)
        draftsFolder.account = account
        let sentFolder = Folder(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", totalCount: 0, folderType: FolderType.sent.rawValue, uidValidity: 1)
        sentFolder.account = account
        repo.folders = [draftsFolder, sentFolder]

        let email = Email(
            accountId: "acc-gmail",
            threadId: "thread-gmail",
            messageId: "<gmail-send@local>",
            fromAddress: "",
            toAddresses: "[\"to@test.com\"]",
            subject: "Gmail Test",
            bodyPlain: "Hello",
            dateSent: Date(),
            isRead: true,
            isDraft: false,
            sendState: SendState.queued.rawValue
        )
        let ef = EmailFolder(imapUID: 0)
        ef.email = email
        ef.folder = draftsFolder
        email.emailFolders.append(ef)
        repo.emails.append(email)

        try await useCase.executeSend(emailId: email.id)

        // Gmail does NOT require IMAP APPEND — verify it was NOT called
        #expect(connProvider.checkoutCount == 0,
                "Gmail should NOT check out IMAP connection for Sent APPEND")
        #expect(imapClient.appendMessageCallCount == 0,
                "Gmail should NOT trigger IMAP APPEND (auto-copies sent messages)")

        #expect(email.sendState == SendState.sent.rawValue)
    }

    @Test("executeSend with Yahoo triggers IMAP APPEND to Sent folder")
    func executeSendYahooTriggersIMAPAppend() async throws {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let smtpClient = MockSMTPClient()
        let imapClient = MockIMAPClient()
        let connProvider = MockConnectionProvider(client: imapClient)

        let useCase = ComposeEmailUseCase(
            repository: repo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: smtpClient,
            connectionProvider: connProvider
        )

        let config = ProviderRegistry.provider(for: .yahoo)!
        let (_, email) = await Self.setupAppPasswordSendScenario(
            repo: repo,
            accountRepo: accountRepo,
            keychainManager: keychainManager,
            providerConfig: config,
            email: "user@yahoo.com",
            password: "yahoo-pw"
        )

        // Configure IMAP mock to return a Sent folder for the APPEND
        imapClient.listFoldersResult = .success([
            IMAPFolderInfo(
                name: "Sent",
                imapPath: "Sent",
                attributes: ["\\Sent"],
                uidValidity: 1,
                messageCount: 0
            )
        ])

        try await useCase.executeSend(emailId: email.id)

        // Yahoo requires IMAP APPEND
        #expect(connProvider.checkoutCount == 1,
                "Yahoo should check out IMAP connection for Sent APPEND")
        #expect(imapClient.appendMessageCallCount == 1,
                "Yahoo provider should trigger IMAP APPEND to Sent folder")
        #expect(imapClient.lastAppendPath == "Sent")
    }
}
