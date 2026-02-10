import Testing
import Foundation
@testable import PrivateMailFeature

@Suite("PromptTemplates")
struct PromptTemplatesTests {

    // MARK: - Sanitization

    @Test("sanitize strips HTML tags")
    func sanitizeStripsHTML() {
        let input = "<p>Hello <b>World</b></p>"
        let result = PromptTemplates.sanitize(input, maxLength: 100)
        #expect(!result.contains("<"))
        #expect(!result.contains(">"))
        #expect(result.contains("Hello"))
        #expect(result.contains("World"))
    }

    @Test("sanitize strips script tags and content")
    func sanitizeStripsScripts() {
        let input = "Before<script>alert('xss')</script>After"
        let result = PromptTemplates.sanitize(input, maxLength: 100)
        #expect(!result.contains("script"))
        #expect(!result.contains("alert"))
        #expect(result.contains("Before"))
        #expect(result.contains("After"))
    }

    @Test("sanitize strips style tags and content")
    func sanitizeStripsStyles() {
        let input = "Text<style>body { color: red; }</style>More"
        let result = PromptTemplates.sanitize(input, maxLength: 100)
        #expect(!result.contains("style"))
        #expect(!result.contains("color"))
    }

    @Test("sanitize truncates long input")
    func sanitizeTruncates() {
        let input = String(repeating: "a", count: 500)
        let result = PromptTemplates.sanitize(input, maxLength: 100)
        #expect(result.count <= 102) // 100 chars + "…"
    }

    @Test("sanitize decodes HTML entities")
    func sanitizeDecodesEntities() {
        let input = "Tom &amp; Jerry &lt;3"
        let result = PromptTemplates.sanitize(input, maxLength: 100)
        #expect(result.contains("Tom & Jerry"))
    }

    @Test("sanitize handles empty string")
    func sanitizeEmpty() {
        let result = PromptTemplates.sanitize("", maxLength: 100)
        #expect(result.isEmpty)
    }

    // MARK: - Categorization

    @Test("categorization prompt contains all required elements")
    func categorizationPromptFormat() {
        let prompt = PromptTemplates.categorization(
            subject: "Summer Sale!",
            sender: "store@example.com",
            body: "Check out our amazing deals."
        )
        #expect(prompt.contains("email classifier"))
        #expect(prompt.contains("primary, social, promotions, updates, forums"))
        #expect(prompt.contains("Summer Sale!"))
        #expect(prompt.contains("store@example.com"))
        #expect(prompt.contains("Check out our amazing deals"))
        #expect(prompt.contains("Respond with only the category name"))
    }

    @Test("parseCategorizationResponse matches exact category")
    func parseCategorizationExact() {
        #expect(PromptTemplates.parseCategorizationResponse("primary") == .primary)
        #expect(PromptTemplates.parseCategorizationResponse("social") == .social)
        #expect(PromptTemplates.parseCategorizationResponse("promotions") == .promotions)
        #expect(PromptTemplates.parseCategorizationResponse("updates") == .updates)
        #expect(PromptTemplates.parseCategorizationResponse("forums") == .forums)
    }

    @Test("parseCategorizationResponse handles case-insensitive input")
    func parseCategorizationCaseInsensitive() {
        #expect(PromptTemplates.parseCategorizationResponse("Primary") == .primary)
        #expect(PromptTemplates.parseCategorizationResponse("SOCIAL") == .social)
        #expect(PromptTemplates.parseCategorizationResponse("Promotions") == .promotions)
    }

    @Test("parseCategorizationResponse handles whitespace and quotes")
    func parseCategorizationWhitespace() {
        #expect(PromptTemplates.parseCategorizationResponse("  primary  ") == .primary)
        #expect(PromptTemplates.parseCategorizationResponse("\"social\"") == .social)
        #expect(PromptTemplates.parseCategorizationResponse("updates.") == .updates)
    }

    @Test("parseCategorizationResponse returns uncategorized for unknown input")
    func parseCategorizationUnknown() {
        #expect(PromptTemplates.parseCategorizationResponse("spam") == .uncategorized)
        #expect(PromptTemplates.parseCategorizationResponse("") == .uncategorized)
        #expect(PromptTemplates.parseCategorizationResponse("I think this is primary because") == .uncategorized)
    }

    @Test("parseCategorizationResponse handles prefix match")
    func parseCategorizationPrefix() {
        #expect(PromptTemplates.parseCategorizationResponse("primary.") == .primary)
    }

    // MARK: - Smart Reply

    @Test("smart reply prompt contains all required elements")
    func smartReplyPromptFormat() {
        let prompt = PromptTemplates.smartReply(
            senderName: "Alice",
            senderEmail: "alice@example.com",
            subject: "Meeting Tomorrow",
            body: "Can we meet at 3pm?"
        )
        #expect(prompt.contains("3 short email reply suggestions"))
        #expect(prompt.contains("affirmative"))
        #expect(prompt.contains("declining"))
        #expect(prompt.contains("follow-up question"))
        #expect(prompt.contains("JSON array"))
        #expect(prompt.contains("Alice"))
        #expect(prompt.contains("alice@example.com"))
        #expect(prompt.contains("Meeting Tomorrow"))
    }

    @Test("parseSmartReplyResponse parses JSON array")
    func parseSmartReplyJSON() {
        let response = #"["Sure, 3pm works!", "Sorry, I'm busy then.", "What's the agenda?"]"#
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
        #expect(replies[0] == "Sure, 3pm works!")
        #expect(replies[1] == "Sorry, I'm busy then.")
        #expect(replies[2] == "What's the agenda?")
    }

    @Test("parseSmartReplyResponse extracts JSON from surrounding text")
    func parseSmartReplyEmbeddedJSON() {
        let response = """
        Here are the suggestions:
        ["Yes!", "No thanks.", "Can you elaborate?"]
        Hope these help!
        """
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
    }

    @Test("parseSmartReplyResponse falls back to line parsing")
    func parseSmartReplyLineFallback() {
        let response = """
        1. Sounds great, I'll be there!
        2. Unfortunately, I won't be able to make it.
        3. Could we reschedule to Thursday?
        """
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
        #expect(replies[0].contains("Sounds great"))
    }

    @Test("parseSmartReplyResponse returns empty for empty input")
    func parseSmartReplyEmpty() {
        let replies = PromptTemplates.parseSmartReplyResponse("")
        #expect(replies.isEmpty)
    }

    @Test("parseSmartReplyResponse limits to 3 replies")
    func parseSmartReplyLimitsTo3() {
        let response = #"["One", "Two", "Three", "Four", "Five"]"#
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
    }

    @Test("parseSmartReplyResponse handles markdown code-fenced JSON")
    func parseSmartReplyMarkdownFence() {
        let response = """
        ```json
        ["Thank you for the update!", "I'll review and get back to you.", "When is the deadline?"]
        ```
        """
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
        #expect(replies[0] == "Thank you for the update!")
        #expect(replies[1] == "I'll review and get back to you.")
        #expect(replies[2] == "When is the deadline?")
    }

    @Test("parseSmartReplyResponse handles markdown code fence without language tag")
    func parseSmartReplyMarkdownFenceNoLang() {
        let response = """
        ```
        ["Sounds good!", "Not right now.", "Could you clarify?"]
        ```
        """
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
        #expect(replies[0] == "Sounds good!")
    }

    @Test("parseSmartReplyResponse handles multiline JSON in code fence")
    func parseSmartReplyMultilineJSON() {
        let response = """
        ```json
        [
          "Thank you",
          "I'm not available",
          "What time works for you?"
        ]
        ```
        """
        let replies = PromptTemplates.parseSmartReplyResponse(response)
        #expect(replies.count == 3)
        #expect(replies[0] == "Thank you")
        #expect(replies[2] == "What time works for you?")
    }

    // MARK: - Summarization

    @Test("summarize prompt contains thread info and messages")
    func summarizePromptFormat() {
        let prompt = PromptTemplates.summarize(
            subject: "Q1 Budget Review",
            messages: [
                (sender: "Alice", date: "Feb 10, 2026", body: "Here's the Q1 budget draft."),
                (sender: "Bob", date: "Feb 10, 2026", body: "Looks good, approved.")
            ]
        )
        #expect(prompt.contains("Summarize this email thread"))
        #expect(prompt.contains("2-4 sentences"))
        #expect(prompt.contains("key decisions"))
        #expect(prompt.contains("Q1 Budget Review"))
        #expect(prompt.contains("Alice"))
        #expect(prompt.contains("Bob"))
        #expect(prompt.contains("2 total"))
    }

    @Test("parseSummarizationResponse trims whitespace")
    func parseSummarizationTrims() {
        let result = PromptTemplates.parseSummarizationResponse("  Summary text here.  ")
        #expect(result == "Summary text here.")
    }

    @Test("parseSummarizationResponse strips Summary prefix")
    func parseSummarizationStripsPrefix() {
        let result = PromptTemplates.parseSummarizationResponse("Summary: The team decided to proceed.")
        #expect(result == "The team decided to proceed.")
    }

    @Test("parseSummarizationResponse returns nil for empty")
    func parseSummarizationEmpty() {
        let result = PromptTemplates.parseSummarizationResponse("")
        #expect(result == nil)
    }

    @Test("parseSummarizationResponse returns nil for whitespace-only")
    func parseSummarizationWhitespaceOnly() {
        let result = PromptTemplates.parseSummarizationResponse("   \n  ")
        #expect(result == nil)
    }
}
