import Foundation

/// Use case for detecting spam and phishing emails.
///
/// Combines two signals for final decision:
/// 1. **ML signal**: Classification via `AIEngineProtocol.classify()`.
///    When a CoreML DistilBERT model is available (bundled), it provides
///    the classification. Falls back to LLM-based classify on generative engines.
/// 2. **Rule signal**: URL/header/pattern + SPF/DKIM/DMARC analysis via `RuleEngine`.
///    Parses `Email.authenticationResults` header for auth failure signals.
///
/// Design principle: Never auto-delete. Flag with visual warning only.
/// Users can override with "Not Spam" action.
///
/// Spec ref: FR-AI-06, AC-A-09
@MainActor
public protocol DetectSpamUseCaseProtocol: Sendable {
    /// Check a single email for spam/phishing and update its `isSpam` flag.
    func detect(email: Email) async -> Bool

    /// Check a batch of emails. Returns count of emails flagged as spam.
    func detectBatch(emails: [Email]) async -> Int

    /// User override: mark a flagged email as not spam.
    func markAsNotSpam(email: Email)
}

@MainActor
public final class DetectSpamUseCase: DetectSpamUseCaseProtocol {
    private let engineResolver: AIEngineResolver
    private let ruleEngine: RuleEngine

    /// Weight for ML vs rule signals in combined decision.
    private let mlWeight: Double = 0.6
    private let ruleWeight: Double = 0.4

    /// Combined score threshold for flagging as spam.
    private let spamThreshold: Double = 0.5

    public init(
        engineResolver: AIEngineResolver,
        ruleEngine: RuleEngine = RuleEngine()
    ) {
        self.engineResolver = engineResolver
        self.ruleEngine = ruleEngine
    }

    public func detect(email: Email) async -> Bool {
        // Rule-based analysis including header auth (always available, fast)
        let ruleSignal = ruleEngine.analyze(
            subject: email.subject,
            sender: email.fromAddress,
            bodyText: email.bodyPlain,
            bodyHTML: email.bodyHTML,
            authenticationResults: email.authenticationResults
        )

        // ML-based analysis (may be unavailable)
        let mlScore = await mlSpamScore(for: email)

        // Combine signals
        let combinedScore: Double
        if mlScore >= 0 {
            // Both signals available
            combinedScore = (mlScore * mlWeight) + (ruleSignal.score * ruleWeight)
        } else {
            // ML unavailable — use rules only with lower threshold
            combinedScore = ruleSignal.score
        }

        let isSpam = combinedScore >= spamThreshold
        email.isSpam = isSpam
        return isSpam
    }

    public func detectBatch(emails: [Email]) async -> Int {
        var spamCount = 0
        for email in emails {
            guard !Task.isCancelled else { break }

            let result = await detect(email: email)
            if result {
                spamCount += 1
            }

            await Task.yield()
        }
        return spamCount
    }

    public func markAsNotSpam(email: Email) {
        email.isSpam = false
    }

    // MARK: - Private

    /// Get ML-based spam classification as a binary vote.
    ///
    /// Returns 1.0 (spam), 0.0 (legitimate), or -1.0 (unavailable).
    /// Uses binary voting instead of fake probability scores (P1-7).
    private func mlSpamScore(for email: Email) async -> Double {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()
        guard available else { return -1.0 }

        do {
            let result = try await engine.classify(
                text: buildSpamText(for: email),
                categories: ["legitimate", "spam"]
            )
            return result.lowercased() == "spam" ? 1.0 : 0.0
        } catch {
            return -1.0
        }
    }

    /// Build sanitized spam detection text from email fields.
    ///
    /// All fields are sanitized via `PromptTemplates.sanitize()` to prevent
    /// prompt injection via malicious email content (P1-4).
    private func buildSpamText(for email: Email) -> String {
        PromptTemplates.buildSanitizedSpamText(
            subject: email.subject,
            sender: email.fromAddress,
            body: email.bodyPlain ?? email.snippet ?? ""
        )
    }
}
