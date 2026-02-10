import Foundation

/// Real AI repository implementation that wires `AIEngineResolver` and prompt templates
/// to the `AIRepositoryProtocol`.
///
/// Replaces `StubAIRepository` when AI engines are available.
/// All inference runs on-device. No user data leaves the device (P-02).
///
/// Spec ref: Foundation spec Section 6, FR-AI-01 through FR-AI-04
@MainActor
public final class AIRepositoryImpl: AIRepositoryProtocol {

    private let engineResolver: AIEngineResolver

    public init(engineResolver: AIEngineResolver) {
        self.engineResolver = engineResolver
    }

    // MARK: - AIRepositoryProtocol

    public func categorize(email: Email) async throws -> AICategory {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        guard available else {
            return .uncategorized
        }

        // Try classify() first — sanitize input to prevent prompt injection (P1-2)
        let categories = AICategory.allCases
            .filter { $0 != .uncategorized }
            .map(\.rawValue)

        let sanitizedText = PromptTemplates.buildSanitizedClassificationText(
            subject: email.subject,
            sender: email.fromName ?? email.fromAddress,
            body: email.bodyPlain ?? email.snippet ?? ""
        )

        do {
            let result = try await engine.classify(
                text: sanitizedText,
                categories: categories
            )
            return AICategory(rawValue: result) ?? .uncategorized
        } catch {
            // Fallback to generate() with prompt template
        }

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

        return PromptTemplates.parseCategorizationResponse(response)
    }

    public func summarize(thread: Thread) async throws -> String {
        // Return cached summary if available
        if let cached = thread.aiSummary, !cached.isEmpty {
            return cached
        }

        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        guard available else {
            throw AIEngineError.engineUnavailable
        }

        // Build message tuples from thread emails
        let sortedEmails = thread.emails.sorted {
            ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast)
        }

        let messages: [(sender: String, date: String, body: String)] = sortedEmails.map { email in
            let dateStr: String
            if let date = email.dateReceived {
                dateStr = date.formatted(date: .abbreviated, time: .shortened)
            } else {
                dateStr = "Unknown date"
            }
            return (
                sender: email.fromName ?? email.fromAddress,
                date: dateStr,
                body: email.bodyPlain ?? email.snippet ?? ""
            )
        }

        let prompt = PromptTemplates.summarize(
            subject: thread.subject,
            messages: messages
        )

        let stream = await engine.generate(prompt: prompt, maxTokens: 200)
        var response = ""
        for await token in stream {
            response += token
        }

        let parsed = PromptTemplates.parseSummarizationResponse(response)

        // Cache the summary on the thread for subsequent loads
        if let parsed, !parsed.isEmpty {
            thread.aiSummary = parsed
            return parsed
        }

        return ""
    }

    /// Hard time limit for smart reply generation (spec FR-AI-03).
    /// If generation exceeds this, we parse whatever we have so far.
    private static let smartReplyTimeout: TimeInterval = 8.0

    public func smartReply(email: Email) async throws -> [String] {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        guard available else {
            return []
        }

        let prompt = PromptTemplates.smartReply(
            senderName: email.fromName ?? email.fromAddress,
            senderEmail: email.fromAddress,
            subject: email.subject,
            body: email.bodyPlain ?? email.snippet ?? ""
        )

        // Enforce 8-second hard limit per spec FR-AI-03.
        // If the model is slow, we parse whatever partial response we have.
        let deadline = Date().addingTimeInterval(Self.smartReplyTimeout)
        let stream = await engine.generate(prompt: prompt, maxTokens: 300)
        var response = ""
        for await token in stream {
            response += token
            // Check 8s budget after each token
            if Date() >= deadline { break }
        }

        let replies = PromptTemplates.parseSmartReplyResponse(response)
        return replies.isEmpty ? [] : replies
    }

    public func generateEmbedding(text: String) async throws -> Data {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()

        guard available else {
            return Data()
        }

        do {
            let floats = try await engine.embed(text: text)
            // Convert [Float] to Data
            return floats.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        } catch {
            return Data()
        }
    }
}
