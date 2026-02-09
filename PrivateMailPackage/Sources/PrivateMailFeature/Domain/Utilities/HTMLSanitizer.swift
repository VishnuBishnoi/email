import Foundation

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

        var result = html

        // --- Phase 1: Strip tags WITH their content ---
        result = stripTagsWithContent(result, tags: ["script", "noscript"])
        result = stripTagsWithContent(result, tags: ["style"])
        result = stripTagsWithContent(result, tags: ["object", "embed", "applet"])

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

        // --- Phase 6: Neutralize dangerous URI schemes ---
        result = neutralizeJavaScriptURIs(result)
        result = neutralizeDataURIsExceptImages(result)

        // --- Phase 6b: Replace cid: inline images with placeholder (E-07) ---
        result = replaceCIDImages(result)

        // --- Phase 6c: Enforce URI scheme allow-list (PR #8 Comment 5) ---
        result = enforceURISchemeAllowList(result)

        // --- Phase 7: Handle remote images ---
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

    /// Wrap HTML in a full document structure with Dynamic Type CSS.
    ///
    /// - Parameters:
    ///   - html: HTML content (already sanitized or raw).
    ///   - fontSizePoints: Base font size in points for the CSS body rule.
    /// - Returns: Complete HTML document string.
    public static func injectDynamicTypeCSS(
        _ html: String,
        fontSizePoints: CGFloat
    ) -> String {
        let sizeString = String(format: "%.0f", fontSizePoints)
        return """
        <html>\
        <head>\
        <meta name="viewport" content="width=device-width, initial-scale=1.0">\
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:;">\
        <style>\
        body{\
        font-size:\(sizeString)pt;\
        word-wrap:break-word;\
        overflow-wrap:break-word;\
        -webkit-text-size-adjust:none;\
        }\
        </style>\
        </head>\
        <body>\(html)</body>\
        </html>
        """
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
        // Pattern: attr = "value" or attr = 'value'
        let pattern = "(\(attribute)\\s*=\\s*)([\"'])([^\"']*?)\\2"
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
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let quoteRange = Range(match.range(at: 2), in: result),
                  let valueRange = Range(match.range(at: 3), in: result) else {
                continue
            }
            let prefix = String(result[prefixRange])
            let quote = String(result[quoteRange])
            let value = String(result[valueRange])

            if !isAllowed(value) {
                result.replaceSubrange(fullRange, with: "\(prefix)\(quote)#\(quote)")
            }
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
