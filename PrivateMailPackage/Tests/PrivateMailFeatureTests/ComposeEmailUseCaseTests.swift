import Foundation
import Testing
@testable import PrivateMailFeature

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

    @Test("saveDraft populates thread participants from recipients")
    func saveDraftPopulatesThreadParticipants() async throws {
        let (useCase, repo) = Self.makeSUT()

        _ = try await useCase.saveDraft(
            draftId: nil,
            accountId: "acc1",
            threadId: nil,
            toAddresses: ["alice@example.com", "bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Test Subject",
            bodyPlain: "Body",
            inReplyTo: nil,
            references: nil,
            attachments: []
        )

        let thread = try #require(repo.threads.first)
        let participants = Participant.decode(from: thread.participants)
        #expect(participants.count == 2)
        #expect(participants.contains { $0.email == "alice@example.com" })
        #expect(participants.contains { $0.email == "bob@example.com" })
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
}
