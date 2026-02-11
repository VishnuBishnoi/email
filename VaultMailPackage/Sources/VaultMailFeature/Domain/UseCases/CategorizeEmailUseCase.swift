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

        if available {
            // Tier 1: Try classify() — direct classification (faster if supported)
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

            // Tier 2: Use generate() with prompt template
            let prompt = PromptTemplates.categorization(
                subject: email.subject,
                sender: email.fromName ?? email.fromAddress,
                body: email.bodyPlain ?? email.snippet ?? ""
            )

            let stream = await engine.generate(prompt: prompt, maxTokens: 20)
            var response = ""
            for await token in stream {
                response += token
                if response.count > 50 { break }
            }

            let category = PromptTemplates.parseCategorizationResponse(response)
            email.aiCategory = category.rawValue
            updateThreadCategory(for: email)
            return category
        }

        // Tier 3: Keyword-based fallback (always available, no model required)
        // Ensures classification works even without a downloaded model per spec.
        let category = keywordClassify(email: email)
        email.aiCategory = category.rawValue
        updateThreadCategory(for: email)
        return category
    }

    // MARK: - Keyword Classification Fallback

    /// Lightweight keyword-based classifier for when no AI engine is available.
    ///
    /// Uses sender domain and subject heuristics to approximate category.
    /// Ensures classification is never fully gated on model download per spec.
    private func keywordClassify(email: Email) -> AICategory {
        let sender = email.fromAddress.lowercased()
        let subject = email.subject.lowercased()
        let body = (email.bodyPlain ?? email.snippet ?? "").lowercased()

        // Social: known social platform domains
        let socialDomains = ["facebook", "twitter", "linkedin", "instagram", "tiktok",
                             "reddit", "pinterest", "snapchat", "tumblr", "mastodon"]
        if socialDomains.contains(where: { sender.contains($0) }) {
            return .social
        }

        // Promotions: marketing/unsubscribe signals
        let promoSignals = ["unsubscribe", "sale", "discount", "offer", "promo",
                            "deal", "coupon", "% off", "limited time", "free shipping"]
        if promoSignals.contains(where: { subject.contains($0) || body.contains($0) }) {
            return .promotions
        }

        // Updates: transactional/notification patterns
        let updateSignals = ["noreply", "no-reply", "notification", "receipt", "invoice",
                             "order confirmation", "shipping", "delivery", "your account",
                             "password reset", "verification", "security alert"]
        if updateSignals.contains(where: { sender.contains($0) || subject.contains($0) }) {
            return .updates
        }

        // Default to primary (personal email)
        return .primary
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

    /// Update thread category from the most recent email's category.
    ///
    /// Per spec Section 6: Thread.aiCategory is derived from the **latest**
    /// email by `dateReceived`. This prevents processing order from determining
    /// the thread category — only recency matters.
    private func updateThreadCategory(for email: Email) {
        guard let thread = email.thread else { return }

        // Find the most recent email in the thread that has a category
        let latestCategorized = thread.emails
            .filter { $0.aiCategory != nil && $0.aiCategory != AICategory.uncategorized.rawValue }
            .max(by: { ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast) })

        if let latest = latestCategorized {
            thread.aiCategory = latest.aiCategory
        } else {
            // No categorized emails yet — use the current one
            thread.aiCategory = email.aiCategory
        }
    }
}
