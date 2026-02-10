import Foundation
@testable import PrivateMailFeature

/// In-memory mock of EmailRepositoryProtocol for testing use cases.
///
/// Provides controllable behavior: arrays for data, call counters for
/// verification, and error injection for testing failure paths.
@MainActor
final class MockEmailRepository: EmailRepositoryProtocol {
    // MARK: - Storage

    var folders: [Folder] = []
    var emails: [Email] = []
    var threads: [PrivateMailFeature.Thread] = []
    var emailFolders: [EmailFolder] = []
    var attachments: [Attachment] = []
    var trustedSenders: [TrustedSender] = []

    // MARK: - Call Counters

    var getFoldersCallCount = 0
    var saveFolderCallCount = 0
    var deleteFolderCallCount = 0
    var getEmailsCallCount = 0
    var saveEmailCallCount = 0
    var deleteEmailCallCount = 0
    var getThreadsCallCount = 0
    var getThreadCallCount = 0
    var saveThreadCallCount = 0
    var getThreadsPaginatedCallCount = 0
    var getThreadsUnifiedCallCount = 0
    var getOutboxEmailsCallCount = 0
    var getUnreadCountsCallCount = 0
    var getUnreadCountsUnifiedCallCount = 0
    var archiveThreadCallCount = 0
    var deleteThreadActionCallCount = 0
    var moveThreadCallCount = 0
    var toggleReadCallCount = 0
    var toggleStarCallCount = 0
    var archiveThreadsCallCount = 0
    var deleteThreadsCallCount = 0
    var markThreadsReadCallCount = 0
    var markThreadsUnreadCallCount = 0
    var starThreadsCallCount = 0
    var moveThreadsCallCount = 0
    var getTrustedSenderCallCount = 0
    var saveTrustedSenderCallCount = 0
    var deleteTrustedSenderCallCount = 0
    var getAllTrustedSendersCallCount = 0

    // MARK: - Error Injection

    var errorToThrow: Error?

    // MARK: - Existing Protocol Methods (Folders)

    func getFolders(accountId: String) async throws -> [Folder] {
        getFoldersCallCount += 1
        if let error = errorToThrow { throw error }
        return folders.filter { $0.account?.id == accountId || true }
    }

    func saveFolder(_ folder: Folder) async throws {
        saveFolderCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
        } else {
            folders.append(folder)
        }
    }

    func deleteFolder(id: String) async throws {
        deleteFolderCallCount += 1
        if let error = errorToThrow { throw error }
        folders.removeAll { $0.id == id }
    }

    // MARK: - Existing Protocol Methods (Emails)

    func getEmails(folderId: String) async throws -> [Email] {
        getEmailsCallCount += 1
        if let error = errorToThrow { throw error }
        return emails
    }

    @discardableResult
    func saveEmail(_ email: Email) async throws -> Email {
        saveEmailCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index] = email
            return emails[index]
        } else {
            emails.append(email)
            return email
        }
    }

    func deleteEmail(id: String) async throws {
        deleteEmailCallCount += 1
        if let error = errorToThrow { throw error }
        emails.removeAll { $0.id == id }
    }

    // MARK: - Existing Protocol Methods (Threads)

    func getThreads(accountId: String) async throws -> [PrivateMailFeature.Thread] {
        getThreadsCallCount += 1
        if let error = errorToThrow { throw error }
        return threads.filter { $0.accountId == accountId }
    }

    func getThread(id: String) async throws -> PrivateMailFeature.Thread? {
        getThreadCallCount += 1
        if let error = errorToThrow { throw error }
        return threads.first { $0.id == id }
    }

    func saveThread(_ thread: PrivateMailFeature.Thread) async throws {
        saveThreadCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
    }

    // MARK: - Sync Support

    var flushChangesCallCount = 0

    func flushChanges() async throws {
        flushChangesCallCount += 1
        if let error = errorToThrow { throw error }
    }

    var getEmailByMessageIdCallCount = 0
    var getFolderByImapPathCallCount = 0
    var getEmailsByAccountCallCount = 0
    var saveEmailFolderCallCount = 0
    var saveAttachmentCallCount = 0

    func getEmailByMessageId(_ messageId: String, accountId: String) async throws -> Email? {
        getEmailByMessageIdCallCount += 1
        if let error = errorToThrow { throw error }
        return emails.first { $0.messageId == messageId && $0.accountId == accountId }
    }

    func getFolderByImapPath(_ imapPath: String, accountId: String) async throws -> Folder? {
        getFolderByImapPathCallCount += 1
        if let error = errorToThrow { throw error }
        return folders.first { $0.imapPath == imapPath }
    }

    func getEmailsByAccount(accountId: String) async throws -> [Email] {
        getEmailsByAccountCallCount += 1
        if let error = errorToThrow { throw error }
        return emails.filter { $0.accountId == accountId }
    }

    func saveEmailFolder(_ emailFolder: EmailFolder) async throws {
        saveEmailFolderCallCount += 1
        if let error = errorToThrow { throw error }
        emailFolders.append(emailFolder)
    }

    func saveAttachment(_ attachment: Attachment) async throws {
        saveAttachmentCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments[index] = attachment
        } else {
            attachments.append(attachment)
        }
    }

    // MARK: - Thread List Queries

    func getThreads(folderId: String, category: String?, cursor: Date?, limit: Int) async throws -> [PrivateMailFeature.Thread] {
        getThreadsPaginatedCallCount += 1
        if let error = errorToThrow { throw error }

        var result = threads.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }

        if let category {
            result = result.filter { $0.aiCategory == category }
        }

        if let cursor {
            result = result.filter { ($0.latestDate ?? .distantPast) < cursor }
        }

        return Array(result.prefix(limit))
    }

    func getThreadsUnified(category: String?, cursor: Date?, limit: Int) async throws -> [PrivateMailFeature.Thread] {
        getThreadsUnifiedCallCount += 1
        if let error = errorToThrow { throw error }

        var result = threads.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }

        if let category {
            result = result.filter { $0.aiCategory == category }
        }

        if let cursor {
            result = result.filter { ($0.latestDate ?? .distantPast) < cursor }
        }

        return Array(result.prefix(limit))
    }

    func getOutboxEmails(accountId: String?) async throws -> [Email] {
        getOutboxEmailsCallCount += 1
        if let error = errorToThrow { throw error }
        let outboxStates: Set<String> = [SendState.queued.rawValue, SendState.sending.rawValue, SendState.failed.rawValue]
        var result = emails.filter { outboxStates.contains($0.sendState) }
        if let accountId {
            result = result.filter { $0.accountId == accountId }
        }
        return result
    }

    func getUnreadCounts(folderId: String) async throws -> [String?: Int] {
        getUnreadCountsCallCount += 1
        if let error = errorToThrow { throw error }
        var counts: [String?: Int] = [:]
        for thread in threads where thread.unreadCount > 0 {
            let category = thread.aiCategory
            counts[category, default: 0] += thread.unreadCount
        }
        counts[nil] = threads.reduce(0) { $0 + $1.unreadCount }
        return counts
    }

    func getUnreadCountsUnified() async throws -> [String?: Int] {
        getUnreadCountsUnifiedCallCount += 1
        if let error = errorToThrow { throw error }
        return try await getUnreadCounts(folderId: "")
    }

    // MARK: - Thread Actions

    func archiveThread(id: String) async throws {
        archiveThreadCallCount += 1
        if let error = errorToThrow { throw error }
    }

    func deleteThread(id: String) async throws {
        deleteThreadActionCallCount += 1
        if let error = errorToThrow { throw error }
    }

    func moveThread(id: String, toFolderId: String) async throws {
        moveThreadCallCount += 1
        if let error = errorToThrow { throw error }
    }

    func toggleReadStatus(threadId: String) async throws {
        toggleReadCallCount += 1
        if let error = errorToThrow { throw error }
        if let thread = threads.first(where: { $0.id == threadId }) {
            thread.unreadCount = thread.unreadCount > 0 ? 0 : 1
        }
    }

    func toggleStarStatus(threadId: String) async throws {
        toggleStarCallCount += 1
        if let error = errorToThrow { throw error }
        if let thread = threads.first(where: { $0.id == threadId }) {
            thread.isStarred = !thread.isStarred
        }
    }

    var toggleEmailStarCallCount = 0

    func toggleEmailStarStatus(emailId: String) async throws {
        toggleEmailStarCallCount += 1
        if let error = errorToThrow { throw error }
    }

    // MARK: - Batch Actions

    func archiveThreads(ids: [String]) async throws {
        archiveThreadsCallCount += 1
        if let error = errorToThrow { throw error }
        for id in ids { try await archiveThread(id: id) }
    }

    func deleteThreads(ids: [String]) async throws {
        deleteThreadsCallCount += 1
        if let error = errorToThrow { throw error }
        for id in ids { try await deleteThread(id: id) }
    }

    func markThreadsRead(ids: [String]) async throws {
        markThreadsReadCallCount += 1
        if let error = errorToThrow { throw error }
        for id in ids {
            if let thread = threads.first(where: { $0.id == id }) {
                thread.unreadCount = 0
            }
        }
    }

    func markThreadsUnread(ids: [String]) async throws {
        markThreadsUnreadCallCount += 1
        if let error = errorToThrow { throw error }
        for id in ids {
            if let thread = threads.first(where: { $0.id == id }) {
                thread.unreadCount = 1
            }
        }
    }

    func starThreads(ids: [String]) async throws {
        starThreadsCallCount += 1
        if let error = errorToThrow { throw error }
        for id in ids {
            if let thread = threads.first(where: { $0.id == id }) {
                thread.isStarred = true
            }
        }
    }

    func moveThreads(ids: [String], toFolderId: String) async throws {
        moveThreadsCallCount += 1
        if let error = errorToThrow { throw error }
    }

    // MARK: - Trusted Senders

    func getTrustedSender(email: String) async throws -> TrustedSender? {
        getTrustedSenderCallCount += 1
        if let error = errorToThrow { throw error }
        return trustedSenders.first { $0.senderEmail == email }
    }

    func saveTrustedSender(_ sender: TrustedSender) async throws {
        saveTrustedSenderCallCount += 1
        if let error = errorToThrow { throw error }
        trustedSenders.append(sender)
    }

    func deleteTrustedSender(email: String) async throws {
        deleteTrustedSenderCallCount += 1
        if let error = errorToThrow { throw error }
        trustedSenders.removeAll { $0.senderEmail == email }
    }

    func getAllTrustedSenders() async throws -> [TrustedSender] {
        getAllTrustedSendersCallCount += 1
        if let error = errorToThrow { throw error }
        return trustedSenders
    }

    // MARK: - Email Lookup (FR-COMP-01)

    var getEmailCallCount = 0

    func getEmail(id: String) async throws -> Email? {
        getEmailCallCount += 1
        if let error = errorToThrow { throw error }
        return emails.first { $0.id == id }
    }

    func getEmailsBySendState(_ state: String) async throws -> [Email] {
        if let error = errorToThrow { throw error }
        return emails.filter { $0.sendState == state }
    }

    // MARK: - Contact Cache (FR-COMP-04)

    var contactEntries: [ContactCacheEntry] = []
    var queryContactsCallCount = 0
    var upsertContactCallCount = 0
    var deleteContactsForAccountCallCount = 0

    func queryContacts(accountId: String, prefix: String, limit: Int) async throws -> [ContactCacheEntry] {
        queryContactsCallCount += 1
        if let error = errorToThrow { throw error }
        let lowercased = prefix.lowercased()
        let filtered = contactEntries
            .filter { $0.accountId == accountId }
            .filter {
                $0.emailAddress.lowercased().hasPrefix(lowercased) ||
                ($0.displayName?.lowercased().hasPrefix(lowercased) ?? false)
            }
            .sorted { $0.frequency > $1.frequency }
        return Array(filtered.prefix(limit))
    }

    func upsertContact(_ entry: ContactCacheEntry) async throws {
        upsertContactCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = contactEntries.firstIndex(where: {
            $0.emailAddress.lowercased() == entry.emailAddress.lowercased() &&
            $0.accountId == entry.accountId
        }) {
            contactEntries[index].frequency += 1
            contactEntries[index].lastSeenDate = entry.lastSeenDate
            if let name = entry.displayName, !name.isEmpty {
                contactEntries[index].displayName = name
            }
        } else {
            contactEntries.append(entry)
        }
    }

    func deleteContactsForAccount(accountId: String) async throws {
        deleteContactsForAccountCallCount += 1
        if let error = errorToThrow { throw error }
        contactEntries.removeAll { $0.accountId == accountId }
    }
}
