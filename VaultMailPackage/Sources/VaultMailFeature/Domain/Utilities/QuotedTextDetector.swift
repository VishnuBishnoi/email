import Foundation

/// Detects and wraps quoted/reply text in email content.
///
/// In HTML emails, quoted text appears inside `<blockquote>` elements or
/// client-specific container divs (Gmail, Outlook, Apple Mail). This detector
/// finds those sections and wraps them with CSS class markers so the Swift
/// view layer can toggle visibility.
///
/// For plain text emails, lines starting with `>` are identified as quoted text.
public enum QuotedTextDetector {

    // MARK: - Types

    /// Result of scanning HTML for quoted text sections.
    public struct HTMLDetectionResult: Sendable, Equatable {
        /// The HTML with quoted sections wrapped in toggle markers.
        public let processedHTML: String
        /// Whether any quoted text was detected.
        public let hasQuotedText: Bool
    }

    /// A character range in plain text that contains quoted content.
    public struct QuotedRange: Sendable, Equatable {
        /// Character offset where the quoted section starts.
        public let startOffset: Int
        /// Character offset where the quoted section ends.
        public let endOffset: Int
    }

    // MARK: - HTML Quoted Text Markers

    /// CSS class applied to the toggle button div.
    public static let toggleClass = "pm-quote-toggle"
    /// CSS class applied to the wrapper around quoted content.
    public static let quotedTextClass = "pm-quoted-text"

    // MARK: - Public API

    /// Detect quoted text in HTML and wrap it with toggle markers.
    ///
    /// Supported patterns:
    /// - `<blockquote>` elements
    /// - `<div class="gmail_quote">` (Gmail)
    /// - `<div id="appendonsend">` (Outlook)
    /// - `<div id="divRplyFwdMsg">` (Outlook)
    /// - `<div class="AppleOriginalContents">` (Apple Mail)
    ///
    /// Each detected section is wrapped in a `<div class="pm-quoted-text" style="display:none;">`
    /// and preceded by a `<div class="pm-quote-toggle">` marker.
    ///
    /// - Parameter html: The raw HTML content of an email.
    /// - Returns: An ``HTMLDetectionResult`` with processed HTML and a flag indicating presence.
    public static func detectInHTML(_ html: String) -> HTMLDetectionResult {
        guard !html.isEmpty else {
            return HTMLDetectionResult(processedHTML: "", hasQuotedText: false)
        }

        var result = html
        var hasQuotedText = false

        // Process each pattern. Order matters: process specific client
        // patterns first, then generic blockquote last, to avoid
        // double-wrapping.
        let clientPatterns: [(pattern: String, options: NSRegularExpression.Options)] = [
            // Gmail
            (
                #"(<div\b[^>]*class\s*=\s*["']gmail_quote["'][^>]*>[\s\S]*?</div>)"#,
                [.caseInsensitive]
            ),
            // Outlook appendonsend
            (
                #"(<div\b[^>]*id\s*=\s*["']appendonsend["'][^>]*>[\s\S]*?</div>)"#,
                [.caseInsensitive]
            ),
            // Outlook divRplyFwdMsg
            (
                #"(<div\b[^>]*id\s*=\s*["']divRplyFwdMsg["'][^>]*>[\s\S]*?</div>)"#,
                [.caseInsensitive]
            ),
            // Apple Mail
            (
                #"(<div\b[^>]*class\s*=\s*["']AppleOriginalContents["'][^>]*>[\s\S]*?</div>)"#,
                [.caseInsensitive]
            ),
        ]

        for (pattern, options) in clientPatterns {
            let wrapped = wrapPattern(pattern, options: options, in: result)
            if wrapped.changed {
                result = wrapped.html
                hasQuotedText = true
            }
        }

        // Blockquote: handle potentially nested blockquotes.
        // Match outermost blockquote elements that haven't already been wrapped.
        let blockquoteResult = wrapBlockquotes(in: result)
        if blockquoteResult.changed {
            result = blockquoteResult.html
            hasQuotedText = true
        }

        return HTMLDetectionResult(processedHTML: result, hasQuotedText: hasQuotedText)
    }

    /// Detect quoted lines in plain text.
    ///
    /// Lines starting with `>` (optionally preceded by whitespace) are considered quoted.
    /// Consecutive quoted lines are merged into a single ``QuotedRange``.
    ///
    /// - Parameter text: The plain text email content.
    /// - Returns: An array of ``QuotedRange`` values representing quoted sections.
    public static func detectInPlainText(_ text: String) -> [QuotedRange] {
        guard !text.isEmpty else {
            return []
        }

        var ranges: [QuotedRange] = []
        var currentStart: Int?
        var currentEnd: Int?
        var offset = 0

        text.enumerateLines { line, _ in
            let lineLength = line.count
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            if trimmed.hasPrefix(">") {
                if currentStart == nil {
                    currentStart = offset
                }
                currentEnd = offset + lineLength
            } else {
                if let start = currentStart, let end = currentEnd {
                    ranges.append(QuotedRange(startOffset: start, endOffset: end))
                    currentStart = nil
                    currentEnd = nil
                }
            }

            // +1 for the newline character that enumerateLines strips.
            offset += lineLength + 1
        }

        // Flush any remaining range.
        if let start = currentStart, let end = currentEnd {
            ranges.append(QuotedRange(startOffset: start, endOffset: end))
        }

        return ranges
    }

    // MARK: - Private Helpers

    /// Wrap matches of a regex pattern with the toggle and hidden div markers.
    private static func wrapPattern(
        _ pattern: String,
        options: NSRegularExpression.Options,
        in html: String
    ) -> (html: String, changed: Bool) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return (html, false)
        }

        var result = html
        var changed = false
        let fullRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: fullRange)

        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let matched = String(result[swiftRange])

            // Skip if already wrapped.
            if matched.contains("pm-quoted-text") {
                continue
            }

            let wrapped = wrapWithToggle(matched)
            result.replaceSubrange(swiftRange, with: wrapped)
            changed = true
        }

        return (result, changed)
    }

    /// Wrap outermost `<blockquote>` elements with toggle markers.
    ///
    /// Uses a simple tag-depth approach to find outermost blockquotes,
    /// which handles nested blockquotes correctly.
    private static func wrapBlockquotes(in html: String) -> (html: String, changed: Bool) {
        // Find all <blockquote> and </blockquote> positions.
        let openPattern = #"<blockquote\b[^>]*>"#
        let closePattern = #"</blockquote\s*>"#

        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive),
              let closeRegex = try? NSRegularExpression(pattern: closePattern, options: .caseInsensitive) else {
            return (html, false)
        }

        let fullRange = NSRange(html.startIndex..., in: html)

        struct TagPosition {
            let range: Range<String.Index>
            let isOpen: Bool
        }

        var tags: [TagPosition] = []

        for match in openRegex.matches(in: html, range: fullRange) {
            if let r = Range(match.range, in: html) {
                tags.append(TagPosition(range: r, isOpen: true))
            }
        }
        for match in closeRegex.matches(in: html, range: fullRange) {
            if let r = Range(match.range, in: html) {
                tags.append(TagPosition(range: r, isOpen: false))
            }
        }

        // Sort by position in the string.
        tags.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Find outermost blockquote ranges (depth 0 -> 1 open, 1 -> 0 close).
        var outermostRanges: [Range<String.Index>] = []
        var depth = 0
        var outermostStart: String.Index?

        for tag in tags {
            if tag.isOpen {
                if depth == 0 {
                    outermostStart = tag.range.lowerBound
                }
                depth += 1
            } else {
                depth -= 1
                if depth == 0, let start = outermostStart {
                    let fullBlockquoteRange = start..<tag.range.upperBound
                    outermostRanges.append(fullBlockquoteRange)
                    outermostStart = nil
                }
            }
        }

        guard !outermostRanges.isEmpty else {
            return (html, false)
        }

        var result = html
        // Process in reverse to maintain indices.
        for range in outermostRanges.reversed() {
            let matched = String(result[range])

            // Skip if already wrapped.
            if matched.contains("pm-quoted-text") {
                continue
            }

            let wrapped = wrapWithToggle(matched)
            result.replaceSubrange(range, with: wrapped)
        }

        return (result, true)
    }

    /// Wrap content with the toggle marker div and hidden wrapper div.
    private static func wrapWithToggle(_ content: String) -> String {
        let toggleDiv = #"<div class="pm-quote-toggle">&#9656; Show quoted text</div>"#
        let openWrapper = #"<div class="pm-quoted-text" style="display:none;">"#
        let closeWrapper = "</div>"

        return "\(toggleDiv)\(openWrapper)\(content)\(closeWrapper)"
    }
}
