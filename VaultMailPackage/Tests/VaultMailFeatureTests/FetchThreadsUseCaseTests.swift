import Foundation
import Testing
@testable import VaultMailFeature

@Suite("FetchThreadsUseCase")
@MainActor
struct FetchThreadsUseCaseTests {

    // MARK: - Helpers

    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Creates a use case with a pre-configured mock repository.
    private static func makeSUT() -> (FetchThreadsUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = FetchThreadsUseCase(repository: repo)
        return (useCase, repo)
    }

    /// Creates a test thread with a deterministic latestDate offset.
    private static func makeThread(
        index: Int,
        accountId: String = "acc1",
        category: String? = nil
    ) -> VaultMailFeature.Thread {
        VaultMailFeature.Thread(
            id: "thread-\(index)",
            accountId: accountId,
            subject: "Subject \(index)",
            latestDate: baseDate.addingTimeInterval(TimeInterval(-index * 60)),
            messageCount: 1,
            unreadCount: index % 2 == 0 ? 1 : 0,
            aiCategory: category
        )
    }

    // MARK: - fetchThreads

    @Test("fetchThreads returns correct ThreadPage with threads")
    func fetchThreadsReturnsPage() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.threads = (0..<5).map { Self.makeThread(index: $0) }

        let page = try await useCase.fetchThreads(
            accountId: "acc1",
            folderId: "folder1",
            category: nil,
            cursor: nil,
            pageSize: 25
        )

        #expect(page.threads.count == 5)
        #expect(page.hasMore == false)
        #expect(page.nextCursor == nil)
        #expect(repo.getThreadsPaginatedCallCount == 1)
    }

    @Test("fetchThreads pagination: first page returns hasMore=true when more exist")
    func fetchThreadsPaginationHasMore() async throws {
        let (useCase, repo) = Self.makeSUT()
        // Create 26 threads, pageSize=25 => overfetch 26, returns 25 + hasMore
        repo.threads = (0..<26).map { Self.makeThread(index: $0) }

        let page = try await useCase.fetchThreads(
            accountId: "acc1",
            folderId: "folder1",
            category: nil,
            cursor: nil,
            pageSize: 25
        )

        #expect(page.threads.count == 25)
        #expect(page.hasMore == true)
        #expect(page.nextCursor != nil)
        // nextCursor should be the latestDate of the 25th thread (index 24)
        let expectedCursor = Self.baseDate.addingTimeInterval(TimeInterval(-24 * 60))
        #expect(page.nextCursor == expectedCursor)
    }

    @Test("fetchThreads cursor returns older threads")
    func fetchThreadsCursorReturnsOlder() async throws {
        let (useCase, repo) = Self.makeSUT()
        // Create 30 threads
        repo.threads = (0..<30).map { Self.makeThread(index: $0) }

        // Use cursor at thread index 10's latestDate to skip first 10
        let cursor = Self.baseDate.addingTimeInterval(TimeInterval(-10 * 60))
        let page = try await useCase.fetchThreads(
            accountId: "acc1",
            folderId: "folder1",
            category: nil,
            cursor: cursor,
            pageSize: 25
        )

        // Mock filters to threads with latestDate < cursor, so threads 11..29 = 19 threads
        #expect(page.threads.count == 19)
        #expect(page.hasMore == false)
    }

    @Test("fetchThreads empty result returns empty page")
    func fetchThreadsEmptyResult() async throws {
        let (useCase, _) = Self.makeSUT()
        // No threads in repo

        let page = try await useCase.fetchThreads(
            accountId: "acc1",
            folderId: "folder1",
            category: nil,
            cursor: nil,
            pageSize: 25
        )

        #expect(page.threads.isEmpty)
        #expect(page.hasMore == false)
        #expect(page.nextCursor == nil)
    }

    @Test("fetchThreads with category filter returns matching threads only")
    func fetchThreadsWithCategory() async throws {
        let (useCase, repo) = Self.makeSUT()
        // Mix of categories
        repo.threads = [
            Self.makeThread(index: 0, category: AICategory.primary.rawValue),
            Self.makeThread(index: 1, category: AICategory.social.rawValue),
            Self.makeThread(index: 2, category: AICategory.primary.rawValue),
            Self.makeThread(index: 3, category: AICategory.promotions.rawValue),
        ]

        let page = try await useCase.fetchThreads(
            accountId: "acc1",
            folderId: "folder1",
            category: AICategory.primary.rawValue,
            cursor: nil,
            pageSize: 25
        )

        #expect(page.threads.count == 2)
        for thread in page.threads {
            #expect(thread.aiCategory == AICategory.primary.rawValue)
        }
    }

    // MARK: - fetchUnifiedThreads

    @Test("fetchUnifiedThreads merges across accounts")
    func fetchUnifiedThreadsMerges() async throws {
        let (useCase, repo) = Self.makeSUT()
        // Threads from two different accounts
        repo.threads = [
            Self.makeThread(index: 0, accountId: "acc1"),
            Self.makeThread(index: 1, accountId: "acc2"),
            Self.makeThread(index: 2, accountId: "acc1"),
            Self.makeThread(index: 3, accountId: "acc2"),
        ]

        let page = try await useCase.fetchUnifiedThreads(
            category: nil,
            cursor: nil,
            pageSize: 25
        )

        #expect(page.threads.count == 4)
        #expect(page.hasMore == false)
        #expect(repo.getThreadsUnifiedCallCount == 1)
    }

    // MARK: - fetchUnreadCounts

    @Test("fetchUnreadCounts returns category counts")
    func fetchUnreadCountsReturnsCounts() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.threads = [
            Self.makeThread(index: 0, category: AICategory.primary.rawValue),
            Self.makeThread(index: 2, category: AICategory.social.rawValue),
        ]

        let counts = try await useCase.fetchUnreadCounts(accountId: "acc1", folderId: "folder1")

        #expect(repo.getUnreadCountsCallCount == 1)
        // At least the nil (total) key should exist
        #expect(counts[nil] != nil)
    }

    // MARK: - fetchUnreadCountsUnified

    @Test("fetchUnreadCountsUnified delegates correctly")
    func fetchUnreadCountsUnifiedDelegates() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.threads = [
            Self.makeThread(index: 0, category: AICategory.primary.rawValue),
        ]

        let counts = try await useCase.fetchUnreadCountsUnified()

        #expect(repo.getUnreadCountsUnifiedCallCount == 1)
        #expect(counts[nil] != nil)
    }

    // MARK: - fetchFolders

    @Test("fetchFolders returns account folders")
    func fetchFoldersReturns() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.folders = [
            Folder(id: "f1", name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue),
            Folder(id: "f2", name: "Sent", imapPath: "[Gmail]/Sent Mail", folderType: FolderType.sent.rawValue),
        ]

        let folders = try await useCase.fetchFolders(accountId: "acc1")

        #expect(folders.count == 2)
        #expect(repo.getFoldersCallCount == 1)
    }

    // MARK: - fetchOutboxEmails

    @Test("fetchOutboxEmails returns outbox emails")
    func fetchOutboxEmailsReturns() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.emails = [
            Email(
                accountId: "acc1",
                threadId: "t1",
                messageId: "msg1",
                fromAddress: "user@test.com",
                subject: "Queued email",
                sendState: SendState.queued.rawValue
            ),
            Email(
                accountId: "acc1",
                threadId: "t2",
                messageId: "msg2",
                fromAddress: "user@test.com",
                subject: "Normal email",
                sendState: SendState.none.rawValue
            ),
        ]

        let outbox = try await useCase.fetchOutboxEmails(accountId: "acc1")

        #expect(outbox.count == 1)
        #expect(outbox.first?.subject == "Queued email")
        #expect(repo.getOutboxEmailsCallCount == 1)
    }

    // MARK: - Error Propagation

    @Test("fetchThreads error propagation wraps as ThreadListError.fetchFailed")
    func fetchThreadsErrorPropagation() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "TestError", code: 42, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])

        await #expect(throws: ThreadListError.self) {
            _ = try await useCase.fetchThreads(
                accountId: "acc1",
                folderId: "folder1",
                category: nil,
                cursor: nil,
                pageSize: 25
            )
        }
    }

    @Test("fetchUnifiedThreads error wraps as fetchFailed")
    func fetchUnifiedThreadsErrorPropagation() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "TestError", code: 43, userInfo: [NSLocalizedDescriptionKey: "DB failure"])

        await #expect(throws: ThreadListError.self) {
            _ = try await useCase.fetchUnifiedThreads(
                category: nil,
                cursor: nil,
                pageSize: 25
            )
        }
    }

    @Test("fetchFolders error wraps as fetchFailed")
    func fetchFoldersErrorPropagation() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "TestError", code: 44, userInfo: [NSLocalizedDescriptionKey: "Folder read error"])

        await #expect(throws: ThreadListError.self) {
            _ = try await useCase.fetchFolders(accountId: "acc1")
        }
    }

    @Test("fetchOutboxEmails error wraps as fetchFailed")
    func fetchOutboxEmailsErrorPropagation() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "TestError", code: 45, userInfo: [NSLocalizedDescriptionKey: "Outbox read error"])

        await #expect(throws: ThreadListError.self) {
            _ = try await useCase.fetchOutboxEmails(accountId: "acc1")
        }
    }
}
