import Testing
import SwiftData
@testable import VaultMailFeature

/// Verify cascade delete behavior per FR-FOUND-03 (AC-F-02).
@Suite("Cascade Deletes")
struct CascadeDeleteTests {

    /// Helper to create a fresh in-memory context for each test.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.createForTesting()
        return ModelContext(container)
    }

    /// Helper: creates a full account hierarchy for testing cascades.
    private func createFullHierarchy(in context: ModelContext) -> (Account, Folder, Email, Thread, EmailFolder, VaultMailFeature.Attachment) {
        let account = Account(email: "cascade@test.com", displayName: "Cascade Test")
        context.insert(account)

        let folder = Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue)
        folder.account = account
        context.insert(folder)

        let thread = Thread(accountId: account.id, subject: "Test Thread")
        context.insert(thread)

        let email = Email(
            accountId: account.id,
            threadId: thread.id,
            messageId: "<cascade@test.com>",
            fromAddress: "sender@test.com",
            subject: "Cascade Test Email"
        )
        email.thread = thread
        context.insert(email)

        let emailFolder = EmailFolder(imapUID: 42)
        emailFolder.email = email
        emailFolder.folder = folder
        context.insert(emailFolder)

        let attachment = VaultMailFeature.Attachment(filename: "file.txt", mimeType: "text/plain", sizeBytes: 100)
        attachment.email = email
        context.insert(attachment)

        return (account, folder, email, thread, emailFolder, attachment)
    }

    // MARK: - Account Cascade (FR-FOUND-03)

    @Test("Deleting Account cascades to Folders")
    func accountDeleteCascadesFolders() throws {
        let context = try makeContext()
        let (account, _, _, _, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(account)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.isEmpty, "Folders should be deleted when Account is deleted")
    }

    @Test("Deleting Account cascades through Folder to EmailFolder")
    func accountDeleteCascadesEmailFolders() throws {
        let context = try makeContext()
        let (account, _, _, _, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(account)
        try context.save()

        let emailFolders = try context.fetch(FetchDescriptor<EmailFolder>())
        #expect(emailFolders.isEmpty, "EmailFolders should be deleted when Account is deleted")
    }

    // MARK: - Email Cascade (FR-FOUND-03)

    @Test("Deleting Email cascades to EmailFolders and Attachments")
    func emailDeleteCascades() throws {
        let context = try makeContext()
        let (_, _, email, _, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(email)
        try context.save()

        let emailFolders = try context.fetch(FetchDescriptor<EmailFolder>())
        #expect(emailFolders.isEmpty, "EmailFolders should be deleted when Email is deleted")

        let attachments = try context.fetch(FetchDescriptor<VaultMailFeature.Attachment>())
        #expect(attachments.isEmpty, "Attachments should be deleted when Email is deleted")
    }

    // MARK: - Thread Cascade

    @Test("Deleting Thread cascades to Emails")
    func threadDeleteCascadesEmails() throws {
        let context = try makeContext()
        let (_, _, _, thread, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(thread)
        try context.save()

        let emails = try context.fetch(FetchDescriptor<Email>())
        #expect(emails.isEmpty, "Emails should be deleted when Thread is deleted")
    }

    @Test("Deleting Thread cascades through Email to Attachments")
    func threadDeleteCascadesAttachments() throws {
        let context = try makeContext()
        let (_, _, _, thread, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(thread)
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<VaultMailFeature.Attachment>())
        #expect(attachments.isEmpty, "Attachments should be cascade-deleted through Email when Thread is deleted")
    }

    // MARK: - Folder Cascade

    @Test("Deleting Folder cascades to EmailFolders")
    func folderDeleteCascadesEmailFolders() throws {
        let context = try makeContext()
        let (_, folder, _, _, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(folder)
        try context.save()

        let emailFolders = try context.fetch(FetchDescriptor<EmailFolder>())
        #expect(emailFolders.isEmpty, "EmailFolders should be deleted when Folder is deleted")
    }

    @Test("Deleting Folder does NOT cascade to Email (email may belong to other folders)")
    func folderDeleteDoesNotCascadeEmail() throws {
        let context = try makeContext()
        let (_, folder, _, _, _, _) = createFullHierarchy(in: context)
        try context.save()

        context.delete(folder)
        try context.save()

        // Email should survive — orphan handling is repository-layer logic
        let emails = try context.fetch(FetchDescriptor<Email>())
        #expect(!emails.isEmpty, "Email should NOT be cascade-deleted when Folder is deleted (orphan handling is repository-layer)")
    }

    // MARK: - SearchIndex cleanup

    @Test("SearchIndex can be created and deleted independently")
    func searchIndexLifecycle() throws {
        let context = try makeContext()

        let index = SearchIndex(emailId: "email-123", content: "test content")
        context.insert(index)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SearchIndex>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.emailId == "email-123")

        context.delete(index)
        try context.save()

        let afterDelete = try context.fetch(FetchDescriptor<SearchIndex>())
        #expect(afterDelete.isEmpty)
    }
}
