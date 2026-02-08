import Foundation
@testable import PrivateMailFeature

/// In-memory mock of EmailRepositoryProtocol for testing use cases.
///
/// Provides controllable behavior: arrays for data, call counters for
/// verification, and error injection for testing failure paths.
final class MockEmailRepository: EmailRepositoryProtocol, @unchecked Sendable {
    // MARK: - Storage

    var folders: [Folder] = []
    var emails: [Email] = []
    var threads: [PrivateMailFeature.Thread] = []
    var emailFolders: [EmailFolder] = []

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

    func saveEmail(_ email: Email) async throws {
        saveEmailCallCount += 1
        if let error = errorToThrow { throw error }
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index] = email
        } else {
            emails.append(email)
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
}
