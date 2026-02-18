import Foundation

/// LRU cache for expensive HTML base sanitization results (phases 0–6c).
///
/// Avoids re-running 20+ regex passes every time the user expands,
/// collapses, or toggles quoted text for the same email.
///
/// Thread safety: Uses `nonisolated(unsafe)` since all callers are
/// on `@MainActor` (SwiftUI views). The cache is process-scoped.
///
/// - Capacity: 32 entries (one per recently-viewed email)
/// - Eviction: LRU via insertion order
final class SanitizationCache: @unchecked Sendable {
    static let shared = SanitizationCache()

    private let lock = NSLock()
    private var storage: [Int: String] = [:]
    private var insertionOrder: [Int] = []
    private let maxSize = 32

    private init() {}

    func get(_ key: Int) -> String? {
        lock.withLock { storage[key] }
    }

    func store(_ html: String, forKey key: Int) {
        lock.withLock {
            if storage[key] == nil {
                insertionOrder.append(key)
            }
            storage[key] = html

            while insertionOrder.count > maxSize {
                let evictedKey = insertionOrder.removeFirst()
                storage.removeValue(forKey: evictedKey)
            }
        }
    }

    func clear() {
        lock.withLock {
            storage.removeAll()
            insertionOrder.removeAll()
        }
    }
}

/// Best-effort HTML sanitizer for untrusted email content.
///
/// Strips dangerous tags, event handlers, and script URIs while
/// preserving safe structural and formatting HTML.
///
/// Spec ref: Email Detail FR-ED-04
public enum HTMLSanitizer {

    // MARK: - Result Type

    /// The outcome of a sanitization pass.
    public struct SanitizationResult: Sendable, Equatable {
        /// Sanitized HTML string.
        public let html: String
        /// `true` when at least one remote image was blocked.
        public let hasBlockedRemoteContent: Bool
        /// Number of remote `<img>` sources that were replaced.
        public let remoteImageCount: Int
    }

    // MARK: - Public API

    /// Sanitize untrusted HTML email content.
    ///
    /// - Parameters:
    ///   - html: Raw HTML string from an email body.
    ///   - loadRemoteImages: When `false` (default), remote `<img>` sources
    ///     are replaced with a placeholder comment and counted.
    /// - Returns: A ``SanitizationResult`` with cleaned HTML and metadata.
    public static func sanitize(
        _ html: String,
        loadRemoteImages: Bool = false
    ) -> SanitizationResult {
        guard !html.isEmpty else {
            return SanitizationResult(
                html: "",
                hasBlockedRemoteContent: false,
                remoteImageCount: 0
            )
        }

        // Check MainActor-isolated cache for the expensive base sanitization
        // (phases 0–6c). Phase 7 (remote images) is fast and depends on user
        // preference, so we always apply it on top of the cached base.
        let cacheKey = html.hashValue
        let baseSanitized: String

        if let cached = SanitizationCache.shared.get(cacheKey) {
            baseSanitized = cached
        } else {
            baseSanitized = runBaseSanitization(html)
            SanitizationCache.shared.store(baseSanitized, forKey: cacheKey)
        }

        // --- Phase 7: Handle remote images (fast, preference-dependent) ---
        var result = baseSanitized
        var blockedCount = 0
        if !loadRemoteImages {
            (result, blockedCount) = blockRemoteImages(result)
        }

        return SanitizationResult(
            html: result,
            hasBlockedRemoteContent: blockedCount > 0,
            remoteImageCount: blockedCount
        )
    }

    /// Run the expensive multi-phase sanitization (phases 0–6c).
    ///
    /// This is the hot path that benefits from caching.
    private static func runBaseSanitization(_ html: String) -> String {
        var result = html

        // --- Phase 0a: Strip leaked IMAP protocol framing ---
        result = stripIMAPFraming(result)

        // --- Phase 0b: Strip raw MIME multipart framing ---
        result = MIMEDecoder.stripMIMEFramingForHTML(result)

        // --- Phase 1: Strip tags WITH their content ---
        result = stripTagsWithContent(result, tags: ["script", "noscript"])
        result = sanitizeStyleBlocks(result)
        result = stripTagsWithContent(result, tags: ["object", "embed", "applet"])
        result = stripTagsWithContent(result, tags: ["svg", "math", "template"])

        // --- Phase 2: Strip specific tags keeping text content ---
        result = stripTagsKeepingContent(result, tags: ["iframe", "frame", "frameset"])
        result = stripTagsKeepingContent(result, tags: ["form", "input", "button", "select", "textarea"])

        // --- Phase 3: Strip specific singleton/self-closing tags ---
        result = stripMetaRefresh(result)
        result = stripExternalStylesheetLinks(result)

        // --- Phase 4: Remove @import rules (safety net) ---
        result = stripCSSImportRules(result)

        // --- Phase 5: Clean attributes ---
        result = stripEventHandlerAttributes(result)
        result = stripSourceSetAttributes(result)
        result = stripStyleAttributesWithPotentialRemoteLoads(result)

        // --- Phase 5b: Neutralize fixed-width attributes and inline styles ---
        result = neutralizeFixedWidthAttributes(result)
        result = neutralizeInlineStyleWidths(result)

        // --- Phase 6: Neutralize dangerous URI schemes ---
        result = neutralizeJavaScriptURIs(result)
        result = neutralizeDataURIsExceptImages(result)

        // --- Phase 6b: Replace cid: inline images with placeholder (E-07) ---
        result = replaceCIDImages(result)

        // --- Phase 6c: Enforce URI scheme allow-list (PR #8 Comment 5) ---
        result = enforceURISchemeAllowList(result)

        return result
    }

    /// Wrap HTML in a full document structure with Dynamic Type CSS.
    ///
    /// - Parameters:
    ///   - html: HTML content (already sanitized or raw).
    ///   - fontSizePoints: Base font size in points for the CSS body rule.
    /// - Returns: Complete HTML document string.
    public static func injectDynamicTypeCSS(
        _ html: String,
        fontSizePoints: CGFloat,
        allowRemoteImages: Bool = false
    ) -> String {
        let sizeString = String(format: "%.0f", fontSizePoints)
        let imgSourcePolicy = allowRemoteImages ? "http: https: data:" : "data:"

        // Strip any existing <html>, <head>, <body> wrappers from the email
        // to avoid nested document structures that confuse rendering.
        let bodyContent = extractBodyContent(html)

        return """
        <!DOCTYPE html>\
        <html>\
        <head>\
        <meta charset="utf-8">\
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">\
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src \(imgSourcePolicy);">\
        <style>\
        *{box-sizing:border-box;max-width:100vw!important;}\
        html,body{\
        margin:0;padding:0;\
        width:100%!important;\
        max-width:100%!important;\
        min-width:0!important;\
        -webkit-text-size-adjust:none;\
        overflow-x:hidden;\
        }\
        body{\
        font-size:\(sizeString)pt;\
        font-family:-apple-system,system-ui,sans-serif;\
        line-height:1.5;\
        color:#1a1a1a;\
        word-wrap:break-word;\
        overflow-wrap:break-word;\
        padding:0 2px;\
        }\
        img{max-width:100%!important;height:auto!important;}\
        table,tbody,thead,tfoot,tr{max-width:100%!important;width:100%!important;min-width:0!important;}\
        table{border-collapse:collapse;}\
        td,th{word-break:break-word;overflow-wrap:break-word;max-width:100vw!important;min-width:0!important;}\
        div,span,section,article,header,footer,main,aside,nav,center{max-width:100%!important;min-width:0!important;}\
        pre,code{white-space:pre-wrap;word-wrap:break-word;max-width:100%!important;overflow-x:auto;}\
        blockquote{margin:8px 0;padding-left:12px;border-left:3px solid #ddd;}\
        a{color:#007AFF;}\
        .pm-quoted-text{border-left:3px solid #ccc;padding-left:10px;margin:8px 0;color:#666;}\
        </style>\
        </head>\
        <body>\(bodyContent)</body>\
        </html>
        """
    }

    /// Extract the inner body content from HTML, stripping any existing
    /// document wrappers (`<html>`, `<head>`, `<body>` tags) to prevent
    /// nested document structures.
    private static func extractBodyContent(_ html: String) -> String {
        var result = html

        // Remove DOCTYPE
        result = result.replacingOccurrences(
            of: "<!DOCTYPE[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove <html> and </html>
        result = result.replacingOccurrences(
            of: "</?html[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Extract <style> blocks from <head> before removing it.
        // These contain the email's CSS layout rules (already sanitized by Phase 1).
        var preservedStyles = ""
        if let headRegex = try? NSRegularExpression(
            pattern: "<head[^>]*>([\\s\\S]*?)</head\\s*>",
            options: .caseInsensitive
        ) {
            let nsResult = result as NSString
            let matches = headRegex.matches(
                in: result,
                range: NSRange(location: 0, length: nsResult.length)
            )
            for match in matches {
                if match.range(at: 1).location != NSNotFound,
                   let contentRange = Range(match.range(at: 1), in: result) {
                    let headContent = String(result[contentRange])
                    // Extract only <style>...</style> blocks from head content
                    if let styleRegex = try? NSRegularExpression(
                        pattern: "<style\\b[^>]*>[\\s\\S]*?</style\\s*>",
                        options: .caseInsensitive
                    ) {
                        let nsHead = headContent as NSString
                        let styleMatches = styleRegex.matches(
                            in: headContent,
                            range: NSRange(location: 0, length: nsHead.length)
                        )
                        for styleMatch in styleMatches {
                            if let styleRange = Range(styleMatch.range, in: headContent) {
                                preservedStyles += String(headContent[styleRange])
                            }
                        }
                    }
                }
            }
        }

        // Remove <head>...</head>
        result = result.replacingOccurrences(
            of: "<head[^>]*>[\\s\\S]*?</head\\s*>",
            with: preservedStyles,
            options: [.regularExpression, .caseInsensitive]
        )
        // Remove orphan <head> tags
        result = result.replacingOccurrences(
            of: "</?head[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove <body> and </body> tags (keep content)
        result = result.replacingOccurrences(
            of: "</?body[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - IMAP Framing Cleanup

    /// Strips leaked IMAP protocol framing from stored email bodies.
    ///
    /// A previous parser bug failed to respect IMAP literal length prefixes,
    /// causing raw protocol data like `BODY[1] {8609} ...content...` to be
    /// appended to the email body. This method removes such framing so
    /// already-synced emails render correctly.
    ///
    /// Also exposed as a public API so plain-text bodies can be cleaned too.
    public static func stripIMAPFraming(_ text: String) -> String {
        // Match "BODY[" (case-insensitive) followed by anything — this is always
        // IMAP protocol framing and never legitimate email content.
        // Truncate everything from the first occurrence of BODY[ onward.
        guard let range = text.range(
            of: "BODY\\[",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return text
        }

        let cleaned = String(text[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }

    // MARK: - Private Helpers

    /// Remove tags AND everything between their opening and closing forms.
    ///
    /// Handles both `<tag ...>...</tag>` and self-closing `<tag .../>`.
    private static func stripTagsWithContent(
        _ html: String,
        tags: [String]
    ) -> String {
        var result = html
        for tag in tags {
            // Match <tag ...>...</tag> (case-insensitive, dotall for content)
            let blockPattern = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>"
            result = result.replacingOccurrences(
                of: blockPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            // Also remove self-closing / orphan opening tags
            let selfClosingPattern = "<\(tag)\\b[^>]*/>"
            result = result.replacingOccurrences(
                of: selfClosingPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            let orphanPattern = "<\(tag)\\b[^>]*>"
            result = result.replacingOccurrences(
                of: orphanPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Remove the opening and closing tags but preserve any text between them.
    private static func stripTagsKeepingContent(
        _ html: String,
        tags: [String]
    ) -> String {
        var result = html
        for tag in tags {
            // Remove closing tags
            let closingPattern = "</\(tag)\\s*>"
            result = result.replacingOccurrences(
                of: closingPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            // Remove opening / self-closing tags
            let openingPattern = "<\(tag)\\b[^>]*/?>"
            result = result.replacingOccurrences(
                of: openingPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Remove `<meta http-equiv="refresh" ...>` tags.
    private static func stripMetaRefresh(_ html: String) -> String {
        let pattern = "<meta\\b[^>]*http-equiv\\s*=\\s*[\"']?refresh[\"']?[^>]*/?>"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Remove `<link rel="stylesheet" ...>` tags.
    private static func stripExternalStylesheetLinks(_ html: String) -> String {
        let pattern = "<link\\b[^>]*rel\\s*=\\s*[\"']?stylesheet[\"']?[^>]*/?>"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Sanitize `<style>` blocks: keep safe CSS rules, strip dangerous ones.
    ///
    /// Many HTML emails (Facebook, banks, newsletters) rely on `<style>` blocks
    /// for their table-based layouts. Stripping all `<style>` tags breaks rendering.
    /// Instead, we preserve the CSS but remove dangerous constructs:
    /// - `@import` rules (remote stylesheet loading)
    /// - `url(...)` values (remote resource loading)
    /// - `expression(...)` (IE-specific JS-in-CSS)
    /// - `javascript:` URIs
    /// - `-moz-binding` (Firefox XBL injection)
    /// - `behavior:` (IE HTC)
    private static func sanitizeStyleBlocks(_ html: String) -> String {
        let pattern = "<style\\b[^>]*>([\\s\\S]*?)</style\\s*>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }

            let contentRange = match.range(at: 1)
            guard contentRange.location != NSNotFound,
                  let resolvedRange = Range(contentRange, in: result) else {
                // No content — remove empty style tag
                result.removeSubrange(fullRange)
                continue
            }

            var css = String(result[resolvedRange])

            // Strip @import rules
            css = css.replacingOccurrences(
                of: "@import\\s+[^;]+;",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            // Strip url(...) values (could load remote resources)
            css = css.replacingOccurrences(
                of: "url\\s*\\([^)]*\\)",
                with: "none",
                options: [.regularExpression, .caseInsensitive]
            )

            // Strip expression(...) (IE JS-in-CSS)
            css = css.replacingOccurrences(
                of: "expression\\s*\\([^)]*\\)",
                with: "none",
                options: [.regularExpression, .caseInsensitive]
            )

            // Strip javascript: URIs
            css = css.replacingOccurrences(
                of: "javascript\\s*:",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            // Strip -moz-binding (Firefox XBL)
            css = css.replacingOccurrences(
                of: "-moz-binding\\s*:[^;]+;?",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            // Strip behavior: (IE HTC)
            css = css.replacingOccurrences(
                of: "behavior\\s*:[^;]+;?",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            // If CSS is now effectively empty, remove the whole block
            let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                result.removeSubrange(fullRange)
            } else {
                // Replace the style content with sanitized version
                result.replaceSubrange(fullRange, with: "<style>\(css)</style>")
            }
        }

        return result
    }

    /// Remove CSS `@import` rules that might appear in inline styles.
    private static func stripCSSImportRules(_ html: String) -> String {
        let pattern = "@import\\s+[^;]+;"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Remove all event handler attributes (on*) from tags.
    private static func stripEventHandlerAttributes(_ html: String) -> String {
        // Matches onXxx="..." or onXxx='...' or bare onXxx=value inside tags.
        let pattern = "\\s+on\\w+\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Remove `srcset` attributes to avoid remote fetch paths outside `img[src]`.
    private static func stripSourceSetAttributes(_ html: String) -> String {
        let pattern = "\\s+srcset\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Drop inline styles that can trigger remote fetches (`url(...)`, `@import`).
    private static func stripStyleAttributesWithPotentialRemoteLoads(_ html: String) -> String {
        let pattern = "\\s+style\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }

            let valueRange = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range(at: 2)
            guard valueRange.location != NSNotFound,
                  let resolvedValueRange = Range(valueRange, in: result) else {
                continue
            }

            let styleValue = String(result[resolvedValueRange]).lowercased()
            if styleValue.contains("url(") || styleValue.contains("@import") {
                result.removeSubrange(fullRange)
            }
        }
        return result
    }

    /// Removes fixed `width` HTML attributes that cause horizontal overflow.
    ///
    /// Banking and marketing emails commonly include `width="600"` or similar
    /// fixed pixel widths on `<table>`, `<td>`, `<div>`, and `<img>` elements.
    /// These values break responsive rendering in a mobile WebView. We strip
    /// the attribute entirely so CSS `max-width: 100%` can control the layout.
    ///
    /// We preserve percentage-based widths (e.g. `width="100%"`) as they are
    /// already responsive, and keep `width` on `<img>` if it's small (to avoid
    /// stretching tiny icons/spacers).
    private static func neutralizeFixedWidthAttributes(_ html: String) -> String {
        // Match width="NNN" or width='NNN' (pixel values without unit or with px)
        // Capture the numeric value to check if it's large enough to cause overflow
        let pattern = "\\s+width\\s*=\\s*[\"']?(\\d+)(?:px)?[\"']?"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        guard !matches.isEmpty else { return html }

        var result = html
        // Process in reverse to preserve ranges
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }

            // Get the numeric width value
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let widthStr = nsHTML.substring(with: valueRange)
            guard let widthVal = Int(widthStr) else { continue }

            // Only strip widths > 100px (small widths may be for icons/spacers)
            if widthVal > 100 {
                result.removeSubrange(fullRange)
            }
        }

        return result
    }

    /// Removes fixed-width CSS properties from inline `style` attributes
    /// that cause horizontal overflow in mobile email rendering.
    ///
    /// Uses a simple two-pass approach:
    /// 1. Strip `width:NNNpx` (pixel values only, not percentages) from inline styles
    /// 2. Strip `min-width:NNNpx` from inline styles
    ///
    /// Preserves percentage-based values and other CSS properties.
    private static func neutralizeInlineStyleWidths(_ html: String) -> String {
        var result = html

        // Pattern 1: Remove "width: NNNpx" but NOT "width: NN%" from inline styles
        // Matches: width:600px, width: 580px, width:640px !important
        // Skips: width:100%, width:auto, max-width (handled separately)
        // The negative lookbehind (?<!-) prevents matching min-width or max-width here
        result = result.replacingOccurrences(
            of: "(?<![-a-z])width\\s*:\\s*\\d+(?:\\.\\d+)?px[^;\"']*;?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Pattern 2: Remove "min-width: NNNpx" from inline styles
        result = result.replacingOccurrences(
            of: "min-width\\s*:\\s*\\d+(?:\\.\\d+)?px[^;\"']*;?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Pattern 3: Remove "max-width: NNNpx" when it's a fixed large value
        // (we want our CSS max-width:100% to take over)
        result = result.replacingOccurrences(
            of: "max-width\\s*:\\s*\\d+(?:\\.\\d+)?px[^;\"']*;?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }

    /// Replace `javascript:` URIs in href, src, action attributes with `#`.
    private static func neutralizeJavaScriptURIs(_ html: String) -> String {
        // Handle double-quoted attributes: href="javascript:..."
        let doubleQuotePattern = "((?:href|src|action)\\s*=\\s*\")\\s*javascript:[^\"]*(\")";
        var result = html.replacingOccurrences(
            of: doubleQuotePattern,
            with: "$1#$2",
            options: [.regularExpression, .caseInsensitive]
        )
        // Handle single-quoted attributes: href='javascript:...'
        let singleQuotePattern = "((?:href|src|action)\\s*=\\s*')\\s*javascript:[^']*(')"
        result = result.replacingOccurrences(
            of: singleQuotePattern,
            with: "$1#$2",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
    }

    /// Neutralize `data:` URIs everywhere EXCEPT in `<img src="data:...">`.
    ///
    /// Strategy: first protect img src data URIs with a sentinel, neutralize
    /// remaining data: URIs, then restore the sentinels.
    private static func neutralizeDataURIsExceptImages(_ html: String) -> String {
        let sentinel = "___DATA_IMG_SAFE___"

        // Protect <img ... src="data:..." ...> (double-quoted)
        let imgDataDoublePattern = "(<img\\b[^>]*\\bsrc\\s*=\\s*\")data:([^\"]*\")"
        var result = html.replacingOccurrences(
            of: imgDataDoublePattern,
            with: "$1\(sentinel)$2",
            options: [.regularExpression, .caseInsensitive]
        )
        // Protect <img ... src='data:...' ...> (single-quoted)
        let imgDataSinglePattern = "(<img\\b[^>]*\\bsrc\\s*=\\s*')data:([^']*')"
        result = result.replacingOccurrences(
            of: imgDataSinglePattern,
            with: "$1\(sentinel)$2",
            options: [.regularExpression, .caseInsensitive]
        )

        // Neutralize remaining data: URIs (double-quoted)
        let dataDoublePattern = "((?:href|src|action)\\s*=\\s*\")\\s*data:[^\"]*(\")";
        result = result.replacingOccurrences(
            of: dataDoublePattern,
            with: "$1#$2",
            options: [.regularExpression, .caseInsensitive]
        )
        // Neutralize remaining data: URIs (single-quoted)
        let dataSinglePattern = "((?:href|src|action)\\s*=\\s*')\\s*data:[^']*(')"
        result = result.replacingOccurrences(
            of: dataSinglePattern,
            with: "$1#$2",
            options: [.regularExpression, .caseInsensitive]
        )

        // Restore protected img data URIs
        result = result.replacingOccurrences(of: sentinel, with: "data:")

        return result
    }

    /// Replace `cid:` inline image references with a user-visible placeholder.
    ///
    /// Per spec E-07, `cid:` images are not downloaded during sync (V1) and
    /// must NOT be counted as tracking pixels or remote content.
    private static func replaceCIDImages(_ html: String) -> String {
        let pattern = "<img\\b[^>]*\\bsrc\\s*=\\s*[\"']cid:[^\"']*[\"'][^>]*/?>|<img\\b[^>]*\\bsrc\\s*=\\s*[\"']cid:[^\"']*[\"'][^>]*>"
        return html.replacingOccurrences(
            of: pattern,
            with: "<span style=\"display:inline-block;padding:4px 8px;background:#f0f0f0;border:1px solid #ccc;border-radius:4px;font-size:12px;color:#888;\">[Inline image not available]</span>",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Enforce an allow-list of URI schemes for href, src, and action attributes.
    ///
    /// - **href**: allow `http://`, `https://`, `mailto:`, `#` (fragment/anchor)
    /// - **src**: allow `http://`, `https://`, `data:image/` (preserved from Phase 6)
    /// - **action**: allow `http://`, `https://` only
    ///
    /// Any other scheme is replaced with `#`.
    /// Runs after the blocklist phases (6, 6b) as defense-in-depth.
    ///
    /// PR #8 Comment 5: Spec requires non-http/https schemes to be neutralized.
    private static func enforceURISchemeAllowList(_ html: String) -> String {
        var result = html

        // href: allow http, https, mailto, # (anchors/fragments)
        result = replaceDisallowedURIs(
            in: result,
            attribute: "href",
            isAllowed: { value in
                let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
                return lower.hasPrefix("http://")
                    || lower.hasPrefix("https://")
                    || lower.hasPrefix("mailto:")
                    || lower.hasPrefix("#")
                    || lower == "#"
            }
        )

        // src: allow http, https, data:image/
        result = replaceDisallowedURIs(
            in: result,
            attribute: "src",
            isAllowed: { value in
                let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
                return lower.hasPrefix("http://")
                    || lower.hasPrefix("https://")
                    || lower.hasPrefix("data:image/")
            }
        )

        // action: allow http, https only
        result = replaceDisallowedURIs(
            in: result,
            attribute: "action",
            isAllowed: { value in
                let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
                return lower.hasPrefix("http://")
                    || lower.hasPrefix("https://")
            }
        )

        return result
    }

    /// Replace attribute values that don't pass the allow-list with `#`.
    ///
    /// Matches both single- and double-quoted attribute values for the given
    /// attribute name (e.g. `href`, `src`, `action`).
    private static func replaceDisallowedURIs(
        in html: String,
        attribute: String,
        isAllowed: (String) -> Bool
    ) -> String {
        // Pattern: attr = "value" or attr = 'value' or attr = bareValue
        let pattern = "(\\b\(attribute)\\s*=\\s*)(?:([\"'])([^\"']*?)\\2|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        guard !matches.isEmpty else { return html }

        var result = html
        // Replace in reverse order so ranges stay valid.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 5,
                  let fullRange = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let prefix = String(result[prefixRange])
            let quoteRange = match.range(at: 2)
            let quotedValueRange = match.range(at: 3)
            let unquotedValueRange = match.range(at: 4)

            let quote = quoteRange.location == NSNotFound
                ? "\""
                : String(result[Range(quoteRange, in: result)!])
            let rawValue: String
            if quotedValueRange.location != NSNotFound,
               let range = Range(quotedValueRange, in: result) {
                rawValue = String(result[range])
            } else if unquotedValueRange.location != NSNotFound,
                      let range = Range(unquotedValueRange, in: result) {
                rawValue = String(result[range])
            } else {
                continue
            }

            let canonical = canonicalizedURIForValidation(rawValue)
            if !isAllowed(canonical) {
                result.replaceSubrange(fullRange, with: "\(prefix)\(quote)#\(quote)")
            }
        }
        return result
    }

    /// Normalize URI attribute values before allow-list checks.
    ///
    /// Handles entity-obfuscated schemes (e.g. `jav&#x61;script:`) and strips
    /// control/whitespace characters sometimes used to evade prefix checks.
    private static func canonicalizedURIForValidation(_ value: String) -> String {
        let decoded = decodeHTMLEntities(value)
        let filteredScalars = decoded.unicodeScalars.filter { scalar in
            !(CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar))
        }
        return String(String.UnicodeScalarView(filteredScalars)).lowercased()
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value

        // Numeric entities (decimal): &#106;
        if let decimalRegex = try? NSRegularExpression(pattern: "&#([0-9]{1,7});?", options: []) {
            decoded = replaceMatches(in: decoded, with: decimalRegex) { groups in
                guard let number = Int(groups[0]),
                      let scalar = UnicodeScalar(number) else {
                    return ""
                }
                return String(Character(scalar))
            }
        }

        // Numeric entities (hex): &#x6a;
        if let hexRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]{1,6});?", options: []) {
            decoded = replaceMatches(in: decoded, with: hexRegex) { groups in
                guard let number = Int(groups[0], radix: 16),
                      let scalar = UnicodeScalar(number) else {
                    return ""
                }
                return String(Character(scalar))
            }
        }

        let namedEntityMap: [String: String] = [
            "&colon;": ":",
            "&tab;": "\t",
            "&newline;": "\n",
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, replacement) in namedEntityMap {
            decoded = decoded.replacingOccurrences(
                of: entity,
                with: replacement,
                options: .caseInsensitive
            )
        }

        return decoded
    }

    private static func replaceMatches(
        in value: String,
        with regex: NSRegularExpression,
        replacement: ([String]) -> String
    ) -> String {
        let nsValue = value as NSString
        let matches = regex.matches(
            in: value,
            range: NSRange(location: 0, length: nsValue.length)
        )
        guard !matches.isEmpty else { return value }

        var result = value
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: result),
                  let groupRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let group = String(result[groupRange])
            let replaced = replacement([group])
            result.replaceSubrange(fullRange, with: replaced)
        }
        return result
    }

    /// Replace remote `<img>` sources (http/https) with a placeholder comment.
    ///
    /// - Returns: Tuple of (modified HTML, count of blocked images).
    private static func blockRemoteImages(_ html: String) -> (String, Int) {
        let pattern = "<img\\b[^>]*\\bsrc\\s*=\\s*[\"']https?://[^\"']*[\"'][^>]*/?>|<img\\b[^>]*\\bsrc\\s*=\\s*[\"']https?://[^\"']*[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return (html, 0)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        guard !matches.isEmpty else {
            return (html, 0)
        }

        var result = html
        // Replace in reverse order so ranges stay valid.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: "<!-- remote-image-blocked -->")
        }

        return (result, matches.count)
    }
}
