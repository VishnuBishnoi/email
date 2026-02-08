import Foundation
import SwiftData
import Testing
@testable import PrivateMailFeature

/// Integration tests for EmailRepositoryImpl using in-memory SwiftData.
///
/// Verifies the 3-step join strategy (Folder -> EmailFolder -> Email -> Thread),
/// cursor-based pagination, category filtering, thread actions, and batch ops.
///
/// Spec ref: FR-TL-01..04, FR-FOUND-01, FR-FOUND-03
@Suite("Email Repository Impl")
struct EmailRepositoryImplTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.createForTesting()
    }

    @MainActor
    private func makeRepo(container: ModelContainer) -> EmailRepositoryImpl {
        EmailRepositoryImpl(modelContainer: container)
    }

    /// Inserts a full hierarchy into the given container's context and returns
    /// all created entities for test assertions.
    ///
    /// Creates:
    /// - 1 account
    /// - 2 folders (inbox, sent)
    /// - 3 threads (thread1 in inbox, thread2 in inbox, thread3 in sent)
    /// - 3 emails (one per thread, linked via EmailFolder to their folder)
    /// - 3 EmailFolder join entries
    @MainActor
    private func insertTestData(
        container: ModelContainer
    ) throws -> TestData {
        let context = container.mainContext

        let account = Account(
            id: "acc-1",
            email: "user@gmail.com",
            displayName: "Test User"
        )
        context.insert(account)

        let inbox = Folder(
            id: "folder-inbox",
            name: "Inbox",
            imapPath: "INBOX",
            folderType: FolderType.inbox.rawValue
        )
        inbox.account = account
        context.insert(inbox)

        let sent = Folder(
            id: "folder-sent",
            name: "Sent",
            imapPath: "[Gmail]/Sent Mail",
            folderType: FolderType.sent.rawValue
        )
        sent.account = account
        context.insert(sent)

        let archive = Folder(
            id: "folder-archive",
            name: "All Mail",
            imapPath: "[Gmail]/All Mail",
            folderType: FolderType.archive.rawValue
        )
        archive.account = account
        context.insert(archive)

        let trash = Folder(
            id: "folder-trash",
            name: "Trash",
            imapPath: "[Gmail]/Trash",
            folderType: FolderType.trash.rawValue
        )
        trash.account = account
        context.insert(trash)

        let now = Date()

        // Thread 1: in inbox, primary, 2 unread, latest = now
        let thread1 = PrivateMailFeature.Thread(
            id: "thread-1",
            accountId: "acc-1",
            subject: "Hello World",
            latestDate: now,
            messageCount: 3,
            unreadCount: 2,
            isStarred: false,
            aiCategory: AICategory.primary.rawValue,
            snippet: "Latest message preview"
        )
        context.insert(thread1)

        // Thread 2: in inbox, social, 1 unread, latest = now - 1 hour
        let thread2 = PrivateMailFeature.Thread(
            id: "thread-2",
            accountId: "acc-1",
            subject: "Social Update",
            latestDate: now.addingTimeInterval(-3600),
            messageCount: 1,
            unreadCount: 1,
            isStarred: true,
            aiCategory: AICategory.social.rawValue,
            snippet: "Social notification"
        )
        context.insert(thread2)

        // Thread 3: in sent, primary, 0 unread, latest = now - 2 hours
        let thread3 = PrivateMailFeature.Thread(
            id: "thread-3",
            accountId: "acc-1",
            subject: "Sent Email",
            latestDate: now.addingTimeInterval(-7200),
            messageCount: 1,
            unreadCount: 0,
            isStarred: false,
            aiCategory: AICategory.primary.rawValue,
            snippet: "Outgoing message"
        )
        context.insert(thread3)

        // Email 1 -> thread1 -> inbox
        let email1 = Email(
            id: "email-1",
            accountId: "acc-1",
            threadId: "thread-1",
            messageId: "<msg1@test.com>",
            fromAddress: "sender@test.com",
            subject: "Hello World",
            dateReceived: now
        )
        email1.thread = thread1
        context.insert(email1)

        let ef1 = EmailFolder(id: "ef-1", imapUID: 100)
        ef1.email = email1
        ef1.folder = inbox
        context.insert(ef1)

        // Email 2 -> thread2 -> inbox
        let email2 = Email(
            id: "email-2",
            accountId: "acc-1",
            threadId: "thread-2",
            messageId: "<msg2@test.com>",
            fromAddress: "social@example.com",
            subject: "Social Update",
            dateReceived: now.addingTimeInterval(-3600)
        )
        email2.thread = thread2
        context.insert(email2)

        let ef2 = EmailFolder(id: "ef-2", imapUID: 101)
        ef2.email = email2
        ef2.folder = inbox
        context.insert(ef2)

        // Email 3 -> thread3 -> sent
        let email3 = Email(
            id: "email-3",
            accountId: "acc-1",
            threadId: "thread-3",
            messageId: "<msg3@test.com>",
            fromAddress: "user@gmail.com",
            subject: "Sent Email",
            dateReceived: now.addingTimeInterval(-7200)
        )
        email3.thread = thread3
        context.insert(email3)

        let ef3 = EmailFolder(id: "ef-3", imapUID: 200)
        ef3.email = email3
        ef3.folder = sent
        context.insert(ef3)

        try context.save()

        return TestData(
            account: account,
            inbox: inbox,
            sent: sent,
            archive: archive,
            trash: trash,
            thread1: thread1,
            thread2: thread2,
            thread3: thread3,
            email1: email1,
            email2: email2,
            email3: email3,
            now: now
        )
    }

    struct TestData {
        let account: Account
        let inbox: Folder
        let sent: Folder
        let archive: Folder
        let trash: Folder
        let thread1: PrivateMailFeature.Thread
        let thread2: PrivateMailFeature.Thread
        let thread3: PrivateMailFeature.Thread
        let email1: Email
        let email2: Email
        let email3: Email
        let now: Date
    }

    // MARK: - getThreads(folderId:) 3-Step Join

    @Test("getThreads returns threads for folder via 3-step join")
    @MainActor
    func getThreadsForFolder() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let inboxThreads = try await repo.getThreads(
            folderId: data.inbox.id,
            category: nil,
            cursor: nil,
            limit: 50
        )

        #expect(inboxThreads.count == 2)
        // Sorted by latestDate DESC: thread1 (now) then thread2 (now - 1h)
        #expect(inboxThreads[0].id == "thread-1")
        #expect(inboxThreads[1].id == "thread-2")

        let sentThreads = try await repo.getThreads(
            folderId: data.sent.id,
            category: nil,
            cursor: nil,
            limit: 50
        )

        #expect(sentThreads.count == 1)
        #expect(sentThreads[0].id == "thread-3")
    }

    @Test("getThreads empty folder returns empty array")
    @MainActor
    func getThreadsEmptyFolder() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let account = Account(id: "acc-empty", email: "empty@test.com", displayName: "Empty")
        context.insert(account)
        let emptyFolder = Folder(id: "folder-empty", name: "Empty", imapPath: "Empty")
        emptyFolder.account = account
        context.insert(emptyFolder)
        try context.save()

        let repo = makeRepo(container: container)
        let threads = try await repo.getThreads(
            folderId: "folder-empty",
            category: nil,
            cursor: nil,
            limit: 50
        )
        #expect(threads.isEmpty)
    }

    // MARK: - Pagination

    @Test("getThreads pagination with cursor and limit")
    @MainActor
    func getThreadsPagination() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Page 1: limit 1, no cursor -> should get thread1 (newest)
        let page1 = try await repo.getThreads(
            folderId: data.inbox.id,
            category: nil,
            cursor: nil,
            limit: 1
        )
        #expect(page1.count == 1)
        #expect(page1[0].id == "thread-1")

        // Page 2: cursor = thread1.latestDate -> should get thread2 (older)
        let page2 = try await repo.getThreads(
            folderId: data.inbox.id,
            category: nil,
            cursor: data.thread1.latestDate,
            limit: 1
        )
        #expect(page2.count == 1)
        #expect(page2[0].id == "thread-2")

        // Page 3: cursor = thread2.latestDate -> should be empty (no more)
        let page3 = try await repo.getThreads(
            folderId: data.inbox.id,
            category: nil,
            cursor: data.thread2.latestDate,
            limit: 1
        )
        #expect(page3.isEmpty)
    }

    // MARK: - Category Filter

    @Test("getThreads with category filter returns only matching threads")
    @MainActor
    func getThreadsCategoryFilter() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Filter by primary -> only thread1
        let primary = try await repo.getThreads(
            folderId: data.inbox.id,
            category: AICategory.primary.rawValue,
            cursor: nil,
            limit: 50
        )
        #expect(primary.count == 1)
        #expect(primary[0].id == "thread-1")

        // Filter by social -> only thread2
        let social = try await repo.getThreads(
            folderId: data.inbox.id,
            category: AICategory.social.rawValue,
            cursor: nil,
            limit: 50
        )
        #expect(social.count == 1)
        #expect(social[0].id == "thread-2")

        // Filter by promotions -> empty
        let promos = try await repo.getThreads(
            folderId: data.inbox.id,
            category: AICategory.promotions.rawValue,
            cursor: nil,
            limit: 50
        )
        #expect(promos.isEmpty)
    }

    // MARK: - Unified Inbox

    @Test("getThreadsUnified returns all threads across accounts")
    @MainActor
    func getThreadsUnified() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()

        // Account 1 thread
        let thread1 = PrivateMailFeature.Thread(
            id: "unified-1",
            accountId: "acc-a",
            subject: "From Account A",
            latestDate: now,
            messageCount: 1,
            unreadCount: 0
        )
        context.insert(thread1)

        // Account 2 thread
        let thread2 = PrivateMailFeature.Thread(
            id: "unified-2",
            accountId: "acc-b",
            subject: "From Account B",
            latestDate: now.addingTimeInterval(-600),
            messageCount: 1,
            unreadCount: 1,
            aiCategory: AICategory.social.rawValue
        )
        context.insert(thread2)

        try context.save()

        let repo = makeRepo(container: container)

        // All threads
        let all = try await repo.getThreadsUnified(
            category: nil,
            cursor: nil,
            limit: 50
        )
        #expect(all.count == 2)
        #expect(all[0].id == "unified-1") // most recent first
        #expect(all[1].id == "unified-2")

        // Filtered by social
        let socialOnly = try await repo.getThreadsUnified(
            category: AICategory.social.rawValue,
            cursor: nil,
            limit: 50
        )
        #expect(socialOnly.count == 1)
        #expect(socialOnly[0].id == "unified-2")
    }

    // MARK: - Outbox Emails

    @Test("getOutboxEmails returns only queued, sending, and failed emails")
    @MainActor
    func getOutboxEmails() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let thread = PrivateMailFeature.Thread(
            id: "outbox-thread",
            accountId: "acc-1",
            subject: "Outbox"
        )
        context.insert(thread)

        let queuedEmail = Email(
            id: "outbox-queued",
            accountId: "acc-1",
            threadId: "outbox-thread",
            messageId: "<queued@test.com>",
            fromAddress: "me@test.com",
            subject: "Queued",
            sendState: SendState.queued.rawValue
        )
        queuedEmail.thread = thread
        context.insert(queuedEmail)

        let sendingEmail = Email(
            id: "outbox-sending",
            accountId: "acc-1",
            threadId: "outbox-thread",
            messageId: "<sending@test.com>",
            fromAddress: "me@test.com",
            subject: "Sending",
            sendState: SendState.sending.rawValue
        )
        sendingEmail.thread = thread
        context.insert(sendingEmail)

        let failedEmail = Email(
            id: "outbox-failed",
            accountId: "acc-1",
            threadId: "outbox-thread",
            messageId: "<failed@test.com>",
            fromAddress: "me@test.com",
            subject: "Failed",
            sendState: SendState.failed.rawValue
        )
        failedEmail.thread = thread
        context.insert(failedEmail)

        // Normal email (sent) — should NOT be in outbox
        let sentEmail = Email(
            id: "outbox-sent",
            accountId: "acc-1",
            threadId: "outbox-thread",
            messageId: "<sent@test.com>",
            fromAddress: "me@test.com",
            subject: "Sent",
            sendState: SendState.sent.rawValue
        )
        sentEmail.thread = thread
        context.insert(sentEmail)

        // Normal email (none) — should NOT be in outbox
        let normalEmail = Email(
            id: "outbox-normal",
            accountId: "acc-1",
            threadId: "outbox-thread",
            messageId: "<normal@test.com>",
            fromAddress: "me@test.com",
            subject: "Normal",
            sendState: SendState.none.rawValue
        )
        normalEmail.thread = thread
        context.insert(normalEmail)

        try context.save()

        let repo = makeRepo(container: container)

        let outbox = try await repo.getOutboxEmails(accountId: "acc-1")
        #expect(outbox.count == 3)

        let outboxIds = Set(outbox.map(\.id))
        #expect(outboxIds.contains("outbox-queued"))
        #expect(outboxIds.contains("outbox-sending"))
        #expect(outboxIds.contains("outbox-failed"))
        #expect(!outboxIds.contains("outbox-sent"))
        #expect(!outboxIds.contains("outbox-normal"))
    }

    // MARK: - Unread Counts

    @Test("getUnreadCounts returns per-category counts for folder")
    @MainActor
    func getUnreadCounts() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let counts = try await repo.getUnreadCounts(folderId: data.inbox.id)

        // thread1: primary, unreadCount=2 ; thread2: social, unreadCount=1
        #expect(counts[AICategory.primary.rawValue] == 2)
        #expect(counts[AICategory.social.rawValue] == 1)
        // promotions not present
        #expect(counts[AICategory.promotions.rawValue] == nil)
    }

    @Test("getUnreadCountsUnified aggregates across all threads")
    @MainActor
    func getUnreadCountsUnified() async throws {
        let container = try makeContainer()
        _ = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let counts = try await repo.getUnreadCountsUnified()

        // thread1: primary, 2 unread; thread2: social, 1 unread; thread3: primary, 0 unread
        #expect(counts[AICategory.primary.rawValue] == 2)
        #expect(counts[AICategory.social.rawValue] == 1)
    }

    // MARK: - Archive Thread

    @Test("archiveThread moves thread emails to Archive folder")
    @MainActor
    func archiveThreadRemoves() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        try await repo.archiveThread(id: data.thread1.id)

        // Thread still exists (move, not delete)
        let thread = try await repo.getThread(id: data.thread1.id)
        #expect(thread != nil)

        // Thread should no longer appear in inbox
        let inboxThreads = try await repo.getThreads(
            folderId: data.inbox.id, category: nil, cursor: nil, limit: 25
        )
        #expect(!inboxThreads.contains { $0.id == "thread-1" })

        // Thread should now be in archive
        let archiveThreads = try await repo.getThreads(
            folderId: data.archive.id, category: nil, cursor: nil, limit: 25
        )
        #expect(archiveThreads.contains { $0.id == "thread-1" })
    }

    @Test("archiveThread throws for non-existent thread")
    @MainActor
    func archiveThreadNotFound() async throws {
        let container = try makeContainer()
        let repo = makeRepo(container: container)

        await #expect(throws: ThreadListError.self) {
            try await repo.archiveThread(id: "non-existent")
        }
    }

    // MARK: - Delete Thread

    @Test("deleteThread moves thread emails to Trash folder")
    @MainActor
    func deleteThreadRemoves() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        try await repo.deleteThread(id: data.thread2.id)

        // Thread still exists (move to trash, not hard-delete)
        let thread = try await repo.getThread(id: data.thread2.id)
        #expect(thread != nil)

        // Thread should no longer appear in inbox
        let inboxThreads = try await repo.getThreads(
            folderId: data.inbox.id, category: nil, cursor: nil, limit: 25
        )
        #expect(!inboxThreads.contains { $0.id == "thread-2" })

        // Thread should now be in trash
        let trashThreads = try await repo.getThreads(
            folderId: data.trash.id, category: nil, cursor: nil, limit: 25
        )
        #expect(trashThreads.contains { $0.id == "thread-2" })
    }

    // MARK: - Toggle Read Status

    @Test("toggleReadStatus flips unread count")
    @MainActor
    func toggleReadStatus() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // thread1 has unreadCount=2 -> toggle -> 0
        try await repo.toggleReadStatus(threadId: data.thread1.id)
        let toggled = try await repo.getThread(id: data.thread1.id)
        #expect(toggled?.unreadCount == 0)

        // Toggle again -> 0 -> 1
        try await repo.toggleReadStatus(threadId: data.thread1.id)
        let toggledBack = try await repo.getThread(id: data.thread1.id)
        #expect(toggledBack?.unreadCount == 1)
    }

    @Test("toggleReadStatus throws for non-existent thread")
    @MainActor
    func toggleReadStatusNotFound() async throws {
        let container = try makeContainer()
        let repo = makeRepo(container: container)

        await #expect(throws: ThreadListError.self) {
            try await repo.toggleReadStatus(threadId: "non-existent")
        }
    }

    // MARK: - Toggle Star Status

    @Test("toggleStarStatus flips star status")
    @MainActor
    func toggleStarStatus() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // thread1 is not starred -> toggle -> starred
        try await repo.toggleStarStatus(threadId: data.thread1.id)
        let toggled = try await repo.getThread(id: data.thread1.id)
        #expect(toggled?.isStarred == true)

        // Toggle again -> unstarred
        try await repo.toggleStarStatus(threadId: data.thread1.id)
        let toggledBack = try await repo.getThread(id: data.thread1.id)
        #expect(toggledBack?.isStarred == false)
    }

    @Test("toggleStarStatus throws for non-existent thread")
    @MainActor
    func toggleStarStatusNotFound() async throws {
        let container = try makeContainer()
        let repo = makeRepo(container: container)

        await #expect(throws: ThreadListError.self) {
            try await repo.toggleStarStatus(threadId: "non-existent")
        }
    }

    // MARK: - Move Thread

    @Test("moveThread updates email folder associations")
    @MainActor
    func moveThread() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Move thread1 from inbox to sent
        try await repo.moveThread(id: data.thread1.id, toFolderId: data.sent.id)

        // Thread1 should now appear in sent folder
        let sentThreads = try await repo.getThreads(
            folderId: data.sent.id,
            category: nil,
            cursor: nil,
            limit: 50
        )
        let sentIds = sentThreads.map(\.id)
        #expect(sentIds.contains("thread-1"))

        // Thread1 should no longer appear in inbox
        let inboxThreads = try await repo.getThreads(
            folderId: data.inbox.id,
            category: nil,
            cursor: nil,
            limit: 50
        )
        let inboxIds = inboxThreads.map(\.id)
        #expect(!inboxIds.contains("thread-1"))
    }

    @Test("moveThread throws for non-existent thread")
    @MainActor
    func moveThreadNotFoundThread() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        await #expect(throws: ThreadListError.self) {
            try await repo.moveThread(id: "non-existent", toFolderId: data.sent.id)
        }
    }

    @Test("moveThread throws for non-existent folder")
    @MainActor
    func moveThreadNotFoundFolder() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        await #expect(throws: ThreadListError.self) {
            try await repo.moveThread(id: data.thread1.id, toFolderId: "non-existent")
        }
    }

    // MARK: - Batch Operations

    @Test("batch markThreadsRead sets unread count to zero")
    @MainActor
    func batchMarkRead() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        try await repo.markThreadsRead(ids: [data.thread1.id, data.thread2.id])

        let t1 = try await repo.getThread(id: data.thread1.id)
        let t2 = try await repo.getThread(id: data.thread2.id)
        #expect(t1?.unreadCount == 0)
        #expect(t2?.unreadCount == 0)
    }

    @Test("batch markThreadsUnread sets unread count to one")
    @MainActor
    func batchMarkUnread() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // First mark as read
        try await repo.markThreadsRead(ids: [data.thread1.id])
        let read = try await repo.getThread(id: data.thread1.id)
        #expect(read?.unreadCount == 0)

        // Then mark as unread
        try await repo.markThreadsUnread(ids: [data.thread1.id])
        let unread = try await repo.getThread(id: data.thread1.id)
        #expect(unread?.unreadCount == 1)
    }

    @Test("batch starThreads sets isStarred to true")
    @MainActor
    func batchStar() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // thread1 is not starred, thread3 is not starred
        try await repo.starThreads(ids: [data.thread1.id, data.thread3.id])

        let t1 = try await repo.getThread(id: data.thread1.id)
        let t3 = try await repo.getThread(id: data.thread3.id)
        #expect(t1?.isStarred == true)
        #expect(t3?.isStarred == true)
    }

    @Test("batch deleteThreads moves multiple threads to Trash")
    @MainActor
    func batchDelete() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        try await repo.deleteThreads(ids: [data.thread1.id, data.thread2.id])

        // Both threads still exist (moved to trash, not hard-deleted)
        let t1 = try await repo.getThread(id: data.thread1.id)
        let t2 = try await repo.getThread(id: data.thread2.id)
        #expect(t1 != nil)
        #expect(t2 != nil)

        // Inbox should only have thread3's email remaining... but thread3 is in sent
        // So inbox should be empty
        let inboxThreads = try await repo.getThreads(
            folderId: data.inbox.id, category: nil, cursor: nil, limit: 25
        )
        #expect(inboxThreads.isEmpty)

        // Both threads should be in trash
        let trashThreads = try await repo.getThreads(
            folderId: data.trash.id, category: nil, cursor: nil, limit: 25
        )
        let trashIds = Set(trashThreads.map(\.id))
        #expect(trashIds.contains("thread-1"))
        #expect(trashIds.contains("thread-2"))
    }

    // MARK: - Basic CRUD

    @Test("getFolders returns folders for account")
    @MainActor
    func getFolders() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let folders = try await repo.getFolders(accountId: data.account.id)
        #expect(folders.count == 4)

        let names = Set(folders.map(\.name))
        #expect(names.contains("Inbox"))
        #expect(names.contains("Sent"))
        #expect(names.contains("All Mail"))
        #expect(names.contains("Trash"))
    }

    @Test("saveFolder inserts new folder")
    @MainActor
    func saveFolderInsert() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let account = Account(id: "acc-save", email: "save@test.com", displayName: "Save")
        context.insert(account)
        try context.save()

        let repo = makeRepo(container: container)

        let folder = Folder(id: "folder-new", name: "Drafts", imapPath: "[Gmail]/Drafts")
        try await repo.saveFolder(folder)

        let verifyContext = container.mainContext
        var desc = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == "folder-new" })
        desc.fetchLimit = 1
        let fetched = try verifyContext.fetch(desc)
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Drafts")
    }

    @Test("saveFolder updates existing folder")
    @MainActor
    func saveFolderUpdate() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let updatedFolder = Folder(
            id: data.inbox.id,
            name: "Updated Inbox",
            imapPath: "INBOX",
            unreadCount: 42
        )
        try await repo.saveFolder(updatedFolder)

        let folders = try await repo.getFolders(accountId: data.account.id)
        let inbox = folders.first { $0.id == data.inbox.id }
        #expect(inbox?.name == "Updated Inbox")
        #expect(inbox?.unreadCount == 42)
    }

    @Test("saveThread inserts new and updates existing")
    @MainActor
    func saveThreadInsertAndUpdate() async throws {
        let container = try makeContainer()
        let repo = makeRepo(container: container)

        // Insert
        let thread = PrivateMailFeature.Thread(
            id: "save-thread",
            accountId: "acc-x",
            subject: "Original Subject"
        )
        try await repo.saveThread(thread)
        let fetched = try await repo.getThread(id: "save-thread")
        #expect(fetched?.subject == "Original Subject")

        // Update
        let updated = PrivateMailFeature.Thread(
            id: "save-thread",
            accountId: "acc-x",
            subject: "Updated Subject",
            unreadCount: 5
        )
        try await repo.saveThread(updated)
        let reFetched = try await repo.getThread(id: "save-thread")
        #expect(reFetched?.subject == "Updated Subject")
        #expect(reFetched?.unreadCount == 5)
    }

    @Test("getEmails returns emails for folder via EmailFolder join")
    @MainActor
    func getEmailsForFolder() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let inboxEmails = try await repo.getEmails(folderId: data.inbox.id)
        #expect(inboxEmails.count == 2)

        let sentEmails = try await repo.getEmails(folderId: data.sent.id)
        #expect(sentEmails.count == 1)
        #expect(sentEmails[0].id == "email-3")
    }

    // MARK: - saveEmail

    @Test("saveEmail inserts new email")
    @MainActor
    func saveEmailInsert() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        let newEmail = Email(
            id: "email-new",
            accountId: "acc-1",
            threadId: data.thread1.id,
            messageId: "<new@test.com>",
            fromAddress: "new@test.com",
            subject: "New Email"
        )
        try await repo.saveEmail(newEmail)

        let context = container.mainContext
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == "email-new" }
        )
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].subject == "New Email")
        #expect(fetched[0].fromAddress == "new@test.com")
    }

    @Test("saveEmail updates existing email fields")
    @MainActor
    func saveEmailUpdate() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Modify email1's subject and isRead
        let updated = Email(
            id: data.email1.id,
            accountId: "acc-1",
            threadId: data.thread1.id,
            messageId: "<msg1@test.com>",
            fromAddress: "sender@test.com",
            subject: "Updated Subject",
            isRead: true
        )
        try await repo.saveEmail(updated)

        let context = container.mainContext
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == "email-1" }
        )
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].subject == "Updated Subject")
        #expect(fetched[0].isRead == true)
    }

    // MARK: - deleteEmail

    @Test("deleteEmail removes email from store")
    @MainActor
    func deleteEmailRemoves() async throws {
        let container = try makeContainer()
        let data = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        try await repo.deleteEmail(id: data.email1.id)

        let context = container.mainContext
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == "email-1" }
        )
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        #expect(fetched.isEmpty)

        // Thread should still exist
        let thread = try await repo.getThread(id: data.thread1.id)
        #expect(thread != nil)
    }

    @Test("deleteEmail with non-existent id does nothing")
    @MainActor
    func deleteEmailNotFoundNoError() async throws {
        let container = try makeContainer()
        _ = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Should not throw
        try await repo.deleteEmail(id: "non-existent-email-id")
    }

    // MARK: - markThreadsRead with empty ids

    @Test("markThreadsRead with empty ids does nothing")
    @MainActor
    func batchEmptyIds() async throws {
        let container = try makeContainer()
        _ = try insertTestData(container: container)
        let repo = makeRepo(container: container)

        // Should succeed without error
        try await repo.markThreadsRead(ids: [])
    }

    // MARK: - getOutboxEmails cross-account

    @Test("getOutboxEmails with nil accountId returns all accounts")
    @MainActor
    func outboxEmailsCrossAccount() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Account 1 thread + email
        let thread1 = PrivateMailFeature.Thread(
            id: "outbox-cross-t1",
            accountId: "acc-a",
            subject: "Cross A"
        )
        context.insert(thread1)

        let email1 = Email(
            id: "outbox-cross-e1",
            accountId: "acc-a",
            threadId: "outbox-cross-t1",
            messageId: "<cross1@test.com>",
            fromAddress: "a@test.com",
            subject: "Queued A",
            sendState: SendState.queued.rawValue
        )
        email1.thread = thread1
        context.insert(email1)

        // Account 2 thread + email
        let thread2 = PrivateMailFeature.Thread(
            id: "outbox-cross-t2",
            accountId: "acc-b",
            subject: "Cross B"
        )
        context.insert(thread2)

        let email2 = Email(
            id: "outbox-cross-e2",
            accountId: "acc-b",
            threadId: "outbox-cross-t2",
            messageId: "<cross2@test.com>",
            fromAddress: "b@test.com",
            subject: "Failed B",
            sendState: SendState.failed.rawValue
        )
        email2.thread = thread2
        context.insert(email2)

        try context.save()

        let repo = makeRepo(container: container)

        let outbox = try await repo.getOutboxEmails(accountId: nil)
        #expect(outbox.count == 2)

        let outboxIds = Set(outbox.map(\.id))
        #expect(outboxIds.contains("outbox-cross-e1"))
        #expect(outboxIds.contains("outbox-cross-e2"))
    }
}
