import Foundation

/// Use case for classifying emails into AI categories.
///
/// Two-tier classification strategy:
/// 1. **Primary**: LLM via `AIEngineProtocol.classify()` (CoreML-backed when available)
/// 2. **Fallback**: LLM via `AIEngineProtocol.generate()` with prompt template
///
/// Stores result on `Email.aiCategory` and derives `Thread.aiCategory`
/// from the latest email per spec Section 6.
///
/// Spec ref: FR-AI-02, AC-A-04, AC-A-04b
@MainActor
public protocol CategorizeEmailUseCaseProtocol: Sendable {
    /// Categorize a single email and store the result.
    func categorize(email: Email) async -> AICategory

    /// Categorize a batch of emails. Returns count of successfully categorized emails.
    func categorizeBatch(emails: [Email]) async -> Int
}

@MainActor
public final class CategorizeEmailUseCase: CategorizeEmailUseCaseProtocol {
    private let engineResolver: AIEngineResolver

    public init(engineResolver: AIEngineResolver) {
        self.engineResolver = engineResolver
    }

    public func categorize(email: Email) async -> AICategory {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        guard available else {
            return .uncategorized
        }

        // Try classify() first (direct classification — faster if supported)
        let categories = AICategory.allCases
            .filter { $0 != .uncategorized }
            .map(\.rawValue)

        do {
            let result = try await engine.classify(
                text: buildClassificationText(for: email),
                categories: categories
            )
            let category = AICategory(rawValue: result) ?? .uncategorized
            email.aiCategory = category.rawValue
            updateThreadCategory(for: email)
            return category
        } catch {
            // classify() not supported or failed — fall through to generate()
        }

        // Fallback: use generate() with prompt template
        let prompt = PromptTemplates.categorization(
            subject: email.subject,
            sender: email.fromName ?? email.fromAddress,
            body: email.bodyPlain ?? email.snippet ?? ""
        )

        let stream = await engine.generate(prompt: prompt, maxTokens: 20)
        var response = ""
        for await token in stream {
            response += token
            // Stop early once we have enough text
            if response.count > 50 { break }
        }

        let category = PromptTemplates.parseCategorizationResponse(response)
        email.aiCategory = category.rawValue
        updateThreadCategory(for: email)
        return category
    }

    public func categorizeBatch(emails: [Email]) async -> Int {
        var successCount = 0
        for email in emails {
            guard !Task.isCancelled else { break }

            let result = await categorize(email: email)
            if result != .uncategorized {
                successCount += 1
            }

            // Yield between emails to avoid blocking
            await Task.yield()
        }
        return successCount
    }

    // MARK: - Helpers

    /// Build sanitized classification input text from email fields.
    ///
    /// All fields are sanitized via `PromptTemplates.sanitize()` to prevent
    /// prompt injection via malicious email content (P1-3).
    private func buildClassificationText(for email: Email) -> String {
        PromptTemplates.buildSanitizedClassificationText(
            subject: email.subject,
            sender: email.fromName ?? email.fromAddress,
            body: email.bodyPlain ?? email.snippet ?? ""
        )
    }

    /// Update thread category based on the latest email's category.
    ///
    /// Per spec Section 6: Thread.aiCategory is derived from the latest email.
    private func updateThreadCategory(for email: Email) {
        if let thread = email.thread {
            thread.aiCategory = email.aiCategory
        }
    }
}
