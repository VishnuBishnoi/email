import Foundation
import Testing
@testable import VaultMailFeature

@Suite("FetchEmailDetailUseCase")
@MainActor
struct FetchEmailDetailUseCaseTests {

    private static func makeSUT() -> (FetchEmailDetailUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = FetchEmailDetailUseCase(repository: repo)
        return (useCase, repo)
    }

    @Test("returns thread when found")
    func returnsThread() async throws {
        let (sut, repo) = Self.makeSUT()
        let thread = Thread(accountId: "acc1", subject: "Test Thread")
        repo.threads = [thread]

        let result = try await sut.fetchThread(threadId: thread.id)

        #expect(result.id == thread.id)
        #expect(result.subject == "Test Thread")
        #expect(repo.getThreadCallCount == 1)
    }

    @Test("throws threadNotFound when thread doesn't exist")
    func throwsNotFound() async throws {
        let (sut, _) = Self.makeSUT()

        do {
            _ = try await sut.fetchThread(threadId: "nonexistent")
            Issue.record("Expected EmailDetailError.threadNotFound to be thrown")
        } catch let error as EmailDetailError {
            #expect(error == .threadNotFound(id: "nonexistent"))
        }
    }

    @Test("threadNotFound error contains correct ID")
    func threadNotFoundContainsId() async throws {
        let (sut, _) = Self.makeSUT()

        do {
            _ = try await sut.fetchThread(threadId: "missing-123")
            Issue.record("Expected EmailDetailError.threadNotFound to be thrown")
        } catch let error as EmailDetailError {
            #expect(error == .threadNotFound(id: "missing-123"))
        }
    }

    @Test("wraps repository errors as loadFailed")
    func wrapsErrors() async throws {
        let (sut, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        do {
            _ = try await sut.fetchThread(threadId: "any")
            Issue.record("Expected EmailDetailError.loadFailed to be thrown")
        } catch is EmailDetailError {
            // Expected error type
        }
    }

    // MARK: - Trusted Senders

    @Test("getAllTrustedSenderEmails returns set of emails")
    func getAllTrustedSenderEmails() async throws {
        let (sut, repo) = Self.makeSUT()
        repo.trustedSenders = [
            TrustedSender(senderEmail: "alice@example.com"),
            TrustedSender(senderEmail: "bob@example.com")
        ]

        let result = try await sut.getAllTrustedSenderEmails()

        #expect(result.count == 2)
        #expect(result.contains("alice@example.com"))
        #expect(result.contains("bob@example.com"))
        #expect(repo.getAllTrustedSendersCallCount == 1)
    }

    @Test("getAllTrustedSenderEmails returns empty set when none exist")
    func getAllTrustedSenderEmailsEmpty() async throws {
        let (sut, _) = Self.makeSUT()

        let result = try await sut.getAllTrustedSenderEmails()

        #expect(result.isEmpty)
    }

    @Test("saveTrustedSender delegates to repository")
    func saveTrustedSenderDelegates() async throws {
        let (sut, repo) = Self.makeSUT()

        try await sut.saveTrustedSender(email: "trusted@example.com")

        #expect(repo.saveTrustedSenderCallCount == 1)
        #expect(repo.trustedSenders.first?.senderEmail == "trusted@example.com")
    }

    @Test("saveTrustedSender propagates repository errors")
    func saveTrustedSenderError() async {
        let (sut, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        do {
            try await sut.saveTrustedSender(email: "any@test.com")
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }
}
