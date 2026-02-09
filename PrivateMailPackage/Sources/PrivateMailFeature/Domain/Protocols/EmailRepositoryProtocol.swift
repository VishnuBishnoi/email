import Foundation

/// Repository protocol for email, thread, and folder operations.
///
/// Isolated to `@MainActor` because SwiftData `@Model` types are not
/// `Sendable` and must be accessed on the main actor.
///
/// Implementations live in the Data layer. The Domain layer depends only
/// on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Foundation spec Section 6
@MainActor
public protocol EmailRepositoryProtocol {
    // MARK: - Folders

    /// Fetch all folders for an account.
    func getFolders(accountId: String) async throws -> [Folder]
    /// Save or update a folder.
    func saveFolder(_ folder: Folder) async throws
    /// Delete a folder and handle orphaned emails per FR-FOUND-03.
    func deleteFolder(id: String) async throws

    // MARK: - Emails

    /// Fetch emails for a given folder.
    func getEmails(folderId: String) async throws -> [Email]
    /// Save or update an email.
    func saveEmail(_ email: Email) async throws
    /// Delete an email and cascade delete EmailFolders + Attachments.
    func deleteEmail(id: String) async throws

    // MARK: - Threads

    /// Fetch all threads for an account.
    func getThreads(accountId: String) async throws -> [Thread]
    /// Fetch a single thread by ID.
    func getThread(id: String) async throws -> Thread?
    /// Save or update a thread.
    func saveThread(_ thread: Thread) async throws

    // MARK: - Sync Support (FR-SYNC-01)

    /// Find an email by its RFC 2822 Message-ID within an account.
    /// Used by the sync engine for thread resolution and deduplication.
    func getEmailByMessageId(_ messageId: String, accountId: String) async throws -> Email?

    /// Find a folder by its IMAP path within an account.
    /// Used by the sync engine for folder deduplication.
    func getFolderByImapPath(_ imapPath: String, accountId: String) async throws -> Folder?

    /// Get all emails for an account (for bulk thread resolution during sync).
    func getEmailsByAccount(accountId: String) async throws -> [Email]

    /// Save an EmailFolder join entry (email ↔ folder with IMAP UID).
    func saveEmailFolder(_ emailFolder: EmailFolder) async throws

    /// Save an Attachment.
    func saveAttachment(_ attachment: Attachment) async throws

    // MARK: - Thread List Queries (FR-TL-01, FR-TL-02)

    /// Fetch paginated threads for a specific folder, optionally filtered by AI category.
    /// Uses cursor-based pagination with latestDate.
    /// - Parameters:
    ///   - folderId: The folder to query threads from (resolved via Folder->EmailFolder->Email->Thread)
    ///   - category: Optional AI category filter (nil = all categories)
    ///   - cursor: Pagination cursor (latestDate of last thread from previous page, nil for first page)
    ///   - limit: Maximum threads to return per page
    /// - Returns: Array of threads sorted by latestDate DESC
    func getThreads(folderId: String, category: String?, cursor: Date?, limit: Int) async throws -> [Thread]

    /// Fetch paginated threads across all accounts (unified inbox).
    /// - Parameters:
    ///   - category: Optional AI category filter
    ///   - cursor: Pagination cursor (latestDate)
    ///   - limit: Maximum threads per page
    /// - Returns: Array of threads sorted by latestDate DESC
    func getThreadsUnified(category: String?, cursor: Date?, limit: Int) async throws -> [Thread]

    /// Fetch outbox emails (queued, sending, or failed) for an account.
    /// Spec ref: FR-TL-04 (Outbox is virtual, not a FolderType)
    func getOutboxEmails(accountId: String?) async throws -> [Email]

    /// Fetch unread counts per AI category for a specific folder.
    /// Returns dictionary keyed by AICategory raw value (nil key = total/all).
    func getUnreadCounts(folderId: String) async throws -> [String?: Int]

    /// Fetch unified unread counts across all accounts.
    func getUnreadCountsUnified() async throws -> [String?: Int]

    // MARK: - Thread Actions (FR-TL-03)

    /// Archive a thread (move to Archive folder).
    func archiveThread(id: String) async throws

    /// Delete a thread (move to Trash folder).
    func deleteThread(id: String) async throws

    /// Move a thread to a different folder.
    func moveThread(id: String, toFolderId: String) async throws

    /// Toggle read/unread status for a thread.
    func toggleReadStatus(threadId: String) async throws

    /// Toggle star status for a thread.
    func toggleStarStatus(threadId: String) async throws

    // MARK: - Batch Thread Actions (FR-TL-03)

    /// Archive multiple threads.
    func archiveThreads(ids: [String]) async throws
    /// Delete multiple threads.
    func deleteThreads(ids: [String]) async throws
    /// Mark multiple threads as read.
    func markThreadsRead(ids: [String]) async throws
    /// Mark multiple threads as unread.
    func markThreadsUnread(ids: [String]) async throws
    /// Star multiple threads.
    func starThreads(ids: [String]) async throws
    /// Move multiple threads to a folder.
    func moveThreads(ids: [String], toFolderId: String) async throws

    // MARK: - Email-Level Actions (PR #8 Comment 1)

    /// Toggle star status for a single email and recalculate thread-level star.
    func toggleEmailStarStatus(emailId: String) async throws

    // MARK: - Trusted Senders (FR-ED-04)

    /// Check if a sender is trusted (always load remote images).
    func getTrustedSender(email: String) async throws -> TrustedSender?
    /// Save a trusted sender preference.
    func saveTrustedSender(_ sender: TrustedSender) async throws
    /// Delete a trusted sender preference.
    func deleteTrustedSender(email: String) async throws
    /// Get all trusted senders (for Settings management).
    func getAllTrustedSenders() async throws -> [TrustedSender]

    // MARK: - Email Lookup (FR-COMP-01)

    /// Fetch a single email by ID.
    func getEmail(id: String) async throws -> Email?

    /// Fetch emails matching a given send state.
    func getEmailsBySendState(_ state: String) async throws -> [Email]

    // MARK: - Contact Cache (FR-COMP-04)

    /// Query cached contacts matching a prefix, sorted by frequency.
    func queryContacts(accountId: String, prefix: String, limit: Int) async throws -> [ContactCacheEntry]
    /// Upsert a contact cache entry (increment frequency if exists).
    func upsertContact(_ entry: ContactCacheEntry) async throws
    /// Delete all contact cache entries for an account (cascade on account removal).
    func deleteContactsForAccount(accountId: String) async throws
}
