import Testing
import Foundation
@testable import VaultMailFeature

@Suite("DetectSpamUseCase")
@MainActor
struct DetectSpamUseCaseTests {

    private func makeEmail(
        subject: String = "Normal Email",
        from: String = "friend@example.com",
        body: String = "Just a normal message.",
        html: String? = nil
    ) -> Email {
        Email(
            accountId: "acc-1",
            threadId: "thread-1",
            messageId: "msg-\(UUID().uuidString)",
            fromAddress: from,
            subject: subject,
            bodyPlain: body,
            bodyHTML: html
        )
    }

    private func makeUseCase() -> DetectSpamUseCase {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpamTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        // Inject StubAIEngine as FM engine so tests exercise the rule-based
        // path consistently, regardless of macOS 26+ Apple Intelligence availability.
        let resolver = AIEngineResolver(
            modelManager: modelManager,
            foundationModelEngine: StubAIEngine()
        )
        return DetectSpamUseCase(engineResolver: resolver)
    }

    @Test("clean email is not flagged as spam")
    func cleanEmail() async {
        let useCase = makeUseCase()
        let email = makeEmail()
        let result = await useCase.detect(email: email)
        #expect(!result)
        #expect(!email.isSpam)
    }

    @Test("obvious spam email is flagged")
    func obviousSpam() async {
        let useCase = makeUseCase()
        let email = makeEmail(
            subject: "URGENT: You are the WINNER of $1,000,000!",
            from: "lottery@free.tk",
            body: "Nigerian prince wire transfer. Verify your account at http://192.168.1.1/claim. Congratulations you have been selected!"
        )
        let result = await useCase.detect(email: email)
        #expect(result)
        #expect(email.isSpam)
    }

    @Test("markAsNotSpam clears spam flag")
    func markAsNotSpam() async {
        let useCase = makeUseCase()
        let email = makeEmail()
        email.isSpam = true

        useCase.markAsNotSpam(email: email)
        #expect(!email.isSpam)
    }

    @Test("detectBatch returns count of spam emails")
    func batchDetection() async {
        let useCase = makeUseCase()
        let emails = [
            makeEmail(subject: "Normal email", from: "friend@gmail.com", body: "Hey!"),
            makeEmail(
                subject: "URGENT WINNER PRIZE!",
                from: "spam@free.tk",
                body: "Nigerian prince wire transfer congratulations you have been selected verify your account http://192.168.1.1/malware"
            ),
            makeEmail(subject: "Meeting notes", from: "colleague@company.com", body: "Here are the notes.")
        ]

        let spamCount = await useCase.detectBatch(emails: emails)
        // At least one email should be flagged (the obvious spam one)
        #expect(spamCount >= 1)
    }

    @Test("phishing email with account verification is flagged")
    func phishingEmail() async {
        let useCase = makeUseCase()
        let email = makeEmail(
            subject: "URGENT: Security Alert - Act Now!",
            from: "security@bank-verify.xyz",
            body: "Your account has been compromised. Click here to verify your account immediately. Enter your password at http://192.168.1.1/verify"
        )
        let result = await useCase.detect(email: email)
        // Should be flagged due to suspicious TLD + phishing patterns + urgency + IP URL
        #expect(result)
    }

    @Test("isSpam defaults to false")
    func isSpamDefault() {
        let email = makeEmail()
        #expect(!email.isSpam)
    }

    // MARK: - ML + Rule Combined Scoring

    private func makeMLUseCase() -> (DetectSpamUseCase, MockAIEngine) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpamMLTest-\(UUID().uuidString)")
        let modelManager = ModelManager(modelsDirectory: tempDir)
        let mockEngine = MockAIEngine()
        let resolver = AIEngineResolver(
            modelManager: modelManager,
            foundationModelEngine: mockEngine
        )
        return (DetectSpamUseCase(engineResolver: resolver), mockEngine)
    }

    @Test("ML spam classification combined with rules flags spam email")
    func mlCombinedWithRulesFlagsSpam() async {
        let (useCase, mockEngine) = makeMLUseCase()
        await mockEngine.setAvailable(true)
        await mockEngine.setClassifyResult("spam")

        let email = makeEmail(
            subject: "URGENT: You won $1,000,000!",
            from: "winner@free.tk",
            body: "Nigerian prince wire transfer. Verify your account at http://192.168.1.1/claim."
        )
        let result = await useCase.detect(email: email)

        // ML returns spam (1.0 * 0.6 = 0.6) + rule signals → combined ≥ 0.5
        #expect(result == true)
        #expect(email.isSpam == true)
        let classifyCount = await mockEngine.getClassifyCallCount()
        #expect(classifyCount == 1)
    }

    @Test("ML legitimate classification keeps clean email clean")
    func mlLegitimateKeepsClean() async {
        let (useCase, mockEngine) = makeMLUseCase()
        await mockEngine.setAvailable(true)
        await mockEngine.setClassifyResult("legitimate")

        let email = makeEmail(
            subject: "Team meeting notes",
            from: "colleague@company.com",
            body: "Here are the notes from today's meeting."
        )
        let result = await useCase.detect(email: email)

        // ML returns legitimate (0.0 * 0.6 = 0.0) + clean rule signals → combined < 0.5
        #expect(result == false)
        #expect(email.isSpam == false)
    }

    @Test("ML unavailable falls back to rules only")
    func mlUnavailableUsesRulesOnly() async {
        let (useCase, mockEngine) = makeMLUseCase()
        await mockEngine.setAvailable(false)

        let email = makeEmail(
            subject: "Normal email",
            from: "friend@gmail.com",
            body: "Let's grab coffee tomorrow."
        )
        let result = await useCase.detect(email: email)

        #expect(result == false)
        let classifyCount = await mockEngine.getClassifyCallCount()
        #expect(classifyCount == 0)
    }
}
