import Foundation
import Testing
@testable import VaultMailFeature

@Suite("ManageThreadActionsUseCase")
@MainActor
struct ManageThreadActionsUseCaseTests {

    // MARK: - Helpers

    /// No-op connection provider for tests that only verify local delegation.
    /// IMAP sync is best-effort and won't affect test assertions.
    private final class StubConnectionProvider: ConnectionProviding, @unchecked Sendable {
        func checkoutConnection(
            accountId: String,
            host: String,
            port: Int,
            email: String,
            accessToken: String
        ) async throws -> any IMAPClientProtocol {
            MockIMAPClient()
        }

        func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {}
    }

    private static func makeSUT() -> (ManageThreadActionsUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let accountRepo = MockAccountRepository()
        let keychainManager = MockKeychainManager()
        let connectionProvider = StubConnectionProvider()
        let useCase = ManageThreadActionsUseCase(
            repository: repo,
            connectionProvider: connectionProvider,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )
        return (useCase, repo)
    }

    // MARK: - Single Actions

    @Test("archiveThread delegates to repository")
    func archiveThreadDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.archiveThread(id: "thread-1")

        #expect(repo.archiveThreadCallCount == 1)
    }

    @Test("deleteThread delegates to repository")
    func deleteThreadDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.deleteThread(id: "thread-1")

        #expect(repo.deleteThreadActionCallCount == 1)
    }

    @Test("toggleReadStatus delegates to repository")
    func toggleReadStatusDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        let thread = VaultMailFeature.Thread(id: "thread-1", accountId: "acc1", subject: "Test", unreadCount: 1)
        repo.threads.append(thread)

        try await useCase.toggleReadStatus(threadId: "thread-1")

        #expect(repo.toggleReadCallCount == 1)
        #expect(thread.unreadCount == 0)
    }

    @Test("toggleStarStatus delegates to repository")
    func toggleStarStatusDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        let thread = VaultMailFeature.Thread(id: "thread-1", accountId: "acc1", subject: "Test", isStarred: false)
        repo.threads.append(thread)

        try await useCase.toggleStarStatus(threadId: "thread-1")

        #expect(repo.toggleStarCallCount == 1)
        #expect(thread.isStarred == true)
    }

    @Test("moveThread delegates to repository")
    func moveThreadDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.moveThread(id: "thread-1", toFolderId: "folder-archive")

        #expect(repo.moveThreadCallCount == 1)
    }

    // MARK: - Batch Actions

    @Test("archiveThreads batch delegates to repository")
    func archiveThreadsBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.archiveThreads(ids: ["t1", "t2", "t3"])

        #expect(repo.archiveThreadsCallCount == 1)
    }

    @Test("deleteThreads batch delegates to repository")
    func deleteThreadsBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.deleteThreads(ids: ["t1", "t2"])

        #expect(repo.deleteThreadsCallCount == 1)
    }

    @Test("markThreadsRead batch delegates to repository")
    func markThreadsReadBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        let t1 = VaultMailFeature.Thread(id: "t1", accountId: "acc1", subject: "A", unreadCount: 1)
        let t2 = VaultMailFeature.Thread(id: "t2", accountId: "acc1", subject: "B", unreadCount: 1)
        repo.threads = [t1, t2]

        try await useCase.markThreadsRead(ids: ["t1", "t2"])

        #expect(repo.markThreadsReadCallCount == 1)
        #expect(t1.unreadCount == 0)
        #expect(t2.unreadCount == 0)
    }

    @Test("markThreadsUnread batch delegates to repository")
    func markThreadsUnreadBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        let t1 = VaultMailFeature.Thread(id: "t1", accountId: "acc1", subject: "A", unreadCount: 0)
        let t2 = VaultMailFeature.Thread(id: "t2", accountId: "acc1", subject: "B", unreadCount: 0)
        repo.threads = [t1, t2]

        try await useCase.markThreadsUnread(ids: ["t1", "t2"])

        #expect(repo.markThreadsUnreadCallCount == 1)
        #expect(t1.unreadCount == 1)
        #expect(t2.unreadCount == 1)
    }

    @Test("starThreads batch delegates to repository")
    func starThreadsBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        let t1 = VaultMailFeature.Thread(id: "t1", accountId: "acc1", subject: "A", isStarred: false)
        let t2 = VaultMailFeature.Thread(id: "t2", accountId: "acc1", subject: "B", isStarred: false)
        repo.threads = [t1, t2]

        try await useCase.starThreads(ids: ["t1", "t2"])

        #expect(repo.starThreadsCallCount == 1)
        #expect(t1.isStarred == true)
        #expect(t2.isStarred == true)
    }

    @Test("moveThreads batch delegates to repository")
    func moveThreadsBatchDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.moveThreads(ids: ["t1", "t2"], toFolderId: "folder-trash")

        #expect(repo.moveThreadsCallCount == 1)
    }

    // MARK: - Batch Edge Cases

    @Test("moveThreads batch with multiple ids delegates to repository")
    func moveThreadsBatchMultipleIdsDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.moveThreads(ids: ["t1", "t2"], toFolderId: "folder-archive")

        #expect(repo.moveThreadsCallCount == 1)
    }

    // MARK: - toggleEmailStarStatus

    @Test("toggleEmailStarStatus delegates to repository")
    func toggleEmailStarStatusDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()

        try await useCase.toggleEmailStarStatus(emailId: "email-1")

        #expect(repo.toggleEmailStarCallCount == 1)
    }

    @Test("toggleEmailStarStatus wraps errors as ThreadListError.actionFailed")
    func toggleEmailStarStatusError() async {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        await #expect(throws: ThreadListError.self) {
            try await useCase.toggleEmailStarStatus(emailId: "email-1")
        }
    }

    // MARK: - Error Propagation

    @Test("Error propagation wraps as ThreadListError.actionFailed")
    func errorPropagationWrapsAsActionFailed() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "TestError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Repository failure"])

        await #expect(throws: ThreadListError.self) {
            try await useCase.archiveThread(id: "thread-1")
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.deleteThread(id: "thread-1")
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.toggleReadStatus(threadId: "thread-1")
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.toggleStarStatus(threadId: "thread-1")
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.moveThread(id: "thread-1", toFolderId: "f1")
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.archiveThreads(ids: ["t1"])
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.deleteThreads(ids: ["t1"])
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.markThreadsRead(ids: ["t1"])
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.markThreadsUnread(ids: ["t1"])
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.starThreads(ids: ["t1"])
        }

        await #expect(throws: ThreadListError.self) {
            try await useCase.moveThreads(ids: ["t1"], toFolderId: "f1")
        }
    }
}
