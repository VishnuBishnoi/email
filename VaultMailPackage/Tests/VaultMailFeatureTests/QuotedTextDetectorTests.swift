import Testing
@testable import VaultMailFeature

@Suite("QuotedTextDetector")
struct QuotedTextDetectorTests {

    // MARK: - HTML: Blockquote Detection

    @Test("Detects blockquote in HTML")
    func detectsBlockquote() {
        let html = """
        <p>My reply</p>
        <blockquote>Original message content</blockquote>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)
        #expect(result.processedHTML.contains("pm-quote-toggle"))
        #expect(result.processedHTML.contains("pm-quoted-text"))
        #expect(result.processedHTML.contains("display:none"))
        #expect(result.processedHTML.contains("Show quoted text"))
    }

    @Test("Handles nested blockquotes by wrapping outermost only")
    func handlesNestedBlockquotes() {
        let html = """
        <p>My reply</p>
        <blockquote>
            First reply
            <blockquote>Original message</blockquote>
        </blockquote>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)

        // Count occurrences of pm-quote-toggle - should be 1 for outermost only.
        let toggleCount = result.processedHTML.components(separatedBy: "pm-quote-toggle").count - 1
        #expect(toggleCount == 1)
    }

    // MARK: - HTML: Gmail Detection

    @Test("Detects Gmail gmail_quote div")
    func detectsGmailQuote() {
        let html = """
        <p>Thanks for the update.</p>
        <div class="gmail_quote">On Mon, Jan 1, 2024, someone wrote:<br>Previous message</div>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)
        #expect(result.processedHTML.contains("pm-quoted-text"))
        #expect(result.processedHTML.contains("Thanks for the update"))
    }

    // MARK: - HTML: Outlook Detection

    @Test("Detects Outlook appendonsend div")
    func detectsOutlookAppendOnSend() {
        let html = """
        <p>My response</p>
        <div id="appendonsend">From: sender@example.com<br>Previous content</div>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)
        #expect(result.processedHTML.contains("pm-quoted-text"))
    }

    @Test("Detects Outlook divRplyFwdMsg div")
    func detectsOutlookReplyForwardMsg() {
        let html = """
        <p>Sure, I'll handle it.</p>
        <div id="divRplyFwdMsg">-----Original Message-----<br>From: boss@company.com</div>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)
        #expect(result.processedHTML.contains("pm-quoted-text"))
    }

    // MARK: - HTML: Apple Mail Detection

    @Test("Detects Apple Mail AppleOriginalContents div")
    func detectsAppleMailOriginalContents() {
        let html = """
        <p>Got it, thanks!</p>
        <div class="AppleOriginalContents">On Jan 1, 2024, at 10:00 AM, someone wrote:<br>Original email</div>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == true)
        #expect(result.processedHTML.contains("pm-quoted-text"))
    }

    // MARK: - HTML: No Quoted Text

    @Test("Returns hasQuotedText=false for HTML with no quotes")
    func noQuotedTextInHTML() {
        let html = """
        <html>
        <body>
        <p>Just a regular email with no quoted content.</p>
        <div class="content">Some content here.</div>
        </body>
        </html>
        """
        let result = QuotedTextDetector.detectInHTML(html)
        #expect(result.hasQuotedText == false)
        #expect(!result.processedHTML.contains("pm-quote-toggle"))
        #expect(!result.processedHTML.contains("pm-quoted-text"))
    }

    // MARK: - HTML: Edge Cases

    @Test("Handles empty HTML input")
    func handlesEmptyHTMLInput() {
        let result = QuotedTextDetector.detectInHTML("")
        #expect(result.hasQuotedText == false)
        #expect(result.processedHTML == "")
    }

    // MARK: - Plain Text: Quoted Line Detection

    @Test("Detects lines starting with > in plain text")
    func detectsQuotedLinesInPlainText() {
        let text = """
        My reply here.

        > This was the original message.
        > It had multiple lines.
        """
        let ranges = QuotedTextDetector.detectInPlainText(text)
        #expect(ranges.count == 1)
        #expect(ranges[0].startOffset > 0)
        #expect(ranges[0].endOffset > ranges[0].startOffset)

        // Verify the detected range contains the quoted text.
        let startIndex = text.index(text.startIndex, offsetBy: ranges[0].startOffset)
        let endIndex = text.index(text.startIndex, offsetBy: ranges[0].endOffset)
        let quotedSection = String(text[startIndex..<endIndex])
        #expect(quotedSection.contains("> This was the original message."))
        #expect(quotedSection.contains("> It had multiple lines."))
    }

    @Test("Handles mixed content with normal and quoted text in plain text")
    func handlesMixedPlainTextContent() {
        let text = """
        First paragraph of reply.

        > Quoted line one.
        > Quoted line two.

        Second paragraph of reply.

        > Another quoted section.
        """
        let ranges = QuotedTextDetector.detectInPlainText(text)
        #expect(ranges.count == 2)

        // First quoted section.
        let start1 = text.index(text.startIndex, offsetBy: ranges[0].startOffset)
        let end1 = text.index(text.startIndex, offsetBy: ranges[0].endOffset)
        let section1 = String(text[start1..<end1])
        #expect(section1.contains("> Quoted line one."))

        // Second quoted section.
        let start2 = text.index(text.startIndex, offsetBy: ranges[1].startOffset)
        let end2 = text.index(text.startIndex, offsetBy: ranges[1].endOffset)
        let section2 = String(text[start2..<end2])
        #expect(section2.contains("> Another quoted section."))
    }

    @Test("Returns empty array for plain text with no quoted lines")
    func noQuotedLinesInPlainText() {
        let text = "Just a regular message with no quoted lines."
        let ranges = QuotedTextDetector.detectInPlainText(text)
        #expect(ranges.isEmpty)
    }

    @Test("Handles empty plain text input")
    func handlesEmptyPlainTextInput() {
        let ranges = QuotedTextDetector.detectInPlainText("")
        #expect(ranges.isEmpty)
    }

    @Test("Detects quoted lines with leading whitespace")
    func detectsQuotedLinesWithLeadingWhitespace() {
        let text = """
        Reply text.
          > Indented quoted line.
          > Another indented line.
        """
        let ranges = QuotedTextDetector.detectInPlainText(text)
        #expect(ranges.count == 1)
    }
}
