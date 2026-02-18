import Foundation

/// Stateless parser for IMAP server responses.
///
/// Converts raw IMAP response strings into structured DTOs
/// (IMAPFolderInfo, IMAPEmailHeader, IMAPEmailBody).
///
/// Spec ref: Email Sync spec FR-SYNC-01 (Folder discovery, Email sync)
enum IMAPResponseParser {

    // MARK: - Shared DateFormatters (allocated once, reused)

    /// RFC 2822: "Mon, 1 Jan 2024 12:00:00 +0000"
    private static let rfc2822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Short: "1 Jan 2024 12:00:00 +0000" (no weekday)
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// IMAP internal: "01-Jan-2024 12:00:00 +0000"
    private static let imapInternalDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - LIST Response Parsing

    /// Parses a `* LIST` response line into an `IMAPFolderInfo`.
    ///
    /// Format: `* LIST (<attributes>) "<delimiter>" "<path>"`
    /// Example: `* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail"`
    static func parseListResponse(_ line: String) -> IMAPFolderInfo? {
        // Remove "* LIST " prefix (case-insensitive for server compat)
        let upper = line.uppercased()
        guard upper.hasPrefix("* LIST ") else { return nil }
        let content = String(line.dropFirst("* LIST ".count))

        // Parse attributes: everything between first ( and matching )
        guard let attrStart = content.firstIndex(of: "("),
              let attrEnd = content.firstIndex(of: ")") else {
            return nil
        }

        let attrString = String(content[content.index(after: attrStart)..<attrEnd])
        let attributes = attrString
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        // After ") " comes: "delimiter" "path"
        let afterAttrs = String(content[content.index(after: attrEnd)...]).trimmingCharacters(in: .whitespaces)

        // Parse the remaining: "<delimiter>" "<path>" or NIL "<path>"
        let parts = parseQuotedParts(afterAttrs)

        // The last quoted string is the folder path
        guard parts.count >= 2 else { return nil }
        let imapPath = parts.last!
        let name = extractFolderName(from: imapPath)

        return IMAPFolderInfo(
            name: name,
            imapPath: imapPath,
            attributes: attributes,
            uidValidity: 0,  // Populated on SELECT
            messageCount: 0  // Populated on SELECT
        )
    }

    // MARK: - SELECT Response Parsing

    /// Extracts UIDVALIDITY from SELECT response lines.
    ///
    /// Looks for `* OK [UIDVALIDITY <value>]`
    static func parseUIDValidity(from responses: [String]) -> UInt32 {
        for line in responses {
            if let range = line.range(of: "UIDVALIDITY ") {
                let afterKey = line[range.upperBound...]
                let numStr = afterKey.prefix(while: { $0.isNumber })
                if let value = UInt32(numStr) {
                    return value
                }
            }
        }
        return 0
    }

    /// Extracts EXISTS count from SELECT response lines.
    ///
    /// Looks for `* <count> EXISTS`
    static func parseExists(from responses: [String]) -> UInt32 {
        for line in responses {
            if line.hasSuffix("EXISTS") || line.contains(" EXISTS") {
                // Pattern: "* 42 EXISTS"
                let stripped = line.hasPrefix("* ") ? String(line.dropFirst(2)) : line
                let parts = stripped.split(separator: " ")
                if let countStr = parts.first, let count = UInt32(countStr) {
                    return count
                }
            }
        }
        return 0
    }

    // MARK: - SEARCH Response Parsing

    /// Parses a `* SEARCH` response into a list of UIDs.
    ///
    /// Format: `* SEARCH 101 102 103`
    static func parseSearchResponse(from responses: [String]) -> [UInt32] {
        for line in responses {
            if line.hasPrefix("* SEARCH") {
                let content = String(line.dropFirst("* SEARCH".count))
                    .trimmingCharacters(in: .whitespaces)
                if content.isEmpty { return [] }

                return content
                    .split(separator: " ")
                    .compactMap { UInt32($0) }
            }
        }
        return []
    }

    // MARK: - FETCH Header Parsing

    /// Parses FETCH response lines into `IMAPEmailHeader` objects.
    ///
    /// Expected FETCH items: UID, FLAGS, RFC822.SIZE, BODY[HEADER.FIELDS (...)]
    static func parseHeaderResponses(_ responses: [String]) -> [IMAPEmailHeader] {
        var headers: [IMAPEmailHeader] = []

        for response in responses {
            guard response.contains("FETCH") else { continue }

            let uid = extractUID(from: response)
            let flags = extractFlags(from: response)
            let size = extractSize(from: response)
            let headerFields = extractHeaderFields(from: response)

            // Decode RFC 2047 encoded-words in headers (subjects, names, etc.)
            let header = IMAPEmailHeader(
                uid: uid,
                messageId: headerFields["message-id"],
                inReplyTo: headerFields["in-reply-to"],
                references: headerFields["references"],
                from: headerFields["from"].map { MIMEDecoder.decodeHeaderValue($0) },
                to: parseAddressList(headerFields["to"]).map { MIMEDecoder.decodeHeaderValue($0) },
                cc: parseAddressList(headerFields["cc"]).map { MIMEDecoder.decodeHeaderValue($0) },
                bcc: parseAddressList(headerFields["bcc"]).map { MIMEDecoder.decodeHeaderValue($0) },
                subject: headerFields["subject"].map { MIMEDecoder.decodeHeaderValue($0) },
                date: parseIMAPDate(headerFields["date"]),
                flags: flags,
                size: size,
                authenticationResults: headerFields["authentication-results"]
            )

            headers.append(header)
        }

        return headers
    }

    // MARK: - FETCH Body Parsing

    /// Parses FETCH body response lines into `IMAPEmailBody` objects.
    ///
    /// Handles both single-part and multi-part responses.
    static func parseBodyResponses(_ responses: [String]) -> [IMAPEmailBody] {
        var bodies: [IMAPEmailBody] = []

        for response in responses {
            guard response.contains("FETCH") else { continue }

            let uid = extractUID(from: response)
            let bodyParts = extractBodyParts(from: response)
            let attachments = extractAttachmentInfo(from: response)

            let body = IMAPEmailBody(
                uid: uid,
                plainText: bodyParts["text/plain"],
                htmlText: bodyParts["text/html"],
                attachments: attachments
            )

            bodies.append(body)
        }

        return bodies
    }

    // MARK: - FETCH Flags Parsing

    /// Parses FETCH flags response lines into a UID → flags dictionary.
    static func parseFlagResponses(_ responses: [String]) -> [UInt32: [String]] {
        var result: [UInt32: [String]] = [:]

        for response in responses {
            guard response.contains("FETCH") else { continue }

            let uid = extractUID(from: response)
            let flags = extractFlags(from: response)
            if uid > 0 {
                result[uid] = flags
            }
        }

        return result
    }

    // MARK: - BODYSTRUCTURE Parsing

    /// Represents a part of an email's body structure.
    struct BodyPart {
        let partId: String
        let mimeType: String
        let filename: String?
        let size: UInt32
        let contentId: String?
        let isAttachment: Bool
        /// Content-Transfer-Encoding (e.g. "BASE64", "QUOTED-PRINTABLE", "7BIT")
        let encoding: String
        /// Charset from Content-Type parameters (e.g. "UTF-8", "ISO-8859-1")
        let charset: String
    }

    /// Parses BODYSTRUCTURE from a FETCH response.
    ///
    /// Returns all body parts with their part IDs and MIME types.
    static func parseBodyStructure(from response: String) -> [BodyPart] {
        // Find BODYSTRUCTURE content
        guard let bsRange = response.range(of: "BODYSTRUCTURE ", options: .caseInsensitive) else {
            return []
        }

        let afterBS = String(response[bsRange.upperBound...])

        // Find the matching parenthesized content
        guard let parenContent = extractParenContent(afterBS) else {
            return []
        }

        // Parse the structure recursively
        var parts: [BodyPart] = []
        parseBodyStructureRecursive(parenContent, partPrefix: "", parts: &parts)
        return parts
    }

    // MARK: - Multi-UID BODYSTRUCTURE Parsing

    /// Parses BODYSTRUCTURE from multiple FETCH response lines (batch fetch).
    ///
    /// Used by the 2-phase batched body fetch (Phase 1) to get all structures
    /// in a single round trip instead of one per UID (N+1 fix).
    ///
    /// - Parameter responses: Raw IMAP response lines from
    ///   `UID FETCH uid1,uid2,...,uidN (UID BODYSTRUCTURE)`
    /// - Returns: Mapping of UID → body parts
    static func parseMultiBodyStructures(from responses: [String]) -> [UInt32: [BodyPart]] {
        var result: [UInt32: [BodyPart]] = [:]
        for response in responses {
            guard response.uppercased().contains("BODYSTRUCTURE") else { continue }
            let uid = extractUID(from: response)
            guard uid > 0 else { continue }
            let parts = parseBodyStructure(from: response)
            result[uid] = parts
        }
        return result
    }

    /// Extracts body part content from a FETCH response, keyed by IMAP section ID.
    ///
    /// Unlike `extractBodyParts` (which keys by guessed content type), this keys
    /// by the raw section number so callers with BODYSTRUCTURE metadata can
    /// accurately determine content types themselves.
    ///
    /// Properly respects IMAP literal length prefixes `{NNN}` to extract
    /// exactly the declared number of bytes, preventing protocol framing
    /// from leaking into body content.
    ///
    /// Example: `"* 1 FETCH (UID 101 BODY[1] {5}\nHello)"` → `["1": "Hello"]`
    static func extractBodyPartsBySection(from response: String) -> [String: String] {
        var parts: [String: String] = [:]

        let scanner = response as NSString
        let searchRange = NSRange(location: 0, length: scanner.length)
        let pattern = "BODY\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return parts
        }

        let matches = regex.matches(in: response, options: [], range: searchRange)

        for match in matches {
            let sectionRange = match.range(at: 1)
            let section = scanner.substring(with: sectionRange)

            // Skip HEADER.FIELDS sections (those are headers, not body)
            if section.contains("HEADER") { continue }

            let afterBodyStart = match.range.upperBound
            guard afterBodyStart < scanner.length else { continue }

            let afterBodyRange = NSRange(
                location: afterBodyStart,
                length: scanner.length - afterBodyStart
            )
            let afterBody = scanner.substring(with: afterBodyRange)

            if afterBody.trimmingCharacters(in: .whitespaces).hasPrefix("NIL") {
                continue
            }

            if let content = extractLiteralContent(from: afterBody) {
                parts[section] = content
            }
        }

        return parts
    }

    // MARK: - IMAP Literal Extraction

    /// Extracts the content of an IMAP literal `{NNN}\r\n<content>` from the
    /// text following a `BODY[section]` marker.
    ///
    /// IMAP servers send body content as synchronizing literals with a length
    /// prefix. For example:
    /// ```
    /// BODY[1] {250}
    /// This is the plain text body...
    /// ```
    ///
    /// This method:
    /// 1. Parses the `{NNN}` length prefix
    /// 2. Reads exactly `NNN` bytes of content after the newline
    /// 3. Falls back to reading until the next `BODY[` marker or closing `)` if
    ///    no length prefix is found (tolerance for unusual server responses)
    ///
    /// - Parameter afterBody: The string after `BODY[section]` in the response
    /// - Returns: The extracted content, or `nil` if nothing could be parsed
    private static func extractLiteralContent(from afterBody: String) -> String? {
        let trimmed = afterBody.trimmingCharacters(in: .whitespaces)

        // Try to parse IMAP literal: {NNN}\r\n or {NNN}\n
        if trimmed.hasPrefix("{") {
            // Extract the byte count from {NNN}
            guard let closeBrace = trimmed.firstIndex(of: "}") else {
                return extractFallbackContent(from: afterBody)
            }

            let countStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBrace])
            guard let byteCount = Int(countStr), byteCount > 0 else {
                return extractFallbackContent(from: afterBody)
            }

            // Find start of content (after the newline following })
            let afterBrace = trimmed[trimmed.index(after: closeBrace)...]
            // Skip \r\n or \n
            var contentStart = afterBrace.startIndex
            if contentStart < afterBrace.endIndex && afterBrace[contentStart] == "\r" {
                contentStart = afterBrace.index(after: contentStart)
            }
            if contentStart < afterBrace.endIndex && afterBrace[contentStart] == "\n" {
                contentStart = afterBrace.index(after: contentStart)
            }

            // Extract exactly byteCount characters from the UTF-8 content.
            // IMAP literal length is in bytes (octets), but since we're working
            // with a String that was already decoded from the socket, we use
            // UTF-8 byte counting for accuracy.
            let contentSubstring = trimmed[contentStart...]
            let utf8View = contentSubstring.utf8
            let endOffset = min(byteCount, utf8View.count)
            let endIndex = utf8View.index(utf8View.startIndex, offsetBy: endOffset)

            // Convert the UTF-8 index back to a String index
            guard let stringEndIndex = endIndex.samePosition(in: trimmed) else {
                // If the byte boundary falls in the middle of a character,
                // find the nearest valid character boundary
                let content = String(contentSubstring.prefix(byteCount))
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let content = String(trimmed[contentStart..<stringEndIndex])
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // No literal prefix — fall back to heuristic extraction
        return extractFallbackContent(from: afterBody)
    }

    /// Fallback content extraction when no `{NNN}` literal prefix is found.
    ///
    /// Extracts content from after the first newline until the next `BODY[`
    /// marker, closing `)`, or end of string.
    private static func extractFallbackContent(from afterBody: String) -> String? {
        guard let newlineIdx = afterBody.firstIndex(of: "\n") else {
            return nil
        }

        let contentStart = afterBody.index(after: newlineIdx)
        let remaining = String(afterBody[contentStart...])

        // Find the boundary: next BODY[ marker or trailing )
        var content = remaining
        if let nextBodyRange = remaining.range(
            of: "BODY\\[",
            options: [.regularExpression, .caseInsensitive]
        ) {
            content = String(remaining[..<nextBodyRange.lowerBound])
        }

        // Also check for trailing ) that closes the FETCH response
        // Look for ) at the end, possibly preceded by whitespace
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasSuffix(")") {
            content = String(content.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return content.isEmpty ? nil : content
    }

    // MARK: - Extraction Helpers

    /// Extracts UID from a FETCH response.
    static func extractUID(from response: String) -> UInt32 {
        // Pattern: "UID 123" within the FETCH response
        if let range = response.range(of: "UID ", options: .caseInsensitive) {
            let afterUID = response[range.upperBound...]
            let numStr = afterUID.prefix(while: { $0.isNumber })
            return UInt32(numStr) ?? 0
        }
        return 0
    }

    /// Extracts FLAGS from a FETCH response.
    static func extractFlags(from response: String) -> [String] {
        // Pattern: "FLAGS (\Seen \Flagged)" within the FETCH response
        guard let flagsRange = response.range(of: "FLAGS (", options: .caseInsensitive) else {
            return []
        }

        let afterFlags = response[flagsRange.upperBound...]
        guard let closeIdx = afterFlags.firstIndex(of: ")") else {
            return []
        }

        let flagStr = String(afterFlags[..<closeIdx])
        return flagStr.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// Extracts RFC822.SIZE from a FETCH response.
    static func extractSize(from response: String) -> UInt32 {
        if let range = response.range(of: "RFC822.SIZE ", options: .caseInsensitive) {
            let afterSize = response[range.upperBound...]
            let numStr = afterSize.prefix(while: { $0.isNumber })
            return UInt32(numStr) ?? 0
        }
        return 0
    }

    /// Extracts email header fields from the literal portion of a FETCH response.
    ///
    /// The FETCH for headers returns a literal block like:
    /// ```
    /// From: user@example.com
    /// Subject: Hello
    /// Date: Mon, 1 Jan 2024 12:00:00 +0000
    /// ```
    private static func extractHeaderFields(from response: String) -> [String: String] {
        // Find the literal content (after the {NNN}\n delimiter)
        guard let literalStart = response.firstIndex(of: "\n"),
              response.contains("HEADER.FIELDS") || response.contains("header.fields") else {
            return [:]
        }

        let headerText = String(response[response.index(after: literalStart)...])
        var fields: [String: String] = [:]
        var currentKey: String?
        var currentValue: String = ""

        for line in headerText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))

            // Empty line marks end of headers
            if trimmed.isEmpty {
                if let key = currentKey {
                    fields[key.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
                }
                break
            }

            // Continuation line (starts with whitespace)
            if trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t") {
                currentValue += " " + trimmed.trimmingCharacters(in: .whitespaces)
                continue
            }

            // New header field
            if let key = currentKey {
                fields[key.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
            }

            if let colonIdx = trimmed.firstIndex(of: ":") {
                currentKey = String(trimmed[..<colonIdx])
                currentValue = String(trimmed[trimmed.index(after: colonIdx)...])
            }
        }

        // Save last header
        if let key = currentKey {
            fields[key.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
        }

        return fields
    }

    /// Extracts body content from FETCH response literal data.
    ///
    /// Handles `BODY[<partId>]` sections with proper IMAP literal
    /// length parsing to avoid including protocol framing in content.
    private static func extractBodyParts(from response: String) -> [String: String] {
        var parts: [String: String] = [:]

        // Find BODY[...] sections with their literal content
        // Pattern: BODY[1] {NNN}\n<content>
        let scanner = response as NSString
        let searchRange = NSRange(location: 0, length: scanner.length)

        // Look for BODY[<section>] patterns
        let pattern = "BODY\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return parts
        }

        let matches = regex.matches(in: response, options: [], range: searchRange)

        for match in matches {
            let sectionRange = match.range(at: 1)
            let section = scanner.substring(with: sectionRange)

            // Skip HEADER.FIELDS sections (those are headers, not body)
            if section.contains("HEADER") { continue }

            // Find the literal content after this BODY section
            let afterBodyStart = match.range.upperBound
            guard afterBodyStart < scanner.length else { continue }

            let afterBodyRange = NSRange(
                location: afterBodyStart,
                length: scanner.length - afterBodyStart
            )

            // Look for {NNN}\n<content> or NIL
            let afterBody = scanner.substring(with: afterBodyRange)

            if afterBody.trimmingCharacters(in: .whitespaces).hasPrefix("NIL") {
                continue
            }

            if let content = extractLiteralContent(from: afterBody) {
                // Determine content type from section number
                let contentType = determineContentType(section: section, fullResponse: response)
                parts[contentType] = content
            }
        }

        return parts
    }

    /// Determines content type for a body section based on BODYSTRUCTURE.
    ///
    /// For simple cases: section "1" is typically text/plain, "2" is text/html.
    /// For complex structures, we rely on BODYSTRUCTURE info.
    private static func determineContentType(section: String, fullResponse: String) -> String {
        // Check if the response contains BODYSTRUCTURE hints
        let lower = fullResponse.lowercased()

        // Simple heuristic for common Gmail multipart/alternative structure
        if section == "1" || section == "1.1" {
            if lower.contains("\"text\" \"plain\"") || lower.contains("text/plain") {
                return "text/plain"
            }
            return "text/plain" // Default first part is plain
        }

        if section == "2" || section == "1.2" {
            if lower.contains("\"text\" \"html\"") || lower.contains("text/html") {
                return "text/html"
            }
            return "text/html" // Default second part is HTML
        }

        if section == "TEXT" {
            return "text/plain"
        }

        return "text/plain"
    }

    /// Extracts attachment info from BODYSTRUCTURE in a FETCH response.
    private static func extractAttachmentInfo(from response: String) -> [IMAPAttachmentInfo] {
        let bsParts = parseBodyStructure(from: response)
        return bsParts
            .filter { $0.isAttachment }
            .map { part in
                IMAPAttachmentInfo(
                    partId: part.partId,
                    filename: part.filename,
                    mimeType: part.mimeType,
                    sizeBytes: part.size,
                    contentId: part.contentId,
                    transferEncoding: part.encoding
                )
            }
    }

    // MARK: - Private: BODYSTRUCTURE Recursive Parser

    /// Recursively parses BODYSTRUCTURE content.
    ///
    /// Simple part format (RFC 3501):
    ///   `"TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 1234 42 ...`
    ///
    /// Multipart format:
    ///   `(part1)(part2) "ALTERNATIVE" ...`
    private static func parseBodyStructureRecursive(
        _ content: String,
        partPrefix: String,
        parts: inout [BodyPart]
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        // Check if this is a multipart body (starts with "(")
        if trimmed.hasPrefix("(") {
            // Extract child parts
            let children = extractTopLevelParenGroups(trimmed)

            if children.count > 1 {
                // Multipart — extractTopLevelParenGroups only captures
                // parenthesized groups, so the subtype ("ALTERNATIVE" etc.)
                // is NOT included. Process ALL children as body parts.
                for (index, child) in children.enumerated() {
                    let childPrefix: String
                    if partPrefix.isEmpty {
                        childPrefix = "\(index + 1)"
                    } else {
                        childPrefix = "\(partPrefix).\(index + 1)"
                    }
                    parseBodyStructureRecursive(child, partPrefix: childPrefix, parts: &parts)
                }
            } else if children.count == 1 {
                // Single parenthesized group — unwrap and recurse
                parseBodyStructureRecursive(children[0], partPrefix: partPrefix, parts: &parts)
            }
        } else {
            // Simple part — parse as a leaf
            if let part = parseSimpleBodyPart(trimmed, partId: partPrefix.isEmpty ? "1" : partPrefix) {
                parts.append(part)
            }
        }
    }

    /// Parses a simple (non-multipart) body part from BODYSTRUCTURE tokens.
    ///
    /// Token order per RFC 3501:
    /// `"TYPE" "SUBTYPE" (params) content-id description encoding size [lines]`
    ///  idx:  0      1       2        3          4        5      6     7
    private static func parseSimpleBodyPart(_ content: String, partId: String) -> BodyPart? {
        let tokens = tokenizeBodyPart(content)
        guard tokens.count >= 7 else { return nil }

        let type = tokens[0].replacingOccurrences(of: "\"", with: "").uppercased()
        let subtype = tokens[1].replacingOccurrences(of: "\"", with: "").uppercased()
        let mimeType = "\(type)/\(subtype)".lowercased()

        // Token 5 is Content-Transfer-Encoding
        let encoding = tokens[5].replacingOccurrences(of: "\"", with: "").uppercased()

        // Token 2 is the parameter list, e.g. ("CHARSET" "UTF-8")
        let charset = extractCharset(from: tokens[2])

        // Size is at index 6 for text parts
        let size = UInt32(tokens[6].replacingOccurrences(of: "\"", with: "")) ?? 0

        // Check for attachment disposition
        var filename: String?
        var contentId: String?
        var isAttachment = false

        // Look for filename in parameters or disposition
        let joined = content.lowercased()
        if let filenameRange = joined.range(of: "\"filename\" \"") {
            let afterFilename = joined[filenameRange.upperBound...]
            if let endQuote = afterFilename.firstIndex(of: "\"") {
                filename = String(content[filenameRange.upperBound..<endQuote])
            }
        }

        if let nameRange = joined.range(of: "\"name\" \"") {
            let afterName = joined[nameRange.upperBound...]
            if let endQuote = afterName.firstIndex(of: "\"") {
                filename = String(content[nameRange.upperBound..<endQuote])
            }
        }

        // Content-ID
        let cidToken = tokens.count > 3 ? tokens[3] : "NIL"
        if cidToken != "NIL" {
            contentId = cidToken.replacingOccurrences(of: "\"", with: "")
        }

        // Determine if this is an attachment.
        // Important: do NOT treat plain inline text body parts as attachments.
        let hasAttachmentDisposition = joined.contains("\"attachment\"")
        let hasInlineDisposition = joined.contains("\"inline\"")
        if hasAttachmentDisposition {
            isAttachment = true
        } else if hasInlineDisposition {
            isAttachment = filename != nil || !mimeType.hasPrefix("text/")
        }
        if filename != nil {
            isAttachment = true
        }

        return BodyPart(
            partId: partId,
            mimeType: mimeType,
            filename: filename,
            size: size,
            contentId: contentId,
            isAttachment: isAttachment,
            encoding: encoding,
            charset: charset
        )
    }

    /// Extracts charset from a BODYSTRUCTURE parameter token.
    ///
    /// Input: `("CHARSET" "UTF-8" "FORMAT" "flowed")`
    /// Output: `"UTF-8"`
    private static func extractCharset(from paramToken: String) -> String {
        let upper = paramToken.uppercased()
        guard let range = upper.range(of: "\"CHARSET\"") else {
            return "UTF-8" // Default per RFC 2045
        }

        // Find the quoted value after "CHARSET"
        let afterCharset = paramToken[range.upperBound...]
        // Skip whitespace
        let trimmed = afterCharset.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.first == "\"" else { return "UTF-8" }

        let afterQuote = trimmed.dropFirst() // skip opening "
        if let endQuote = afterQuote.firstIndex(of: "\"") {
            return String(afterQuote[..<endQuote])
        }
        return "UTF-8"
    }

    // MARK: - Private: Tokenization Helpers

    /// Tokenizes a BODYSTRUCTURE simple part into atoms, strings, and NIL values.
    private static func tokenizeBodyPart(_ content: String) -> [String] {
        var tokens: [String] = []
        var index = content.startIndex
        let end = content.endIndex

        while index < end {
            let char = content[index]

            if char == "\"" {
                // Quoted string
                var str = "\""
                index = content.index(after: index)
                while index < end && content[index] != "\"" {
                    str.append(content[index])
                    index = content.index(after: index)
                }
                str.append("\"")
                if index < end { index = content.index(after: index) }
                tokens.append(str)
            } else if char == "(" {
                // Skip parenthesized groups (parameters, extensions)
                var depth = 1
                var group = "("
                index = content.index(after: index)
                while index < end && depth > 0 {
                    let c = content[index]
                    group.append(c)
                    if c == "(" { depth += 1 }
                    if c == ")" { depth -= 1 }
                    index = content.index(after: index)
                }
                tokens.append(group)
            } else if char == " " || char == "\t" || char == "\r" || char == "\n" {
                index = content.index(after: index)
            } else {
                // Atom (NIL, number, etc.)
                var atom = ""
                while index < end && content[index] != " " && content[index] != ")"
                        && content[index] != "(" && content[index] != "\"" {
                    atom.append(content[index])
                    index = content.index(after: index)
                }
                tokens.append(atom)
            }
        }

        return tokens
    }

    /// Extracts top-level parenthesized groups from a string.
    ///
    /// Input: `(group1)(group2) "ALTERNATIVE"`
    /// Output: `["group1", "group2"]`
    private static func extractTopLevelParenGroups(_ content: String) -> [String] {
        var groups: [String] = []
        var index = content.startIndex
        let end = content.endIndex

        while index < end {
            if content[index] == "(" {
                var depth = 1
                var group = ""
                index = content.index(after: index)

                while index < end && depth > 0 {
                    let char = content[index]
                    if char == "(" { depth += 1 }
                    if char == ")" { depth -= 1 }
                    if depth > 0 { group.append(char) }
                    index = content.index(after: index)
                }

                groups.append(group)
            } else {
                index = content.index(after: index)
            }
        }

        return groups
    }

    /// Extracts the content between the first matching pair of parentheses.
    private static func extractParenContent(_ text: String) -> String? {
        guard let openIdx = text.firstIndex(of: "(") else { return nil }

        var depth = 1
        var index = text.index(after: openIdx)
        let end = text.endIndex

        while index < end && depth > 0 {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" { depth -= 1 }
            if depth > 0 { index = text.index(after: index) }
        }

        if depth == 0 {
            return String(text[text.index(after: openIdx)..<index])
        }
        return nil
    }

    // MARK: - Private: Address & Date Parsing

    /// Parses a comma-separated address list.
    ///
    /// Input: `"user1@test.com, User Two <user2@test.com>"`
    /// Output: `["user1@test.com", "User Two <user2@test.com>"]`
    private static func parseAddressList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses an IMAP date string into a `Date`.
    ///
    /// Handles common formats:
    /// - RFC 2822: "Mon, 1 Jan 2024 12:00:00 +0000"
    /// - IMAP internal: "01-Jan-2024 12:00:00 +0000"
    private static func parseIMAPDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Uses static formatters — allocated once, not per call
        let formatters = [rfc2822Formatter, shortDateFormatter, imapInternalDateFormatter]

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    /// Parses quoted parts from an IMAP response string.
    ///
    /// Input: `"/" "[Gmail]/Sent Mail"`
    /// Output: `["/", "[Gmail]/Sent Mail"]`
    private static func parseQuotedParts(_ text: String) -> [String] {
        var parts: [String] = []
        var index = text.startIndex
        let end = text.endIndex

        while index < end {
            if text[index] == "\"" {
                // Start of quoted string
                index = text.index(after: index)
                var str = ""
                while index < end && text[index] != "\"" {
                    str.append(text[index])
                    index = text.index(after: index)
                }
                if index < end { index = text.index(after: index) } // skip closing quote
                parts.append(str)
            } else if text[index] == " " {
                // Skip whitespace
                index = text.index(after: index)
            } else {
                // Unquoted token (NIL, or unquoted folder name like INBOX)
                var token = ""
                while index < end && text[index] != " " && text[index] != "\"" {
                    token.append(text[index])
                    index = text.index(after: index)
                }
                if !token.isEmpty {
                    parts.append(token)
                }
            }
        }

        return parts
    }

    /// Extracts folder display name from IMAP path.
    ///
    /// "[Gmail]/Sent Mail" → "Sent Mail"
    /// "INBOX" → "INBOX"
    /// "Work/Projects" → "Projects"
    private static func extractFolderName(from path: String) -> String {
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[path.index(after: lastSlash)...])
        }
        return path
    }
}
