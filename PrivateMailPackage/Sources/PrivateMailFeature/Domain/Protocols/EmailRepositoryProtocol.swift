import Foundation

/// Repository protocol for email, thread, and folder operations.
///
/// Implementations live in the Data layer. The Domain layer depends only
/// on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Foundation spec Section 6
public protocol EmailRepositoryProtocol: Sendable {
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
}
