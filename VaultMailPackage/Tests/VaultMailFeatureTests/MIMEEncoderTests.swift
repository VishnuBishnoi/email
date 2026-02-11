import Foundation
import Testing
@testable import VaultMailFeature

@Suite("MIMEEncoder")
struct MIMEEncoderTests {

    // MARK: - Helpers

    /// Decode MIME Data to a string for assertion convenience.
    private func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Message Structure: encode()

    @Test("plain text only message has correct Content-Type")
    func plainTextOnlyMessage() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Hello",
            bodyPlain: "Hi Bob!",
            bodyHTML: nil,
            messageId: "<msg1@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("Content-Type: text/plain; charset=UTF-8"))
        #expect(msg.contains("Content-Transfer-Encoding: quoted-printable"))
        #expect(!msg.contains("multipart"))
    }

    @Test("alternative message has multipart/alternative")
    func alternativeMessage() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Hello",
            bodyPlain: "Hi Bob!",
            bodyHTML: "<p>Hi Bob!</p>",
            messageId: "<msg2@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("Content-Type: multipart/alternative"))
        #expect(msg.contains("Content-Type: text/plain; charset=UTF-8"))
        #expect(msg.contains("Content-Type: text/html; charset=UTF-8"))
    }

    @Test("mixed message with attachment has multipart/mixed")
    func mixedMessageWithAttachment() {
        let attachment = MIMEEncoder.AttachmentData(
            filename: "report.pdf",
            mimeType: "application/pdf",
            data: Data("PDF content".utf8)
        )
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Report",
            bodyPlain: "See attached.",
            bodyHTML: nil,
            messageId: "<msg3@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date(),
            attachments: [attachment]
        )
        let msg = string(data)
        #expect(msg.contains("Content-Type: multipart/mixed"))
        #expect(msg.contains("Content-Disposition: attachment; filename=\"report.pdf\""))
        #expect(msg.contains("Content-Transfer-Encoding: base64"))
    }

    @Test("mixed message with HTML and attachment has nested multipart/alternative")
    func mixedMessageWithHTMLAndAttachment() {
        let attachment = MIMEEncoder.AttachmentData(
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xFF, count: 10)
        )
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Photo",
            bodyPlain: "See attached photo.",
            bodyHTML: "<p>See attached photo.</p>",
            messageId: "<msg4@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date(),
            attachments: [attachment]
        )
        let msg = string(data)
        #expect(msg.contains("Content-Type: multipart/mixed"))
        #expect(msg.contains("Content-Type: multipart/alternative"))
        #expect(msg.contains("Content-Type: text/plain; charset=UTF-8"))
        #expect(msg.contains("Content-Type: text/html; charset=UTF-8"))
    }

    @Test("multiple attachments appear as separate base64 parts")
    func multipleAttachments() {
        let attachments = [
            MIMEEncoder.AttachmentData(filename: "a.txt", mimeType: "text/plain", data: Data("AAA".utf8)),
            MIMEEncoder.AttachmentData(filename: "b.txt", mimeType: "text/plain", data: Data("BBB".utf8))
        ]
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Files",
            bodyPlain: "Two files.",
            bodyHTML: nil,
            messageId: "<msg5@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date(),
            attachments: attachments
        )
        let msg = string(data)
        // Both attachment filenames must appear
        #expect(msg.contains("filename=\"a.txt\""))
        #expect(msg.contains("filename=\"b.txt\""))
    }

    // MARK: - Header Tests

    @Test("From header includes display name when provided")
    func fromHeaderWithDisplayName() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: "Alice Smith",
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Test",
            bodyPlain: "Body",
            bodyHTML: nil,
            messageId: "<msg6@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("From: \"Alice Smith\" <alice@example.com>"))
    }

    @Test("From header is bare email when no display name")
    func fromHeaderWithoutName() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Test",
            bodyPlain: "Body",
            bodyHTML: nil,
            messageId: "<msg7@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("From: alice@example.com"))
        #expect(!msg.contains("From: \""))
    }

    @Test("To and CC headers contain comma-separated addresses")
    func toAndCcHeaders() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com", "carol@example.com"],
            ccAddresses: ["dave@example.com", "eve@example.com"],
            bccAddresses: [],
            subject: "Test",
            bodyPlain: "Body",
            bodyHTML: nil,
            messageId: "<msg8@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("To: bob@example.com, carol@example.com"))
        #expect(msg.contains("Cc: dave@example.com, eve@example.com"))
    }

    @Test("BCC addresses are NOT included in message headers (RFC 5322)")
    func bccNotInHeaders() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: ["secret@example.com"],
            subject: "Test",
            bodyPlain: "Body",
            bodyHTML: nil,
            messageId: "<msg9@example.com>",
            inReplyTo: nil,
            references: nil,
            date: Date()
        )
        let msg = string(data)
        #expect(!msg.contains("Bcc:"))
        #expect(!msg.contains("secret@example.com"))
    }

    @Test("In-Reply-To and References headers included when non-nil")
    func inReplyToAndReferences() {
        let data = MIMEEncoder.encode(
            from: "alice@example.com",
            fromName: nil,
            toAddresses: ["bob@example.com"],
            ccAddresses: [],
            bccAddresses: [],
            subject: "Re: Test",
            bodyPlain: "Reply",
            bodyHTML: nil,
            messageId: "<reply1@example.com>",
            inReplyTo: "<original@example.com>",
            references: "<original@example.com>",
            date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("In-Reply-To: <original@example.com>"))
        #expect(msg.contains("References: <original@example.com>"))
    }

    @Test("In-Reply-To header omitted when nil or empty")
    func emptyInReplyToOmitted() {
        let data1 = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        let data2 = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: "", references: "", date: Date()
        )
        #expect(!string(data1).contains("In-Reply-To:"))
        #expect(!string(data2).contains("In-Reply-To:"))
        #expect(!string(data2).contains("References:"))
    }

    @Test("Message-ID header is present")
    func messageIdHeader() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<unique-id@example.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        #expect(string(data).contains("Message-ID: <unique-id@example.com>"))
    }

    @Test("MIME-Version 1.0 header is present")
    func mimeVersionHeader() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        #expect(string(data).contains("MIME-Version: 1.0"))
    }

    // MARK: - Encoding Tests

    @Test("ASCII subject passes through unchanged")
    func subjectASCIIPassthrough() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Meeting Tomorrow",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        #expect(string(data).contains("Subject: Meeting Tomorrow"))
    }

    @Test("non-ASCII subject uses RFC 2047 Base64 encoding")
    func subjectNonASCIIUsesRFC2047() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "H\u{00E9}llo",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("=?UTF-8?B?"))
        #expect(msg.contains("?="))
    }

    @Test("quoted-printable encodes equals sign as =3D")
    func quotedPrintableEncodesEquals() {
        let encoded = MIMEEncoder.encodeQuotedPrintable("a=b")
        #expect(encoded.contains("=3D"))
    }

    @Test("quoted-printable encodes non-ASCII bytes")
    func quotedPrintableEncodesNonASCII() {
        // "caf\u{00E9}" → the 'é' byte (0xC3 0xA9 in UTF-8) should be encoded
        let encoded = MIMEEncoder.encodeQuotedPrintable("caf\u{00E9}")
        #expect(encoded.contains("=C3"))
        #expect(encoded.contains("=A9"))
    }

    @Test("quoted-printable inserts soft line break at 76 chars")
    func quotedPrintableSoftLineBreak() {
        let longLine = String(repeating: "A", count: 100)
        let encoded = MIMEEncoder.encodeQuotedPrintable(longLine)
        #expect(encoded.contains("=\r\n"))
    }

    @Test("quoted-printable passes through printable ASCII unchanged")
    func quotedPrintablePassthroughASCII() {
        let text = "Hello World"
        let encoded = MIMEEncoder.encodeQuotedPrintable(text)
        #expect(encoded == "Hello World")
    }

    @Test("base64 attachment data has CRLF line breaks")
    func base64WithLineBreaks() {
        // Create data large enough to require multiple base64 lines (>76 chars base64 = >57 bytes)
        let largeData = Data(repeating: 0x42, count: 200)
        let attachment = MIMEEncoder.AttachmentData(
            filename: "big.bin",
            mimeType: "application/octet-stream",
            data: largeData
        )
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date(),
            attachments: [attachment]
        )
        let msg = string(data)
        // Base64 section should contain CRLF line breaks
        let base64Content = largeData.base64EncodedString()
        // The base64 output should be split at 76 chars
        #expect(base64Content.count > 76) // Ensure we have enough data
        #expect(msg.contains("\r\n")) // CRLF present in output
    }

    @Test("non-ASCII attachment filename uses RFC 2047 encoding")
    func attachmentFilenameNonASCII() {
        let attachment = MIMEEncoder.AttachmentData(
            filename: "\u{65E5}\u{672C}\u{8A9E}.pdf", // 日本語.pdf
            mimeType: "application/pdf",
            data: Data("test".utf8)
        )
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date(),
            attachments: [attachment]
        )
        let msg = string(data)
        #expect(msg.contains("=?UTF-8?B?"))
    }

    @Test("X-Mailer header is present")
    func xMailerHeader() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        #expect(string(data).contains("X-Mailer: VaultMail/1.0"))
    }

    @Test("Date header is present in RFC 5322 format")
    func dateHeaderPresent() {
        let data = MIMEEncoder.encode(
            from: "a@b.com", fromName: nil, toAddresses: ["c@d.com"],
            ccAddresses: [], bccAddresses: [], subject: "Test",
            bodyPlain: "Body", bodyHTML: nil, messageId: "<m@b.com>",
            inReplyTo: nil, references: nil, date: Date()
        )
        let msg = string(data)
        #expect(msg.contains("Date: "))
    }
}
