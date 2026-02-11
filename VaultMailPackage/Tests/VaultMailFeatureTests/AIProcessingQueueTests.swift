import Testing
import Foundation
@testable import VaultMailFeature

@Suite("AIProcessingQueue")
@MainActor
struct AIProcessingQueueTests {

    private func makeEmail(
        category: String? = AICategory.uncategorized.rawValue
    ) -> Email {
        Email(
            accountId: "acc-1",
            threadId: "thread-1",
            messageId: "msg-\(UUID().uuidString)",
            fromAddress: "sender@example.com",
            subject: "Test Email",
            bodyPlain: "Test body",
            aiCategory: category
        )
    }

    private func makeQueue() -> AIProcessingQueue {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueueTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let resolver = AIEngineResolver(modelManager: modelManager)
        let categorize = CategorizeEmailUseCase(engineResolver: resolver)
        let detectSpam = DetectSpamUseCase(engineResolver: resolver)
        return AIProcessingQueue(categorize: categorize, detectSpam: detectSpam)
    }

    @Test("queue starts not processing")
    func initialState() {
        let queue = makeQueue()
        #expect(!queue.isProcessing)
        #expect(queue.processedCount == 0)
        #expect(queue.totalCount == 0)
    }

    @Test("enqueue filters out already-categorized emails")
    func filtersAlreadyCategorized() {
        let queue = makeQueue()

        let emails = [
            makeEmail(category: AICategory.primary.rawValue),
            makeEmail(category: AICategory.social.rawValue),
            makeEmail(category: AICategory.uncategorized.rawValue),
        ]

        queue.enqueue(emails: emails)
        // Only the uncategorized email should be queued
        #expect(queue.totalCount == 1)
    }

    @Test("enqueue skips empty list")
    func skipsEmptyList() {
        let queue = makeQueue()
        queue.enqueue(emails: [])
        #expect(!queue.isProcessing)
        #expect(queue.totalCount == 0)
    }

    @Test("enqueue skips when all emails already categorized")
    func skipsAllCategorized() {
        let queue = makeQueue()
        let emails = [
            makeEmail(category: AICategory.primary.rawValue),
            makeEmail(category: AICategory.social.rawValue),
        ]
        queue.enqueue(emails: emails)
        #expect(!queue.isProcessing)
    }

    @Test("cancel stops processing")
    func cancelStopsProcessing() async {
        let queue = makeQueue()
        let emails = (0..<10).map { _ in makeEmail() }
        queue.enqueue(emails: emails)

        // Cancel immediately
        queue.cancel()
        #expect(!queue.isProcessing)
    }

    @Test("enqueue with uncategorized emails starts processing")
    func enqueueStartsProcessing() {
        let queue = makeQueue()
        let emails = (0..<3).map { _ in makeEmail() }
        queue.enqueue(emails: emails)
        #expect(queue.totalCount == 3)
        // Processing starts immediately but runs async
        // Just verify state was set correctly
    }
}
