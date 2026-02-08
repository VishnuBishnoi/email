import Testing
@testable import PrivateMailFeature

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

        let thread = PrivateMailFeature.Thread(accountId: "a", subject: "Test")
        let result = await sut.summarize(thread: thread)

        #expect(result == "This thread discusses project deadlines")
        #expect(repo.summarizeCallCount == 1)
    }

    @Test("returns nil when AI fails")
    func returnsNilOnFailure() async {
        let (sut, repo) = Self.makeSUT()
        repo.shouldThrowError = true

        let thread = PrivateMailFeature.Thread(accountId: "a", subject: "Test")
        let result = await sut.summarize(thread: thread)

        #expect(result == nil)
        #expect(repo.summarizeCallCount == 1)
    }

    @Test("returns default summary without configuration")
    func returnsDefaultSummary() async {
        let (sut, repo) = Self.makeSUT()

        let thread = PrivateMailFeature.Thread(accountId: "a", subject: "Test")
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
}
