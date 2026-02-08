import Foundation

/// Write-side use case for single and batch thread actions.
///
/// Per Foundation FR-FOUND-01, views **MUST** call domain use cases only —
/// never repositories directly. This use case delegates to
/// EmailRepositoryProtocol for thread mutations and wraps errors
/// as ThreadListError.actionFailed.
///
/// Spec ref: FR-TL-03
@MainActor
public protocol ManageThreadActionsUseCaseProtocol {
    /// Archive a single thread (move to Archive folder).
    func archiveThread(id: String) async throws
    /// Delete a single thread (move to Trash folder).
    func deleteThread(id: String) async throws
    /// Toggle read/unread status for a thread.
    func toggleReadStatus(threadId: String) async throws
    /// Toggle star status for a thread.
    func toggleStarStatus(threadId: String) async throws
    /// Move a thread to a different folder.
    func moveThread(id: String, toFolderId: String) async throws

    // MARK: - Batch Actions

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
}

/// Default implementation of ManageThreadActionsUseCaseProtocol.
///
/// Each method delegates directly to the corresponding
/// EmailRepositoryProtocol method and maps errors to ThreadListError.actionFailed.
@MainActor
public final class ManageThreadActionsUseCase: ManageThreadActionsUseCaseProtocol {

    private let repository: EmailRepositoryProtocol

    /// Creates a ManageThreadActionsUseCase.
    /// - Parameter repository: Email data access layer.
    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Single Actions

    public func archiveThread(id: String) async throws {
        do {
            try await repository.archiveThread(id: id)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func deleteThread(id: String) async throws {
        do {
            try await repository.deleteThread(id: id)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func toggleReadStatus(threadId: String) async throws {
        do {
            try await repository.toggleReadStatus(threadId: threadId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func toggleStarStatus(threadId: String) async throws {
        do {
            try await repository.toggleStarStatus(threadId: threadId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func moveThread(id: String, toFolderId: String) async throws {
        do {
            try await repository.moveThread(id: id, toFolderId: toFolderId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    // MARK: - Batch Actions

    public func archiveThreads(ids: [String]) async throws {
        do {
            try await repository.archiveThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func deleteThreads(ids: [String]) async throws {
        do {
            try await repository.deleteThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func markThreadsRead(ids: [String]) async throws {
        do {
            try await repository.markThreadsRead(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func markThreadsUnread(ids: [String]) async throws {
        do {
            try await repository.markThreadsUnread(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func starThreads(ids: [String]) async throws {
        do {
            try await repository.starThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }

    public func moveThreads(ids: [String], toFolderId: String) async throws {
        do {
            try await repository.moveThreads(ids: ids, toFolderId: toFolderId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }
    }
}
