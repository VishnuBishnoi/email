import Foundation
import Testing
@testable import VaultMailFeature

@Suite("MarkReadUseCase")
@MainActor
struct MarkReadUseCaseTests {

    private static func makeSUT() -> (MarkReadUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = MarkReadUseCase(repository: repo)
        return (useCase, repo)
    }

    /// Creates a thread with the given number of unread emails.
    private static func makeThreadWithEmails(
        unreadCount: Int,
        totalCount: Int
    ) -> VaultMailFeature.Thread {
        let thread = Thread(
            accountId: "acc1",
            subject: "Test Thread",
            messageCount: totalCount,
            unreadCount: unreadCount
        )
        for i in 0..<totalCount {
            let email = Email(
                accountId: "acc1",
                threadId: thread.id,
                messageId: "msg-\(i)",
                fromAddress: "sender@test.com",
                subject: "Email \(i)",
                isRead: i >= unreadCount
            )
            email.thread = thread
            thread.emails.append(email)
        }
        return thread
    }

    @Test("marks unread emails as read")
    func marksUnreadEmailsAsRead() async throws {
        let (sut, repo) = Self.makeSUT()
        let thread = Self.makeThreadWithEmails(unreadCount: 2, totalCount: 3)
        repo.threads = [thread]

        try await sut.markAllRead(in: thread)

        for email in thread.emails {
            #expect(email.isRead == true)
        }
        // 2 unread emails saved + 1 thread save
        #expect(repo.saveEmailCallCount == 2)
    }

    @Test("updates thread unreadCount to zero")
    func updatesThreadUnreadCount() async throws {
        let (sut, repo) = Self.makeSUT()
        let thread = Self.makeThreadWithEmails(unreadCount: 2, totalCount: 2)
        repo.threads = [thread]

        try await sut.markAllRead(in: thread)

        #expect(thread.unreadCount == 0)
        #expect(repo.saveThreadCallCount == 1)
    }

    @Test("does nothing for already-read thread")
    func doesNothingForReadThread() async throws {
        let (sut, repo) = Self.makeSUT()
        let thread = Self.makeThreadWithEmails(unreadCount: 0, totalCount: 3)
        repo.threads = [thread]

        try await sut.markAllRead(in: thread)

        #expect(repo.saveEmailCallCount == 0)
        #expect(repo.saveThreadCallCount == 0)
    }

    @Test("wraps errors as markReadFailed")
    func wrapsErrorsAsMarkReadFailed() async throws {
        let (sut, repo) = Self.makeSUT()
        let thread = Self.makeThreadWithEmails(unreadCount: 1, totalCount: 1)
        repo.threads = [thread]
        repo.errorToThrow = NSError(domain: "test", code: 1)

        await #expect(throws: EmailDetailError.self) {
            try await sut.markAllRead(in: thread)
        }
    }

    @Test("marks only unread emails in mixed thread")
    func marksMixedThread() async throws {
        let (sut, repo) = Self.makeSUT()
        // 3 emails total: 1 already read, 2 unread
        let thread = Self.makeThreadWithEmails(unreadCount: 2, totalCount: 3)
        repo.threads = [thread]

        try await sut.markAllRead(in: thread)

        for email in thread.emails {
            #expect(email.isRead == true)
        }
        // Only 2 unread emails should have been saved (not the already-read one)
        #expect(repo.saveEmailCallCount == 2)
        #expect(thread.unreadCount == 0)
    }
}
