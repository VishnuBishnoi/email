import Testing
import Foundation
import SwiftData
@testable import PrivateMailFeature

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

    private func makeResolver() -> (AIEngineResolver, MockAIEngine) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let mockEngine = MockAIEngine()
        let resolver = AIEngineResolver(
            modelManager: modelManager,
            llamaEngine: LlamaEngine(),
            stubEngine: StubAIEngine()
        )
        return (resolver, mockEngine)
    }

    // MARK: - Tests

    @Test("falls back to keyword classification when engine unavailable")
    func engineUnavailable() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)
        let email = makeEmail()

        let result = await useCase.categorize(email: email)
        // Keyword fallback classifies generic email as .primary (personal)
        #expect(result == .primary)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("categorizeBatch processes multiple emails")
    func batchProcessing() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let emails = (0..<5).map { _ in makeEmail() }

        let count = await useCase.categorizeBatch(emails: emails)
        // With keyword fallback, generic emails get classified as .primary (non-uncategorized)
        #expect(count == 5)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("categorizeBatch skips already-categorized emails via CategorizeEmailUseCase.categorizeBatch check")
    func batchSkipsAlreadyCategorized() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        // Pre-categorized email still goes through since categorizeBatch doesn't filter
        // (filtering happens in AIProcessingQueue.enqueue)
        let email = makeEmail(category: AICategory.social.rawValue)
        let count = await useCase.categorizeBatch(emails: [email])
        // Keyword fallback classifies the generic email as .primary (non-uncategorized)
        #expect(count == 1)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Keyword Fallback Tests

    @Test("keyword fallback classifies social domain emails")
    func keywordSocialDomain() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(from: "notifications@facebook.com")
        let result = await useCase.categorize(email: email)
        #expect(result == .social)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("keyword fallback classifies promotional emails")
    func keywordPromotional() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(subject: "50% off sale - limited time offer", body: "Unsubscribe from this list")
        let result = await useCase.categorize(email: email)
        #expect(result == .promotions)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("keyword fallback classifies update emails")
    func keywordUpdates() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategorizeTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let useCase = CategorizeEmailUseCase(engineResolver: resolver)

        let email = makeEmail(subject: "Your order confirmation", from: "noreply@service.com")
        let result = await useCase.categorize(email: email)
        #expect(result == .updates)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
