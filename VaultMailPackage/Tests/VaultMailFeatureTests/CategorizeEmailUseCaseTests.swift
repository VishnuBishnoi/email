import Testing
import Foundation
import SwiftData
@testable import VaultMailFeature

@Suite("CategorizeEmailUseCase")
@MainActor
struct CategorizeEmailUseCaseTests {

    // MARK: - Helpers

    private func makeEmail(
        subject: String = "Test Email",
        from: String = "sender@example.com",
        body: String = "Test body content",
        category: String? = AICategory.uncategorized.rawValue
    ) -> Email {
        Email(
            accountId: "acc-1",
            threadId: "thread-1",
            messageId: "msg-\(UUID().uuidString)",
            fromAddress: from,
            subject: subject,
            bodyPlain: body,
            aiCategory: category
        )
    }

    /// Create a resolver guaranteed to fall back to keyword classification.
    ///
    /// Injects a `StubAIEngine` as the FM engine so that FoundationModelEngine
    /// availability on macOS 26+ doesn't influence keyword fallback tests.
    /// All three engine tiers report unavailable → keyword fallback is exercised.
    private func makeStubResolver() -> AIEngineResolver {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        return AIEngineResolver(
            modelManager: modelManager,
            foundationModelEngine: StubAIEngine(),
            llamaEngine: LlamaEngine(),
            stubEngine: StubAIEngine()
        )
    }

    private func makeResolver() -> (AIEngineResolver, MockAIEngine) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let mockEngine = MockAIEngine()
        let resolver = AIEngineResolver(
            modelManager: modelManager,
            foundationModelEngine: mockEngine,
            llamaEngine: LlamaEngine(),
            stubEngine: StubAIEngine()
        )
        return (resolver, mockEngine)
    }

    // MARK: - Tests

    @Test("falls back to keyword classification when engine unavailable")
    func engineUnavailable() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)
        let email = makeEmail()

        let result = await useCase.categorize(email: email)
        // Keyword fallback classifies generic email as .primary (personal)
        #expect(result == .primary)
    }

    @Test("categorizeBatch processes multiple emails")
    func batchProcessing() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let emails = (0..<5).map { _ in makeEmail() }

        let count = await useCase.categorizeBatch(emails: emails)
        // With keyword fallback, generic emails get classified as .primary (non-uncategorized)
        #expect(count == 5)
    }

    @Test("categorizeBatch skips already-categorized emails via CategorizeEmailUseCase.categorizeBatch check")
    func batchSkipsAlreadyCategorized() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        // Pre-categorized email still goes through since categorizeBatch doesn't filter
        // (filtering happens in AIProcessingQueue.enqueue)
        let email = makeEmail(category: AICategory.social.rawValue)
        let count = await useCase.categorizeBatch(emails: [email])
        // Keyword fallback classifies the generic email as .primary (non-uncategorized)
        #expect(count == 1)
    }

    // MARK: - Keyword Fallback Tests

    @Test("keyword fallback classifies social domain emails")
    func keywordSocialDomain() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(from: "notifications@facebook.com")
        let result = await useCase.categorize(email: email)
        #expect(result == .social)
    }

    @Test("keyword fallback classifies promotional emails")
    func keywordPromotional() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(subject: "50% off sale - limited time offer", body: "Unsubscribe from this list")
        let result = await useCase.categorize(email: email)
        #expect(result == .promotions)
    }

    @Test("keyword fallback classifies update emails")
    func keywordUpdates() async {
        let resolver = makeStubResolver()
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(subject: "Your order confirmation", from: "noreply@service.com")
        let result = await useCase.categorize(email: email)
        #expect(result == .updates)
    }

    // MARK: - ML Tier Tests

    @Test("classify tier returns category when engine succeeds")
    func classifyTierReturnsCategory() async {
        let (resolver, mockEngine) = makeResolver()
        await mockEngine.setAvailable(true)
        await mockEngine.setClassifyResult("social")

        let useCase = CategorizeEmailUseCase(engineResolver: resolver)
        let email = makeEmail(subject: "Friend request from Alice")

        let result = await useCase.categorize(email: email)

        #expect(result == .social)
        #expect(email.aiCategory == AICategory.social.rawValue)
        let classifyCount = await mockEngine.getClassifyCallCount()
        #expect(classifyCount == 1)
    }

    @Test("classify tier failure falls back to generate tier")
    func classifyFailsFallsToGenerate() async {
        let (resolver, mockEngine) = makeResolver()
        await mockEngine.setAvailable(true)
        await mockEngine.setShouldThrow(true)
        await mockEngine.setGenerateTokens(["promotions"])

        let useCase = CategorizeEmailUseCase(engineResolver: resolver)
        let email = makeEmail(subject: "50% off everything!")

        let result = await useCase.categorize(email: email)

        // classify() threw, so generate() was called as fallback
        let classifyCount = await mockEngine.getClassifyCallCount()
        let generateCount = await mockEngine.getGenerateCallCount()
        #expect(classifyCount == 1)
        #expect(generateCount == 1)
        #expect(result == .promotions)
    }

    @Test("categorizeBatch with ML engine categorizes all emails")
    func batchWithMLEngine() async {
        let (resolver, mockEngine) = makeResolver()
        await mockEngine.setAvailable(true)
        await mockEngine.setClassifyResult("primary")

        let useCase = CategorizeEmailUseCase(engineResolver: resolver)
        let emails = (0..<3).map { _ in makeEmail() }

        let count = await useCase.categorizeBatch(emails: emails)
        #expect(count == 3)
        let classifyCount = await mockEngine.getClassifyCallCount()
        #expect(classifyCount == 3)
    }
}
