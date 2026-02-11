import Testing
import SwiftData
@testable import VaultMailFeature

/// Verify SwiftData model relationships and CRUD operations (AC-F-02).
@Suite("Model Relationships")
struct ModelRelationshipTests {

    /// Helper to create a fresh in-memory context for each test.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.createForTesting()
        return ModelContext(container)
    }

    // MARK: - Account → Folder relationship

    @Test("Account can have folders and relationship is navigable")
    func accountFolderRelationship() throws {
        let context = try makeContext()

        let account = Account(email: "test@gmail.com", displayName: "Test User")
        context.insert(account)

        let folder = Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue)
        folder.account = account
        context.insert(folder)

        try context.save()

        #expect(account.folders.count == 1)
        #expect(account.folders.first?.name == "Inbox")
        #expect(folder.account?.email == "test@gmail.com")
    }

    // MARK: - Email ↔ Folder (many-to-many via EmailFolder)

    @Test("Email can belong to multiple folders via EmailFolder join")
    func emailFolderManyToMany() throws {
        let context = try makeContext()

        let account = Account(email: "test@gmail.com", displayName: "Test")
        context.insert(account)

        let inbox = Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue)
        inbox.account = account
        context.insert(inbox)

        let starred = Folder(name: "Starred", imapPath: "[Gmail]/Starred", folderType: FolderType.starred.rawValue)
        starred.account = account
        context.insert(starred)

        let thread = Thread(accountId: account.id, subject: "Test Thread")
        context.insert(thread)

        let email = Email(
            accountId: account.id,
            threadId: thread.id,
            messageId: "<msg1@gmail.com>",
            fromAddress: "sender@gmail.com",
            subject: "Test Email"
        )
        email.thread = thread
        context.insert(email)

        let ef1 = EmailFolder(imapUID: 100)
        ef1.email = email
        ef1.folder = inbox
        context.insert(ef1)

        let ef2 = EmailFolder(imapUID: 200)
        ef2.email = email
        ef2.folder = starred
        context.insert(ef2)

        try context.save()

        #expect(email.emailFolders.count == 2)
        #expect(inbox.emailFolders.count == 1)
        #expect(starred.emailFolders.count == 1)
    }

    // MARK: - Email → Attachment relationship

    @Test("Email can have multiple attachments")
    func emailAttachments() throws {
        let context = try makeContext()

        let thread = Thread(accountId: "acct-1", subject: "Test")
        context.insert(thread)

        let email = Email(
            accountId: "acct-1",
            threadId: thread.id,
            messageId: "<msg@test.com>",
            fromAddress: "a@test.com",
            subject: "With attachments"
        )
        email.thread = thread
        context.insert(email)

        let att1 = Attachment(filename: "doc.pdf", mimeType: "application/pdf", sizeBytes: 1024)
        att1.email = email
        context.insert(att1)

        let att2 = Attachment(filename: "image.png", mimeType: "image/png", sizeBytes: 2048)
        att2.email = email
        context.insert(att2)

        try context.save()

        #expect(email.attachments.count == 2)
        #expect(att1.email?.id == email.id)
        #expect(att2.email?.id == email.id)
    }

    // MARK: - Thread → Email relationship

    @Test("Thread can contain multiple emails")
    func threadEmails() throws {
        let context = try makeContext()

        let thread = Thread(accountId: "acct-1", subject: "Conversation")
        context.insert(thread)

        let email1 = Email(
            accountId: "acct-1",
            threadId: thread.id,
            messageId: "<msg1@test.com>",
            fromAddress: "a@test.com",
            subject: "Conversation"
        )
        email1.thread = thread
        context.insert(email1)

        let email2 = Email(
            accountId: "acct-1",
            threadId: thread.id,
            messageId: "<msg2@test.com>",
            fromAddress: "b@test.com",
            subject: "Re: Conversation"
        )
        email2.thread = thread
        context.insert(email2)

        try context.save()

        #expect(thread.emails.count == 2)
    }

    // MARK: - CRUD Persistence

    @Test("CRUD operations persist across contexts")
    func crudPersistence() throws {
        let container = try ModelContainerFactory.createForTesting()
        let context1 = ModelContext(container)

        // Create
        let account = Account(email: "crud@test.com", displayName: "CRUD Test")
        context1.insert(account)
        try context1.save()

        // Read in new context
        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<Account>()
        let accounts = try context2.fetch(descriptor)
        #expect(accounts.count == 1)
        #expect(accounts.first?.email == "crud@test.com")

        // Update
        accounts.first?.displayName = "Updated Name"
        try context2.save()

        // Verify update in new context
        let context3 = ModelContext(container)
        let updated = try context3.fetch(descriptor)
        #expect(updated.first?.displayName == "Updated Name")
    }

    // MARK: - Default values

    @Test("Account defaults match spec")
    func accountDefaults() {
        let account = Account(email: "test@gmail.com", displayName: "Test")
        #expect(account.isActive == true)
        #expect(account.syncWindowDays == 30)
        #expect(account.imapHost == "imap.gmail.com")
        #expect(account.imapPort == 993)
        #expect(account.smtpHost == "smtp.gmail.com")
        #expect(account.smtpPort == 465)
        #expect(account.authType == "xoauth2")
    }

    @Test("Email defaults match spec")
    func emailDefaults() {
        let email = Email(
            accountId: "acct-1",
            threadId: "thread-1",
            messageId: "<msg@test.com>",
            fromAddress: "a@test.com",
            subject: "Test"
        )
        #expect(email.isRead == false)
        #expect(email.isStarred == false)
        #expect(email.isDraft == false)
        #expect(email.isDeleted == false)
        #expect(email.sendState == SendState.none.rawValue)
        #expect(email.sendRetryCount == 0)
        #expect(email.aiCategory == AICategory.uncategorized.rawValue)
    }
}
