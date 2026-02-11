import Foundation

/// Utilities for decoding MIME-encoded content in emails.
///
/// Handles:
/// - **RFC 2047 encoded-words** in headers (subjects, from names):
///   `=?charset?encoding?encoded-text?=`
/// - **Content-Transfer-Encoding** for body parts:
///   Base64, Quoted-Printable, 7bit/8bit pass-through.
///
/// Spec ref: RFC 2047 (MIME Part Three: Header Extensions),
/// RFC 2045 (Content-Transfer-Encoding).
enum MIMEDecoder {

    // MARK: - RFC 2047: Encoded-Word Decoding (Headers)

    /// Decodes RFC 2047 encoded-words in a header value.
    ///
    /// Handles patterns like:
    /// - `=?UTF-8?Q?Hello=20World?=` → "Hello World"
    /// - `=?UTF-8?B?SGVsbG8gV29ybGQ=?=` → "Hello World"
    /// - Multiple adjacent encoded-words with whitespace between
    /// - Mixed encoded and plain text
    ///
    /// - Parameter value: Raw header value potentially containing encoded-words.
    /// - Returns: Decoded string with all encoded-words replaced.
    static func decodeHeaderValue(_ value: String) -> String {
        guard value.contains("=?") else { return value }

        // RFC 2047 encoded-word pattern:
        // =?charset?encoding?encoded-text?=
        // charset: e.g. UTF-8, ISO-8859-1
        // encoding: Q (quoted-printable) or B (base64)
        let pattern = "=\\?([^?]+)\\?([QqBb])\\?([^?]*)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let nsString = value as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: value, range: fullRange)

        guard !matches.isEmpty else { return value }

        var result = ""
        var lastEnd = value.startIndex

        for match in matches {
            // Add text before this encoded-word
            let matchStart = value.index(value.startIndex, offsetBy: match.range.location)
            let textBefore = String(value[lastEnd..<matchStart])

            // RFC 2047 says whitespace between adjacent encoded-words should be ignored
            if !result.isEmpty && textBefore.allSatisfy({ $0.isWhitespace }) {
                // Skip whitespace between consecutive encoded-words
            } else {
                result += textBefore
            }

            let charset = nsString.substring(with: match.range(at: 1))
            let encoding = nsString.substring(with: match.range(at: 2)).uppercased()
            let encodedText = nsString.substring(with: match.range(at: 3))

            let decoded: String
            if encoding == "Q" {
                decoded = decodeQuotedPrintableHeader(encodedText, charset: charset)
            } else if encoding == "B" {
                decoded = decodeBase64Text(encodedText, charset: charset)
            } else {
                decoded = encodedText
            }
            result += decoded

            let matchEnd = match.range.location + match.range.length
            lastEnd = value.index(value.startIndex, offsetBy: matchEnd)
        }

        // Append remaining text after last match
        result += String(value[lastEnd...])

        return result
    }

    // MARK: - Content-Transfer-Encoding Decoding (Bodies)

    /// Decodes body content based on Content-Transfer-Encoding.
    ///
    /// - Parameters:
    ///   - content: Raw body content from IMAP FETCH.
    ///   - encoding: Transfer encoding (e.g. "BASE64", "QUOTED-PRINTABLE", "7BIT").
    ///   - charset: Character set (e.g. "UTF-8", "ISO-8859-1"). Defaults to UTF-8.
    /// - Returns: Decoded text content.
    static func decodeBody(_ content: String, encoding: String, charset: String = "UTF-8") -> String {
        let enc = encoding.uppercased().trimmingCharacters(in: .whitespaces)

        switch enc {
        case "BASE64":
            return decodeBase64Body(content, charset: charset)
        case "QUOTED-PRINTABLE":
            return decodeQuotedPrintableBody(content, charset: charset)
        case "7BIT", "8BIT", "BINARY":
            return content
        default:
            return content
        }
    }

    // MARK: - Private: Quoted-Printable Decoding

    /// Decodes RFC 2047 Q-encoding (used in headers).
    ///
    /// Q-encoding rules (slightly different from body QP):
    /// - Underscores `_` represent spaces (ASCII 0x20)
    /// - `=XX` represents a hex-encoded byte
    private static func decodeQuotedPrintableHeader(_ text: String, charset: String) -> String {
        // Replace underscores with spaces (RFC 2047 Q-encoding rule)
        let withSpaces = text.replacingOccurrences(of: "_", with: " ")
        let bytes = decodeQuotedPrintableBytes(withSpaces)
        return stringFromBytes(bytes, charset: charset)
    }

    /// Decodes Quoted-Printable body content (RFC 2045).
    ///
    /// Body QP rules:
    /// - `=XX` represents a hex-encoded byte
    /// - `=\r\n` is a soft line break (remove it)
    /// - Lines should not exceed 76 characters
    private static func decodeQuotedPrintableBody(_ text: String, charset: String) -> String {
        // Remove soft line breaks: =\r\n or =\n
        let noSoftBreaks = text
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
        let bytes = decodeQuotedPrintableBytes(noSoftBreaks)
        return stringFromBytes(bytes, charset: charset)
    }

    /// Converts quoted-printable encoded text to raw bytes.
    private static func decodeQuotedPrintableBytes(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            if char == "=" {
                // Check for hex pair
                let next1 = text.index(after: index)
                guard next1 < text.endIndex else {
                    bytes.append(UInt8(char.asciiValue ?? 0x3D))
                    index = next1
                    continue
                }

                let next2 = text.index(after: next1)
                guard next2 < text.endIndex else {
                    bytes.append(UInt8(char.asciiValue ?? 0x3D))
                    index = next1
                    continue
                }

                // Two hex chars after =
                let hexStr = String(text[next1...next2])
                if hexStr.count == 2, let byte = UInt8(hexStr, radix: 16) {
                    bytes.append(byte)
                    index = text.index(after: next2)
                } else {
                    // Not valid hex, keep the = literal
                    bytes.append(0x3D) // '='
                    index = next1
                }
            } else {
                if let ascii = char.asciiValue {
                    bytes.append(ascii)
                } else {
                    // Non-ASCII — encode as UTF-8 bytes
                    bytes.append(contentsOf: String(char).utf8)
                }
                index = text.index(after: index)
            }
        }

        return bytes
    }

    // MARK: - Public: Binary Decoding (for attachment downloads)

    /// Decodes a quoted-printable encoded string to raw binary `Data`.
    ///
    /// Unlike `decodeQuotedPrintableBody` (which returns a String), this preserves
    /// raw bytes for binary attachments (images, PDFs, etc.).
    ///
    /// Spec ref: FR-SYNC-08 (Attachment download)
    static func decodeQuotedPrintableToData(_ text: String) -> Data {
        let noSoftBreaks = text
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
        let bytes = decodeQuotedPrintableBytes(noSoftBreaks)
        return Data(bytes)
    }

    // MARK: - Private: Base64 Decoding

    /// Decodes Base64-encoded text with charset conversion.
    private static func decodeBase64Text(_ text: String, charset: String) -> String {
        // Remove whitespace/newlines that might be in the encoded text
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard let data = Data(base64Encoded: cleaned) else {
            return text
        }

        return stringFromData(data, charset: charset)
    }

    /// Decodes a Base64-encoded body (may have line wrapping).
    private static func decodeBase64Body(_ content: String, charset: String) -> String {
        // Base64 bodies are typically line-wrapped at 76 chars
        let cleaned = content
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let data = Data(base64Encoded: cleaned) else {
            return content
        }

        return stringFromData(data, charset: charset)
    }

    // MARK: - Multipart MIME Body Parsing

    /// Result of parsing a raw multipart MIME body.
    struct MultipartResult: Sendable {
        /// Decoded plain text body, if found.
        let plainText: String?
        /// Decoded HTML body, if found.
        let htmlText: String?
    }

    /// Parses a raw multipart MIME body into decoded plain text and HTML parts.
    ///
    /// When BODYSTRUCTURE parsing fails to identify individual text parts
    /// (e.g. for some banking emails), the IMAP client falls back to
    /// `BODY[TEXT]`, which for multipart messages returns the raw MIME
    /// multipart content including boundaries, part headers, and
    /// transfer-encoded content. This method splits that content at MIME
    /// boundaries and decodes each part according to its headers.
    ///
    /// - Parameter rawBody: The raw `BODY[TEXT]` content that may contain
    ///   MIME boundaries, part headers, and encoded body content.
    /// - Returns: A ``MultipartResult`` with decoded text and/or HTML content,
    ///   or `nil` if the content is not multipart.
    static func parseMultipartBody(_ rawBody: String) -> MultipartResult? {
        // Detect multipart content by looking for MIME boundary markers.
        // Boundaries appear as "--<boundary_string>" in the body.
        guard let boundary = extractBoundary(from: rawBody) else {
            return nil
        }

        let delimiter = "--\(boundary)"

        // Strip trailing IMAP FETCH closing paren that may be stored with the content.
        // The `)` appears when raw BODY[TEXT] content was stored with the IMAP response framing.
        var cleanedBody = rawBody
        let bodyTrimmed = cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if bodyTrimmed.hasSuffix(")") {
            // Only strip if the last ) isn't part of legitimate MIME content
            // (it would be after the closing boundary --boundary--)
            if let endBoundary = bodyTrimmed.range(of: "--\(boundary)--") {
                let afterEnd = bodyTrimmed[endBoundary.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if afterEnd == ")" {
                    cleanedBody = String(bodyTrimmed.dropLast())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Split the body at boundary markers
        let segments = cleanedBody.components(separatedBy: delimiter)

        var plainText: String?
        var htmlText: String?

        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty segments, preamble, and the end marker (-- or --\n))
            if trimmed.isEmpty || trimmed == "--" || trimmed.hasPrefix("--") { continue }

            // Parse part headers and body
            guard let parsed = parseMIMEPart(trimmed) else { continue }

            let contentType = parsed.contentType.lowercased()
            let encoding = parsed.encoding
            let charset = parsed.charset

            // Decode the body using Content-Transfer-Encoding
            let decoded = decodeBody(parsed.body, encoding: encoding, charset: charset)

            if contentType.contains("text/html") {
                htmlText = decoded
            } else if contentType.contains("text/plain") {
                plainText = decoded
            }
        }

        // Only return if we actually found usable content
        guard plainText != nil || htmlText != nil else { return nil }
        return MultipartResult(plainText: plainText, htmlText: htmlText)
    }

    /// Detects whether the content appears to be raw MIME multipart data.
    ///
    /// Checks for the preamble "This is a multi-part message in MIME format"
    /// or MIME boundary patterns (`--boundary_string`).
    static func isMultipartContent(_ content: String) -> Bool {
        let prefix = content.prefix(500).lowercased()
        if prefix.contains("this is a multi-part message in mime format") {
            return true
        }
        // Look for MIME boundary pattern: line starting with --
        // followed by Content-Type header on a nearby line
        if prefix.contains("content-type:") && content.contains("\n--") {
            return true
        }
        return false
    }

    /// Strips raw MIME multipart framing from content, returning just the
    /// decoded body text. Used as a render-time safety net for data that was
    /// already stored with raw MIME content.
    ///
    /// - Parameter text: Potentially MIME-contaminated text.
    /// - Returns: The decoded plain text content, or the original text if no
    ///   MIME framing was detected.
    static func stripMIMEFraming(_ text: String) -> String {
        guard isMultipartContent(text) else { return text }

        if let result = parseMultipartBody(text) {
            // Prefer plain text for plain-text display paths
            if let plain = result.plainText, !plain.isEmpty {
                return plain
            }
            if let html = result.htmlText, !html.isEmpty {
                // Strip HTML tags for plain text display
                return stripHTMLForPlainText(html)
            }
        }

        // If parsing failed, try to extract content after the first blank line
        // following a Content-Type header (best effort)
        let bestEffort = extractBestEffortContent(from: text)
        // Guard: if best-effort extraction produced very short junk
        // (e.g. lone ")" from IMAP framing), return original
        let cleaned = bestEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 3 || cleaned == ")" || cleaned == "()" {
            return text
        }
        return bestEffort
    }

    /// Strips raw MIME multipart framing from HTML content, returning the
    /// decoded HTML body. Used as a render-time safety net for HTML display paths.
    ///
    /// - Parameter html: Potentially MIME-contaminated HTML.
    /// - Returns: The decoded HTML content, or the original HTML if no MIME
    ///   framing was detected.
    static func stripMIMEFramingForHTML(_ html: String) -> String {
        guard isMultipartContent(html) else { return html }

        if let result = parseMultipartBody(html) {
            // Prefer HTML for HTML display paths
            if let htmlContent = result.htmlText, !htmlContent.isEmpty {
                return htmlContent
            }
            if let plain = result.plainText, !plain.isEmpty {
                return plain
            }
        }

        let bestEffort = extractBestEffortContent(from: html)
        // Guard: if best-effort extraction produced very short junk
        // (e.g. lone ")" from IMAP framing), return original
        let cleaned = bestEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 3 || cleaned == ")" || cleaned == "()" {
            return html
        }
        return bestEffort
    }

    // MARK: - Private: Multipart Helpers

    /// Extracts the MIME boundary string from raw multipart content.
    ///
    /// Looks for the first line starting with `--` that looks like a boundary
    /// (not just `--` by itself, which marks the end).
    private static func extractBoundary(from content: String) -> String? {
        // Strategy 1: Look for Content-Type header with boundary parameter
        // This handles cases where the multipart has a Content-Type at the top
        let lines = content.components(separatedBy: .newlines)
        for line in lines.prefix(20) {
            let lower = line.lowercased()
            if lower.contains("boundary=") {
                return parseBoundaryValue(from: line)
            }
        }

        // Strategy 2: Find the first line starting with "--" that looks like a boundary
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))
            if trimmed.hasPrefix("--") && trimmed.count > 3 && !trimmed.hasSuffix("--") {
                // This looks like a boundary delimiter
                let candidate = String(trimmed.dropFirst(2))
                // Verify it appears more than once (a real boundary)
                let delimiter = "--\(candidate)"
                let occurrences = content.components(separatedBy: delimiter).count - 1
                if occurrences >= 2 {
                    return candidate
                }
            }
        }

        return nil
    }

    /// Parses the boundary value from a Content-Type header line.
    ///
    /// Handles both quoted and unquoted boundary values:
    /// - `boundary="----=_Part_123"` → `----=_Part_123`
    /// - `boundary=----=_Part_123` → `----=_Part_123`
    private static func parseBoundaryValue(from line: String) -> String? {
        guard let boundaryRange = line.range(of: "boundary=", options: .caseInsensitive) else {
            return nil
        }

        var value = String(line[boundaryRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        // Remove trailing semicolons or other parameters
        if let semiIdx = value.firstIndex(of: ";") {
            value = String(value[..<semiIdx])
        }

        // Remove quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }

        return value.isEmpty ? nil : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Represents a parsed individual MIME part.
    private struct ParsedMIMEPart {
        let contentType: String
        let encoding: String
        let charset: String
        let body: String
    }

    /// Parses an individual MIME part into its headers and body content.
    ///
    /// A MIME part looks like:
    /// ```
    /// Content-Type: text/plain; charset="utf-8"
    /// Content-Transfer-Encoding: quoted-printable
    ///
    /// Decoded body content here...
    /// ```
    private static func parseMIMEPart(_ segment: String) -> ParsedMIMEPart? {
        // Split headers from body at the first blank line
        // Handle both \r\n\r\n and \n\n
        let headerBodySeparators = ["\r\n\r\n", "\n\n"]
        var headerPart: String?
        var bodyPart: String?

        for separator in headerBodySeparators {
            if let range = segment.range(of: separator) {
                headerPart = String(segment[..<range.lowerBound])
                bodyPart = String(segment[range.upperBound...])
                break
            }
        }

        guard let headers = headerPart, let body = bodyPart else {
            // No headers found — might be just content, skip it
            return nil
        }

        // Parse headers
        var contentType = "text/plain"
        var encoding = "7BIT"
        var charset = "UTF-8"

        let headerLines = headers.components(separatedBy: .newlines)
        var i = 0
        while i < headerLines.count {
            var line = headerLines[i].trimmingCharacters(in: .init(charactersIn: "\r"))

            // Handle header continuation (lines starting with whitespace)
            while i + 1 < headerLines.count {
                let nextLine = headerLines[i + 1].trimmingCharacters(in: .init(charactersIn: "\r"))
                if nextLine.hasPrefix(" ") || nextLine.hasPrefix("\t") {
                    line += " " + nextLine.trimmingCharacters(in: .whitespaces)
                    i += 1
                } else {
                    break
                }
            }

            let lower = line.lowercased()
            if lower.hasPrefix("content-type:") {
                let value = String(line.dropFirst("Content-Type:".count))
                    .trimmingCharacters(in: .whitespaces)
                contentType = value
                // Extract charset from Content-Type
                if let charsetMatch = value.range(of: "charset=", options: .caseInsensitive) {
                    var cs = String(value[charsetMatch.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    // Remove trailing parameters and quotes
                    if let semi = cs.firstIndex(of: ";") {
                        cs = String(cs[..<semi])
                    }
                    cs = cs.replacingOccurrences(of: "\"", with: "")
                    if !cs.isEmpty { charset = cs }
                }
            } else if lower.hasPrefix("content-transfer-encoding:") {
                encoding = String(line.dropFirst("Content-Transfer-Encoding:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
            }

            i += 1
        }

        // Clean up body — remove trailing end-boundary marker if present
        var cleanBody = body
        if let endMarkerRange = cleanBody.range(of: "\n--", options: .backwards) {
            // Check if what follows is a boundary marker
            let afterMarker = cleanBody[endMarkerRange.upperBound...]
            // Only trim if it looks like a MIME boundary (not regular content)
            if afterMarker.count < 200 && !afterMarker.contains("<") {
                cleanBody = String(cleanBody[..<endMarkerRange.lowerBound])
            }
        }

        // Strip trailing IMAP FETCH response closing paren
        var trimmedBody = cleanBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.hasSuffix("\n)") || trimmedBody.hasSuffix("\r\n)") {
            trimmedBody = String(trimmedBody.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParsedMIMEPart(
            contentType: contentType,
            encoding: encoding,
            charset: charset,
            body: trimmedBody
        )
    }

    /// Simple HTML tag stripper for converting HTML to plain text.
    private static func stripHTMLForPlainText(_ html: String) -> String {
        var result = html
        // Replace <br> and block-closing tags with newlines
        result = result.replacingOccurrences(
            of: "<br\\s*/?>|</p>|</div>|</li>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode common entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse blank lines
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort content extraction when MIME parsing fails.
    ///
    /// Tries to skip past MIME headers and boundary preambles to find
    /// the actual content.
    private static func extractBestEffortContent(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var inBody = false
        var result: [String] = []
        var skipCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))

            // Skip MIME preamble
            if trimmed.lowercased().contains("this is a multi-part message in mime format") {
                continue
            }
            // Skip boundary lines
            if trimmed.hasPrefix("--") && trimmed.count > 4 {
                inBody = false
                skipCount = 0
                continue
            }
            // Skip MIME headers
            let lower = trimmed.lowercased()
            if lower.hasPrefix("content-type:") ||
               lower.hasPrefix("content-transfer-encoding:") ||
               lower.hasPrefix("content-disposition:") {
                continue
            }
            // Blank line after headers signals body start
            if trimmed.isEmpty && !inBody {
                inBody = true
                skipCount += 1
                continue
            }

            if inBody {
                result.append(trimmed)
            }
        }

        let content = result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? text : content
    }

    // MARK: - Private: Charset Conversion

    /// Converts raw bytes to a String using the specified charset.
    private static func stringFromBytes(_ bytes: [UInt8], charset: String) -> String {
        let data = Data(bytes)
        return stringFromData(data, charset: charset)
    }

    /// Converts Data to a String using the specified charset.
    private static func stringFromData(_ data: Data, charset: String) -> String {
        let encoding = encodingFromCharset(charset)
        return String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) ?? ""
    }

    /// Maps a MIME charset name to a Swift `String.Encoding`.
    private static func encodingFromCharset(_ charset: String) -> String.Encoding {
        switch charset.uppercased() {
        case "UTF-8", "UTF8":
            return .utf8
        case "ISO-8859-1", "LATIN1", "LATIN-1":
            return .isoLatin1
        case "ISO-8859-2", "LATIN2", "LATIN-2":
            return .isoLatin2
        case "US-ASCII", "ASCII":
            return .ascii
        case "WINDOWS-1252", "CP1252":
            return .windowsCP1252
        case "WINDOWS-1251", "CP1251":
            return .windowsCP1251
        case "WINDOWS-1250", "CP1250":
            return .windowsCP1250
        case "ISO-2022-JP":
            return .iso2022JP
        case "EUC-JP":
            return .japaneseEUC
        case "SHIFT_JIS", "SHIFT-JIS":
            return .shiftJIS
        case "UTF-16", "UTF16":
            return .utf16
        case "UTF-16BE":
            return .utf16BigEndian
        case "UTF-16LE":
            return .utf16LittleEndian
        case "UTF-32", "UTF32":
            return .utf32
        case "GB2312", "GB18030", "GBK":
            // Best effort: fall back to UTF-8 for Chinese encodings
            return .utf8
        case "BIG5":
            return .utf8
        case "KOI8-R":
            return .utf8
        default:
            return .utf8
        }
    }
}
