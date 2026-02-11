import Foundation

/// Encodes email fields into an RFC 2822 MIME message for SMTP transmission.
///
/// Handles:
/// - Header encoding (From, To, CC, BCC, Subject, Date, Message-ID, etc.)
/// - Plain text body encoding
/// - Multipart/alternative for plain+HTML bodies
/// - Multipart/mixed for messages with attachments (Base64-encoded)
/// - RFC 2047 encoded-word for non-ASCII subjects/names
/// - Proper CRLF line endings per RFC 5322
///
/// Spec ref: Email Composer spec FR-COMP-02
enum MIMEEncoder {

    /// Attachment data for MIME encoding.
    struct AttachmentData: Sendable {
        /// Original filename
        let filename: String
        /// MIME type (e.g., "application/pdf", "image/jpeg")
        let mimeType: String
        /// Raw file data
        let data: Data
    }

    /// Encodes an email into a complete RFC 2822 MIME message.
    ///
    /// - Parameters:
    ///   - from: Sender email address
    ///   - fromName: Optional sender display name
    ///   - toAddresses: To recipient email addresses
    ///   - ccAddresses: CC recipient email addresses
    ///   - bccAddresses: BCC recipient email addresses (included in envelope, not headers)
    ///   - subject: Email subject
    ///   - bodyPlain: Plain text body
    ///   - bodyHTML: Optional HTML body (if both provided, creates multipart/alternative)
    ///   - messageId: RFC 2822 Message-ID
    ///   - inReplyTo: Optional In-Reply-To header
    ///   - references: Optional References header
    ///   - date: Send date
    ///   - attachments: File attachments to include (default: empty)
    /// - Returns: Raw MIME message data for SMTP DATA command
    static func encode(
        from: String,
        fromName: String?,
        toAddresses: [String],
        ccAddresses: [String],
        bccAddresses: [String],
        subject: String,
        bodyPlain: String,
        bodyHTML: String?,
        messageId: String,
        inReplyTo: String?,
        references: String?,
        date: Date,
        attachments: [AttachmentData] = []
    ) -> Data {
        var headers: [String] = []

        // Date header (RFC 5322 format)
        headers.append("Date: \(formatRFC5322Date(date))")

        // From header
        headers.append("From: \(formatAddress(email: from, name: fromName))")

        // To header
        if !toAddresses.isEmpty {
            headers.append("To: \(toAddresses.map { formatAddress(email: $0, name: nil) }.joined(separator: ", "))")
        }

        // CC header (visible to all recipients)
        if !ccAddresses.isEmpty {
            headers.append("Cc: \(ccAddresses.map { formatAddress(email: $0, name: nil) }.joined(separator: ", "))")
        }

        // BCC is NOT included in headers per RFC 5322 §3.6.3
        // BCC recipients are only in the SMTP envelope (RCPT TO)

        // Subject header
        headers.append("Subject: \(encodeSubject(subject))")

        // Message-ID header
        headers.append("Message-ID: \(messageId)")

        // In-Reply-To header
        if let inReplyTo, !inReplyTo.isEmpty {
            headers.append("In-Reply-To: \(inReplyTo)")
        }

        // References header
        if let references, !references.isEmpty {
            headers.append("References: \(references)")
        }

        // MIME version
        headers.append("MIME-Version: 1.0")

        // User-Agent
        headers.append("X-Mailer: VaultMail/1.0")

        // Build body based on content type and attachments
        if !attachments.isEmpty {
            // multipart/mixed: text body (or multipart/alternative) + attachments
            return buildMixedMessage(
                headers: headers,
                bodyPlain: bodyPlain,
                bodyHTML: bodyHTML,
                attachments: attachments
            )
        } else if let bodyHTML, !bodyHTML.isEmpty {
            // multipart/alternative: plain + HTML (no attachments)
            return buildAlternativeMessage(headers: headers, bodyPlain: bodyPlain, bodyHTML: bodyHTML)
        } else {
            // Simple text/plain message
            return buildPlainMessage(headers: headers, bodyPlain: bodyPlain)
        }
    }

    // MARK: - Message Builders

    /// Builds a simple text/plain message with no attachments.
    private static func buildPlainMessage(headers: [String], bodyPlain: String) -> Data {
        var hdrs = headers
        hdrs.append("Content-Type: text/plain; charset=UTF-8")
        hdrs.append("Content-Transfer-Encoding: quoted-printable")

        let headerBlock = hdrs.joined(separator: "\r\n")
        let message = "\(headerBlock)\r\n\r\n\(encodeQuotedPrintable(bodyPlain))\r\n"
        return Data(message.utf8)
    }

    /// Builds a multipart/alternative message (plain + HTML, no attachments).
    private static func buildAlternativeMessage(
        headers: [String],
        bodyPlain: String,
        bodyHTML: String
    ) -> Data {
        var hdrs = headers
        let boundary = generateBoundary()
        hdrs.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"")

        let headerBlock = hdrs.joined(separator: "\r\n")
        var message = "\(headerBlock)\r\n\r\n"

        // Plain text part
        message += "--\(boundary)\r\n"
        message += "Content-Type: text/plain; charset=UTF-8\r\n"
        message += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
        message += encodeQuotedPrintable(bodyPlain)
        message += "\r\n"

        // HTML part
        message += "--\(boundary)\r\n"
        message += "Content-Type: text/html; charset=UTF-8\r\n"
        message += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
        message += encodeQuotedPrintable(bodyHTML)
        message += "\r\n"

        // Close boundary
        message += "--\(boundary)--\r\n"

        return Data(message.utf8)
    }

    /// Builds a multipart/mixed message with text body + file attachments.
    ///
    /// Structure:
    /// ```
    /// multipart/mixed
    /// ├── text/plain (or multipart/alternative if HTML exists)
    /// ├── attachment 1 (Base64)
    /// └── attachment 2 (Base64)
    /// ```
    private static func buildMixedMessage(
        headers: [String],
        bodyPlain: String,
        bodyHTML: String?,
        attachments: [AttachmentData]
    ) -> Data {
        var hdrs = headers
        let mixedBoundary = generateBoundary()
        hdrs.append("Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"")

        let headerBlock = hdrs.joined(separator: "\r\n")
        var message = "\(headerBlock)\r\n\r\n"

        // Text body part
        if let bodyHTML, !bodyHTML.isEmpty {
            // Nested multipart/alternative for plain + HTML
            let altBoundary = generateBoundary()

            message += "--\(mixedBoundary)\r\n"
            message += "Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"\r\n\r\n"

            // Plain text sub-part
            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/plain; charset=UTF-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
            message += encodeQuotedPrintable(bodyPlain)
            message += "\r\n"

            // HTML sub-part
            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/html; charset=UTF-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
            message += encodeQuotedPrintable(bodyHTML)
            message += "\r\n"

            message += "--\(altBoundary)--\r\n"
        } else {
            // Simple text/plain part
            message += "--\(mixedBoundary)\r\n"
            message += "Content-Type: text/plain; charset=UTF-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
            message += encodeQuotedPrintable(bodyPlain)
            message += "\r\n"
        }

        // Attachment parts
        for attachment in attachments {
            message += "--\(mixedBoundary)\r\n"
            message += "Content-Type: \(attachment.mimeType); name=\"\(encodeAttachmentFilename(attachment.filename))\"\r\n"
            message += "Content-Disposition: attachment; filename=\"\(encodeAttachmentFilename(attachment.filename))\"\r\n"
            message += "Content-Transfer-Encoding: base64\r\n\r\n"
            message += encodeBase64WithLineBreaks(attachment.data)
            message += "\r\n"
        }

        // Close mixed boundary
        message += "--\(mixedBoundary)--\r\n"

        return Data(message.utf8)
    }

    // MARK: - Date Formatting

    /// Cached formatter for RFC 5322 dates.
    /// `DateFormatter` init is expensive; reusing a single instance avoids
    /// allocating one per email (review comment #7).
    private static let rfc5322Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Formats a date per RFC 5322 §3.3.
    /// Example: "Mon, 14 Nov 2023 10:30:00 +0000"
    private static func formatRFC5322Date(_ date: Date) -> String {
        rfc5322Formatter.string(from: date)
    }

    // MARK: - Address Formatting

    /// Formats an email address with optional display name.
    /// Example: "John Doe <john@example.com>" or "john@example.com"
    private static func formatAddress(email: String, name: String?) -> String {
        if let name, !name.isEmpty {
            let encodedName = encodeHeaderWord(name)
            return "\(encodedName) <\(email)>"
        }
        return email
    }

    // MARK: - Subject Encoding

    /// Encodes a subject line, using RFC 2047 encoded-word if needed.
    private static func encodeSubject(_ subject: String) -> String {
        if subject.allSatisfy({ $0.isASCII }) {
            return subject
        }
        return encodeRFC2047(subject)
    }

    /// Encodes a header value using RFC 2047 encoded-word syntax.
    /// Uses Base64 encoding for simplicity: =?UTF-8?B?<base64>?=
    private static func encodeHeaderWord(_ value: String) -> String {
        if value.allSatisfy({ $0.isASCII && !value.contains("\"") }) {
            return "\"\(value)\""
        }
        return encodeRFC2047(value)
    }

    /// RFC 2047 Base64 encoded-word.
    private static func encodeRFC2047(_ value: String) -> String {
        let data = Data(value.utf8)
        let base64 = data.base64EncodedString()
        return "=?UTF-8?B?\(base64)?="
    }

    // MARK: - Attachment Filename Encoding

    /// Encodes a filename for use in Content-Type/Content-Disposition headers.
    /// Uses RFC 2047 if non-ASCII characters are present.
    private static func encodeAttachmentFilename(_ filename: String) -> String {
        if filename.allSatisfy({ $0.isASCII }) {
            return filename
        }
        return encodeRFC2047(filename)
    }

    // MARK: - Base64 Encoding

    /// Encodes data as Base64 with CRLF line breaks every 76 characters per RFC 2045.
    private static func encodeBase64WithLineBreaks(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        var result = ""
        var index = base64.startIndex

        while index < base64.endIndex {
            let endIndex = base64.index(index, offsetBy: 76, limitedBy: base64.endIndex) ?? base64.endIndex
            result += base64[index..<endIndex]
            if endIndex < base64.endIndex {
                result += "\r\n"
            }
            index = endIndex
        }

        return result
    }

    // MARK: - Quoted-Printable Encoding

    /// Encodes text using quoted-printable encoding per RFC 2045 §6.7.
    ///
    /// Rules:
    /// - Lines must not exceed 76 characters
    /// - Non-printable characters encoded as =XX
    /// - Soft line breaks: "=\r\n"
    /// - Literal "=" encoded as "=3D"
    static func encodeQuotedPrintable(_ text: String) -> String {
        var result = ""
        var lineLength = 0

        for byte in Data(text.utf8) {
            let char = Character(UnicodeScalar(byte))

            // Check if we need a soft line break (max 76 chars per line)
            let encoded: String
            if byte == 0x0D || byte == 0x0A {
                // Pass through CR/LF as-is
                encoded = String(char)
                if byte == 0x0A {
                    lineLength = 0
                }
                result.append(encoded)
                continue
            } else if byte == 0x3D {
                // Encode '=' as =3D
                encoded = "=3D"
            } else if byte == 0x09 || (byte >= 0x20 && byte <= 0x7E) {
                // Printable ASCII and tab — pass through
                encoded = String(char)
            } else {
                // Non-ASCII or control — encode as =XX
                encoded = String(format: "=%02X", byte)
            }

            // Soft line break if needed
            if lineLength + encoded.count > 75 {
                result.append("=\r\n")
                lineLength = 0
            }

            result.append(encoded)
            lineLength += encoded.count
        }

        return result
    }

    // MARK: - Boundary

    /// Generates a unique MIME boundary string.
    private static func generateBoundary() -> String {
        "----=_VaultMail_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }
}
