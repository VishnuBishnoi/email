import Foundation
import Testing
@testable import VaultMailFeature

// MARK: - Summarize Thread Use Case Tests

@Suite("SummarizeThreadUseCase")
@MainActor
struct SummarizeThreadUseCaseTests {

    private static func makeSUT() -> (SummarizeThreadUseCase, MockAIRepository) {
        let repo = MockAIRepository()
        let useCase = SummarizeThreadUseCase(aiRepository: repo)
        return (useCase, repo)
    }

    @Test("returns summary when AI succeeds")
    func returnsSummary() async {
        let (sut, repo) = Self.makeSUT()
        repo.summarizeResult = "This thread discusses project deadlines"

        let thread = VaultMailFeature.Thread(accountId: "a", subject: "Test")
        let result = await sut.summarize(thread: thread)

        #expect(result == "This thread discusses project deadlines")
        #expect(repo.summarizeCallCount == 1)
    }

    @Test("returns nil when AI fails")
    func returnsNilOnFailure() async {
        let (sut, repo) = Self.makeSUT()
        repo.shouldThrowError = true

        let thread = VaultMailFeature.Thread(accountId: "a", subject: "Test")
        let result = await sut.summarize(thread: thread)

        #expect(result == nil)
        #expect(repo.summarizeCallCount == 1)
    }

    @Test("returns default summary without configuration")
    func returnsDefaultSummary() async {
        let (sut, repo) = Self.makeSUT()

        let thread = VaultMailFeature.Thread(accountId: "a", subject: "Test")
        let result = await sut.summarize(thread: thread)

        #expect(result == "Test summary")
        #expect(repo.summarizeCallCount == 1)
    }
}

// MARK: - Smart Reply Use Case Tests

@Suite("SmartReplyUseCase")
@MainActor
struct SmartReplyUseCaseTests {

    private static func makeSUT() -> (SmartReplyUseCase, MockAIRepository) {
        let repo = MockAIRepository()
        let useCase = SmartReplyUseCase(aiRepository: repo)
        return (useCase, repo)
    }

    @Test("returns suggestions when AI succeeds")
    func returnsSuggestions() async {
        let (sut, repo) = Self.makeSUT()
        repo.smartReplyResult = ["OK", "Sure"]

        let email = Email(
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            subject: "Hi"
        )
        let result = await sut.generateReplies(for: email)

        #expect(result == ["OK", "Sure"])
        #expect(repo.smartReplyCallCount == 1)
    }

    @Test("returns empty array when AI fails")
    func returnsEmptyOnFailure() async {
        let (sut, repo) = Self.makeSUT()
        repo.shouldThrowError = true

        let email = Email(
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            subject: "Hi"
        )
        let result = await sut.generateReplies(for: email)

        #expect(result.isEmpty)
        #expect(repo.smartReplyCallCount == 1)
    }

    @Test("returns default suggestions without configuration")
    func returnsDefaultSuggestions() async {
        let (sut, repo) = Self.makeSUT()

        let email = Email(
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            subject: "Hi"
        )
        let result = await sut.generateReplies(for: email)

        #expect(result == ["Thanks!", "Got it", "Will do"])
        #expect(repo.smartReplyCallCount == 1)
    }

    @Test("caches replies on Email.aiSmartReplies after first generation")
    func cachesRepliesAfterGeneration() async {
        let (sut, repo) = Self.makeSUT()
        repo.smartReplyResult = ["Great!", "No thanks", "Tell me more"]

        let email = Email(
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            subject: "Hi"
        )

        // First call — generates and caches
        let result1 = await sut.generateReplies(for: email)
        #expect(result1 == ["Great!", "No thanks", "Tell me more"])
        #expect(repo.smartReplyCallCount == 1)
        #expect(email.aiSmartReplies != nil)

        // Second call — returns from cache, does NOT call AI again
        let result2 = await sut.generateReplies(for: email)
        #expect(result2 == ["Great!", "No thanks", "Tell me more"])
        #expect(repo.smartReplyCallCount == 1) // Still 1, not 2
    }

    @Test("returns cached replies without calling AI when aiSmartReplies is set")
    func returnsCachedReplies() async {
        let (sut, repo) = Self.makeSUT()

        let email = Email(
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            subject: "Hi"
        )
        // Pre-populate cache
        email.aiSmartReplies = #"["Cached A","Cached B"]"#

        let result = await sut.generateReplies(for: email)
        #expect(result == ["Cached A", "Cached B"])
        #expect(repo.smartReplyCallCount == 0) // No AI call at all
    }

    // MARK: - ComposerEmailContext overload

    @Test("generateReplies for ComposerEmailContext returns empty array (stub)")
    func generateRepliesForComposerContext() async {
        let (sut, _) = Self.makeSUT()

        let ctx = ComposerEmailContext(
            emailId: "e1",
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            toAddresses: "[\"to@example.com\"]",
            subject: "Hi",
            dateSent: Date()
        )
        let result = await sut.generateReplies(for: ctx)

        #expect(result.isEmpty)
    }

    @Test("generateReplies for ComposerEmailContext does not call AI")
    func generateRepliesForComposerContextNoAICall() async {
        let (sut, repo) = Self.makeSUT()

        let ctx = ComposerEmailContext(
            emailId: "e1",
            accountId: "a",
            threadId: "t",
            messageId: "m",
            fromAddress: "sender@example.com",
            toAddresses: "[\"to@example.com\"]",
            subject: "Hi",
            dateSent: Date()
        )
        _ = await sut.generateReplies(for: ctx)

        #expect(repo.smartReplyCallCount == 0)
    }
}
