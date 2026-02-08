import Foundation

/// Read-side use case for thread list data: paginated threads, unread counts, folders, outbox.
///
/// Per Foundation FR-FOUND-01, views **MUST** call domain use cases only —
/// never repositories directly. This use case wraps EmailRepositoryProtocol
/// queries with cursor-based pagination logic and error mapping.
///
/// Spec ref: FR-TL-01, FR-TL-02, FR-TL-04
@MainActor
public protocol FetchThreadsUseCaseProtocol {
    /// Fetch a page of threads for a specific folder, optionally filtered by AI category.
    /// Uses cursor-based pagination keyed on `latestDate`.
    func fetchThreads(accountId: String, folderId: String, category: String?, cursor: Date?, pageSize: Int) async throws -> ThreadPage

    /// Fetch a page of threads across all accounts (unified inbox).
    func fetchUnifiedThreads(category: String?, cursor: Date?, pageSize: Int) async throws -> ThreadPage

    /// Fetch unread counts per AI category for a specific folder.
    /// Returns dictionary keyed by AICategory raw value (nil key = total/all).
    func fetchUnreadCounts(accountId: String, folderId: String) async throws -> [String?: Int]

    /// Fetch unified unread counts across all accounts.
    func fetchUnreadCountsUnified() async throws -> [String?: Int]

    /// Fetch all folders for an account.
    func fetchFolders(accountId: String) async throws -> [Folder]

    /// Fetch outbox emails (queued, sending, or failed).
    /// Pass nil accountId for all accounts.
    func fetchOutboxEmails(accountId: String?) async throws -> [Email]
}

/// Default implementation of FetchThreadsUseCaseProtocol.
///
/// Delegates to EmailRepositoryProtocol for data access and applies
/// cursor-based pagination (fetch limit+1, detect hasMore, compute nextCursor).
@MainActor
public final class FetchThreadsUseCase: FetchThreadsUseCaseProtocol {

    private let repository: EmailRepositoryProtocol

    /// Creates a FetchThreadsUseCase.
    /// - Parameter repository: Email data access layer.
    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - FetchThreadsUseCaseProtocol

    public func fetchThreads(accountId: String, folderId: String, category: String?, cursor: Date?, pageSize: Int) async throws -> ThreadPage {
        do {
            let results = try await repository.getThreads(
                folderId: folderId,
                category: category,
                cursor: cursor,
                limit: pageSize + 1
            )
            return buildPage(from: results, pageSize: pageSize)
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    public func fetchUnifiedThreads(category: String?, cursor: Date?, pageSize: Int) async throws -> ThreadPage {
        do {
            let results = try await repository.getThreadsUnified(
                category: category,
                cursor: cursor,
                limit: pageSize + 1
            )
            return buildPage(from: results, pageSize: pageSize)
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    public func fetchUnreadCounts(accountId: String, folderId: String) async throws -> [String?: Int] {
        do {
            return try await repository.getUnreadCounts(folderId: folderId)
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    public func fetchUnreadCountsUnified() async throws -> [String?: Int] {
        do {
            return try await repository.getUnreadCountsUnified()
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    public func fetchFolders(accountId: String) async throws -> [Folder] {
        do {
            return try await repository.getFolders(accountId: accountId)
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    public func fetchOutboxEmails(accountId: String?) async throws -> [Email] {
        do {
            return try await repository.getOutboxEmails(accountId: accountId)
        } catch {
            throw ThreadListError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Build a ThreadPage from raw results using the overfetch-by-one pattern.
    ///
    /// If `results.count > pageSize`, there are more pages:
    /// - Drop the extra item, set `hasMore = true`
    /// - `nextCursor` = `latestDate` of the last included thread
    private func buildPage(from results: [Thread], pageSize: Int) -> ThreadPage {
        if results.isEmpty {
            return .empty
        }

        if results.count > pageSize {
            let pageThreads = Array(results.prefix(pageSize))
            let nextCursor = pageThreads.last?.latestDate
            return ThreadPage(threads: pageThreads, nextCursor: nextCursor, hasMore: true)
        } else {
            return ThreadPage(threads: results, nextCursor: nil, hasMore: false)
        }
    }
}
