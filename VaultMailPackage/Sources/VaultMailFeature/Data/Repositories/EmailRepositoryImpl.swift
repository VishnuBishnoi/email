import Foundation
import SwiftData

/// SwiftData implementation of EmailRepositoryProtocol.
///
/// All operations run on `@MainActor` because SwiftData's `ModelContext`
/// requires main-actor isolation.
///
/// Spec ref: Foundation FR-FOUND-01, Thread List FR-TL-01..04
@MainActor
public final class EmailRepositoryImpl: EmailRepositoryProtocol {

    private let modelContainer: ModelContainer

    /// Single shared context for all operations. Safe because this class is @MainActor.
    private var context: ModelContext {
        modelContainer.mainContext
    }

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Batch Flush

    public func flushChanges() async throws {
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: - Folders

    public func getFolders(accountId: String) async throws -> [Folder] {

        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.account?.id == accountId },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func saveFolder(_ folder: Folder) async throws {

        let folderId = folder.id
        var descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.id == folderId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.name = folder.name
            existing.imapPath = folder.imapPath
            existing.unreadCount = folder.unreadCount
            existing.totalCount = folder.totalCount
            existing.folderType = folder.folderType
            existing.uidValidity = folder.uidValidity
            existing.lastSyncDate = folder.lastSyncDate
        } else {
            context.insert(folder)
        }
        try context.save()
    }

    public func deleteFolder(id: String) async throws {

        var descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let folder = try context.fetch(descriptor).first else {
            throw ThreadListError.folderNotFound(id: id)
        }
        // Cascade handles EmailFolder join entries (FR-FOUND-03)
        context.delete(folder)
        try context.save()
    }

    // MARK: - Emails

    public func getEmails(folderId: String) async throws -> [Email] {

        // 2-step: EmailFolder -> Email
        let efDescriptor = FetchDescriptor<EmailFolder>(
            predicate: #Predicate<EmailFolder> { $0.folder?.id == folderId }
        )
        let emailFolders = try context.fetch(efDescriptor)
        return emailFolders.compactMap { $0.email }
    }

    @discardableResult
    public func saveEmail(_ email: Email) async throws -> Email {

        let emailId = email.id
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == emailId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.fromAddress = email.fromAddress
            existing.fromName = email.fromName
            existing.toAddresses = email.toAddresses
            existing.ccAddresses = email.ccAddresses
            existing.bccAddresses = email.bccAddresses
            existing.subject = email.subject
            existing.bodyPlain = email.bodyPlain
            existing.bodyHTML = email.bodyHTML
            existing.snippet = email.snippet
            existing.dateReceived = email.dateReceived
            existing.dateSent = email.dateSent
            existing.isRead = email.isRead
            existing.isStarred = email.isStarred
            existing.isDraft = email.isDraft
            existing.isDeleted = email.isDeleted
            existing.aiCategory = email.aiCategory
            existing.aiSummary = email.aiSummary
            existing.sizeBytes = email.sizeBytes
            existing.sendState = email.sendState
            existing.sendRetryCount = email.sendRetryCount
            existing.sendQueuedDate = email.sendQueuedDate
            return existing
        } else {
            context.insert(email)
            return email
        }
        // No explicit save — callers use flushChanges() for batch persistence,
        // or SwiftData auto-saves at the end of the run loop cycle.
    }

    public func deleteEmail(id: String) async throws {

        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let email = try context.fetch(descriptor).first else { return }
        // Cascade handles EmailFolder + Attachment cleanup (FR-FOUND-03)
        context.delete(email)
        try context.save()
    }

    // MARK: - Threads (Basic)

    public func getThreads(accountId: String) async throws -> [VaultMailFeature.Thread] {

        let descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.accountId == accountId },
            sortBy: [SortDescriptor(\.latestDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func getThread(id: String) async throws -> VaultMailFeature.Thread? {

        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func saveThread(_ thread: VaultMailFeature.Thread) async throws {

        let threadId = thread.id
        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.subject = thread.subject
            existing.latestDate = thread.latestDate
            existing.messageCount = thread.messageCount
            existing.unreadCount = thread.unreadCount
            existing.isStarred = thread.isStarred
            existing.aiCategory = thread.aiCategory
            existing.aiSummary = thread.aiSummary
            existing.snippet = thread.snippet
            existing.participants = thread.participants
        } else {
            context.insert(thread)
        }
        // No explicit save — callers use flushChanges() for batch persistence,
        // or SwiftData auto-saves at the end of the run loop cycle.
        // Calling context.save() here caused "store went missing" crashes when
        // Thread objects reference Emails with temporary persistent identifiers
        // that were inserted in the same sync batch.
    }

    // MARK: - Thread List Queries (FR-TL-01, FR-TL-02)

    public func getThreads(
        folderId: String,
        category: String?,
        cursor: Date?,
        limit: Int
    ) async throws -> [VaultMailFeature.Thread] {


        // Step 1: Fetch EmailFolder entries for the given folderId
        let efDescriptor = FetchDescriptor<EmailFolder>(
            predicate: #Predicate<EmailFolder> { $0.folder?.id == folderId }
        )
        let emailFolders = try context.fetch(efDescriptor)

        // Step 2: Collect unique threadIds via the Email relationship
        var threadIds = Set<String>()
        for ef in emailFolders {
            if let threadId = ef.email?.threadId {
                threadIds.insert(threadId)
            }
        }

        guard !threadIds.isEmpty else { return [] }

        // Step 3: Fetch all threads and filter in memory
        // (SwiftData #Predicate doesn't support Set.contains())
        let allThreadsDescriptor = FetchDescriptor<VaultMailFeature.Thread>(
            sortBy: [SortDescriptor(\.latestDate, order: .reverse)]
        )
        let allThreads = try context.fetch(allThreadsDescriptor)

        let filtered = allThreads.filter { thread in
            // Must be in the folder's thread set
            guard threadIds.contains(thread.id) else { return false }

            // Category filter
            if let category, thread.aiCategory != category {
                return false
            }

            // Cursor-based pagination: only threads older than cursor
            if let cursor, let latestDate = thread.latestDate {
                if latestDate >= cursor { return false }
            } else if let cursor, thread.latestDate == nil {
                // Threads with nil latestDate are treated as older than any cursor
                _ = cursor
            }

            return true
        }

        return Array(filtered.prefix(limit))
    }

    public func getThreadsUnified(
        category: String?,
        cursor: Date?,
        limit: Int
    ) async throws -> [VaultMailFeature.Thread] {

        let descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            sortBy: [SortDescriptor(\.latestDate, order: .reverse)]
        )
        var threads = try context.fetch(descriptor)

        // Apply category filter
        if let category {
            threads = threads.filter { $0.aiCategory == category }
        }

        // Apply cursor-based pagination
        if let cursor {
            threads = threads.filter { thread in
                guard let latestDate = thread.latestDate else { return true }
                return latestDate < cursor
            }
        }

        return Array(threads.prefix(limit))
    }

    public func getOutboxEmails(accountId: String?) async throws -> [Email] {

        let queuedState = SendState.queued.rawValue
        let sendingState = SendState.sending.rawValue
        let failedState = SendState.failed.rawValue

        if let accountId {
            let descriptor = FetchDescriptor<Email>(
                predicate: #Predicate {
                    $0.accountId == accountId && (
                        $0.sendState == queuedState ||
                        $0.sendState == sendingState ||
                        $0.sendState == failedState
                    )
                },
                sortBy: [SortDescriptor(\.sendQueuedDate, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<Email>(
                predicate: #Predicate {
                    $0.sendState == queuedState ||
                    $0.sendState == sendingState ||
                    $0.sendState == failedState
                },
                sortBy: [SortDescriptor(\.sendQueuedDate, order: .reverse)]
            )
            return try context.fetch(descriptor)
        }
    }

    public func getUnreadCounts(folderId: String) async throws -> [String?: Int] {


        // 3-step join: get threads for this folder
        let efDescriptor = FetchDescriptor<EmailFolder>(
            predicate: #Predicate<EmailFolder> { $0.folder?.id == folderId }
        )
        let emailFolders = try context.fetch(efDescriptor)

        var threadIds = Set<String>()
        for ef in emailFolders {
            if let threadId = ef.email?.threadId {
                threadIds.insert(threadId)
            }
        }

        guard !threadIds.isEmpty else { return [:] }

        let allThreadsDescriptor = FetchDescriptor<VaultMailFeature.Thread>()
        let allThreads = try context.fetch(allThreadsDescriptor)
        let folderThreads = allThreads.filter { threadIds.contains($0.id) && $0.unreadCount > 0 }

        // Aggregate unread counts per aiCategory
        var counts: [String?: Int] = [:]
        for thread in folderThreads {
            let key = thread.aiCategory
            counts[key, default: 0] += thread.unreadCount
        }
        return counts
    }

    public func getUnreadCountsUnified() async throws -> [String?: Int] {

        let descriptor = FetchDescriptor<VaultMailFeature.Thread>()
        let allThreads = try context.fetch(descriptor)

        var counts: [String?: Int] = [:]
        for thread in allThreads where thread.unreadCount > 0 {
            let key = thread.aiCategory
            counts[key, default: 0] += thread.unreadCount
        }
        return counts
    }

    // MARK: - Thread Actions (FR-TL-03)

    public func archiveThread(id: String) async throws {

        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let thread = try context.fetch(descriptor).first else {
            throw ThreadListError.threadNotFound(id: id)
        }

        // Find the Archive folder for this thread's account
        let threadAccountId = thread.accountId
        let archiveType = FolderType.archive.rawValue
        var archiveDescriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.account?.id == threadAccountId && $0.folderType == archiveType }
        )
        archiveDescriptor.fetchLimit = 1

        guard let archiveFolder = try context.fetch(archiveDescriptor).first else {
            throw ThreadListError.folderNotFound(id: "archive(\(threadAccountId))")
        }

        // Archive: remove Inbox association, add Archive, preserve other labels.
        // PR #8 Comment 3: Multi-label semantics — only remove Inbox, keep custom labels.
        let inboxType = FolderType.inbox.rawValue
        for email in thread.emails {
            // Remove ONLY Inbox folder associations
            let inboxEFs = email.emailFolders.filter { $0.folder?.folderType == inboxType }
            for ef in inboxEFs {
                context.delete(ef)
            }

            // Add Archive association if not already present
            let alreadyInArchive = email.emailFolders.contains { $0.folder?.id == archiveFolder.id }
            if !alreadyInArchive {
                let newEF = EmailFolder(imapUID: 0)
                newEF.email = email
                newEF.folder = archiveFolder
                context.insert(newEF)
            }
        }

        try context.save()
    }

    public func deleteThread(id: String) async throws {

        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let thread = try context.fetch(descriptor).first else {
            throw ThreadListError.threadNotFound(id: id)
        }

        // Find the Trash folder for this thread's account
        let threadAccountId = thread.accountId
        let trashType = FolderType.trash.rawValue
        var trashDescriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.account?.id == threadAccountId && $0.folderType == trashType }
        )
        trashDescriptor.fetchLimit = 1

        guard let trashFolder = try context.fetch(trashDescriptor).first else {
            throw ThreadListError.folderNotFound(id: "trash(\(threadAccountId))")
        }

        // Move all emails in the thread to the Trash folder
        for email in thread.emails {
            for ef in email.emailFolders {
                context.delete(ef)
            }
            let newEF = EmailFolder(imapUID: 0)
            newEF.email = email
            newEF.folder = trashFolder
            context.insert(newEF)
        }

        try context.save()
    }

    public func moveThread(id: String, toFolderId: String) async throws {


        // Find the thread
        var threadDescriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == id }
        )
        threadDescriptor.fetchLimit = 1
        guard let thread = try context.fetch(threadDescriptor).first else {
            throw ThreadListError.threadNotFound(id: id)
        }

        // Find the destination folder
        var folderDescriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.id == toFolderId }
        )
        folderDescriptor.fetchLimit = 1
        guard let destinationFolder = try context.fetch(folderDescriptor).first else {
            throw ThreadListError.folderNotFound(id: toFolderId)
        }

        // Update EmailFolder entries for all emails in the thread
        for email in thread.emails {
            // Remove existing EmailFolder associations
            for ef in email.emailFolders {
                context.delete(ef)
            }
            // Create new association with destination folder
            let newEF = EmailFolder(imapUID: 0)
            newEF.email = email
            newEF.folder = destinationFolder
            context.insert(newEF)
        }

        try context.save()
    }

    public func toggleReadStatus(threadId: String) async throws {

        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        descriptor.fetchLimit = 1

        guard let thread = try context.fetch(descriptor).first else {
            throw ThreadListError.threadNotFound(id: threadId)
        }

        // Flip: if unread (> 0) set to 0, else set to 1
        thread.unreadCount = thread.unreadCount > 0 ? 0 : 1
        try context.save()
    }

    public func toggleStarStatus(threadId: String) async throws {

        var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate { $0.id == threadId }
        )
        descriptor.fetchLimit = 1

        guard let thread = try context.fetch(descriptor).first else {
            throw ThreadListError.threadNotFound(id: threadId)
        }

        thread.isStarred = !thread.isStarred
        try context.save()
    }

    // MARK: - Email-Level Star (PR #8 Comment 1)

    public func toggleEmailStarStatus(emailId: String) async throws {
        let eid = emailId
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == eid }
        )
        descriptor.fetchLimit = 1

        guard let email = try context.fetch(descriptor).first else {
            throw ThreadListError.threadNotFound(id: emailId)
        }

        email.isStarred = !email.isStarred

        // Recalculate thread-level star: true if ANY email in thread is starred
        if let thread = email.thread {
            thread.isStarred = thread.emails.contains { $0.isStarred }
        }

        try context.save()
    }

    // MARK: - Batch Thread Actions (FR-TL-03)

    public func archiveThreads(ids: [String]) async throws {
        for id in ids {
            try await archiveThread(id: id)
        }
    }

    public func deleteThreads(ids: [String]) async throws {
        for id in ids {
            try await deleteThread(id: id)
        }
    }

    public func markThreadsRead(ids: [String]) async throws {

        for id in ids {
            var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let thread = try context.fetch(descriptor).first else {
                throw ThreadListError.threadNotFound(id: id)
            }
            thread.unreadCount = 0
        }
        try context.save()
    }

    public func markThreadsUnread(ids: [String]) async throws {

        for id in ids {
            var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let thread = try context.fetch(descriptor).first else {
                throw ThreadListError.threadNotFound(id: id)
            }
            thread.unreadCount = 1
        }
        try context.save()
    }

    public func starThreads(ids: [String]) async throws {

        for id in ids {
            var descriptor = FetchDescriptor<VaultMailFeature.Thread>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let thread = try context.fetch(descriptor).first else {
                throw ThreadListError.threadNotFound(id: id)
            }
            thread.isStarred = true
        }
        try context.save()
    }

    public func moveThreads(ids: [String], toFolderId: String) async throws {
        for id in ids {
            try await moveThread(id: id, toFolderId: toFolderId)
        }
    }

    // MARK: - Sync Support (FR-SYNC-01)

    public func getEmailByMessageId(_ messageId: String, accountId: String) async throws -> Email? {

        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.messageId == messageId && $0.accountId == accountId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func getFolderByImapPath(_ imapPath: String, accountId: String) async throws -> Folder? {

        var descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate { $0.imapPath == imapPath && $0.account?.id == accountId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func getEmailsByAccount(accountId: String) async throws -> [Email] {

        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        return try context.fetch(descriptor)
    }

    public func saveEmailFolder(_ emailFolder: EmailFolder) async throws {

        let efId = emailFolder.id
        var descriptor = FetchDescriptor<EmailFolder>(
            predicate: #Predicate { $0.id == efId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.imapUID = emailFolder.imapUID
            existing.email = emailFolder.email
            existing.folder = emailFolder.folder
        } else {
            context.insert(emailFolder)
        }
        // No explicit save — callers use flushChanges() for batch persistence,
        // or SwiftData auto-saves at the end of the run loop cycle.
    }

    public func saveAttachment(_ attachment: Attachment) async throws {

        let attId = attachment.id
        var descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.id == attId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.filename = attachment.filename
            existing.mimeType = attachment.mimeType
            existing.sizeBytes = attachment.sizeBytes
            existing.localPath = attachment.localPath
            existing.isDownloaded = attachment.isDownloaded
        } else {
            context.insert(attachment)
        }
        // No explicit save — callers use flushChanges() for batch persistence,
        // or SwiftData auto-saves at the end of the run loop cycle.
    }

    // MARK: - Trusted Senders (FR-ED-04)

    public func getTrustedSender(email: String) async throws -> TrustedSender? {
        let descriptor = FetchDescriptor<TrustedSender>(
            predicate: #Predicate { $0.senderEmail == email }
        )
        return try context.fetch(descriptor).first
    }

    public func saveTrustedSender(_ sender: TrustedSender) async throws {
        context.insert(sender)
        try context.save()
    }

    public func deleteTrustedSender(email: String) async throws {
        let descriptor = FetchDescriptor<TrustedSender>(
            predicate: #Predicate { $0.senderEmail == email }
        )
        for sender in try context.fetch(descriptor) {
            context.delete(sender)
        }
        try context.save()
    }

    public func getAllTrustedSenders() async throws -> [TrustedSender] {
        let descriptor = FetchDescriptor<TrustedSender>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Email Lookup (FR-COMP-01)

    public func getEmail(id: String) async throws -> Email? {
        let emailId = id
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == emailId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func getEmailsBySendState(_ state: String) async throws -> [Email] {
        let sendState = state
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.sendState == sendState }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Contact Cache (FR-COMP-04)

    public func queryContacts(accountId: String, prefix: String, limit: Int) async throws -> [ContactCacheEntry] {
        let acctId = accountId
        let descriptor = FetchDescriptor<ContactCacheEntry>(
            predicate: #Predicate { $0.accountId == acctId },
            sortBy: [SortDescriptor(\.frequency, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        let lowercased = prefix.lowercased()
        let filtered = all.filter {
            $0.emailAddress.lowercased().hasPrefix(lowercased) ||
            ($0.displayName?.lowercased().hasPrefix(lowercased) ?? false)
        }
        return Array(filtered.prefix(limit))
    }

    public func upsertContact(_ entry: ContactCacheEntry) async throws {
        let email = entry.emailAddress.lowercased()
        let acctId = entry.accountId
        let descriptor = FetchDescriptor<ContactCacheEntry>(
            predicate: #Predicate {
                $0.emailAddress == email && $0.accountId == acctId
            }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.frequency += 1
            existing.lastSeenDate = entry.lastSeenDate
            if let newName = entry.displayName, !newName.isEmpty {
                existing.displayName = newName
            }
        } else {
            // Normalize email to lowercase for consistent matching
            entry.emailAddress = entry.emailAddress.lowercased()
            context.insert(entry)
        }
        // No explicit save — callers use flushChanges() for batch persistence,
        // or SwiftData auto-saves at the end of the run loop cycle.
    }

    public func deleteContactsForAccount(accountId: String) async throws {
        let acctId = accountId
        let descriptor = FetchDescriptor<ContactCacheEntry>(
            predicate: #Predicate { $0.accountId == acctId }
        )
        let contacts = try context.fetch(descriptor)
        for contact in contacts {
            context.delete(contact)
        }
        try context.save()
    }
}
