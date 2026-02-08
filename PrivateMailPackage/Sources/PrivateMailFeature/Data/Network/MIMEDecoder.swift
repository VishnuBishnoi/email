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
