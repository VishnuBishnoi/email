import Testing
@testable import VaultMailFeature

@Suite("MIMEDecoder - Multipart Parsing")
struct MIMEDecoderMultipartTests {

    // MARK: - isMultipartContent

    @Test("Detects MIME preamble text")
    func detectsMIMEPreamble() {
        let content = """
        This is a multi-part message in MIME format.
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/plain; charset="utf-8"

        Hello World
        """
        #expect(MIMEDecoder.isMultipartContent(content) == true)
    }

    @Test("Detects Content-Type with boundary pattern")
    func detectsContentTypeWithBoundary() {
        let content = """
        Content-Type: multipart/alternative; boundary="----=_Part_123"

        ------=_Part_123
        Content-Type: text/plain

        Hello
        """
        #expect(MIMEDecoder.isMultipartContent(content) == true)
    }

    @Test("Does not flag normal plain text as multipart")
    func normalTextNotMultipart() {
        let content = "Hello, this is a normal email message with no MIME content."
        #expect(MIMEDecoder.isMultipartContent(content) == false)
    }

    @Test("Does not flag normal HTML as multipart")
    func normalHTMLNotMultipart() {
        let content = "<html><body><p>Hello World</p></body></html>"
        #expect(MIMEDecoder.isMultipartContent(content) == false)
    }

    // MARK: - parseMultipartBody

    @Test("Parses multipart with plain text and HTML parts")
    func parsesPlainAndHTML() {
        let content = """
        This is a multi-part message in MIME format.
        --boundary123
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Hello World plain text
        --boundary123
        Content-Type: text/html; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        <html><body><p>Hello World HTML</p></body></html>
        --boundary123--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Hello World plain text")
        #expect(result?.htmlText?.contains("Hello World HTML") == true)
    }

    @Test("Parses multipart with quoted-printable encoding")
    func parsesQuotedPrintable() {
        let content = """
        This is a multi-part message in MIME format.
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/plain; charset="utf-8"

        Hello=20World=20with=20spaces
        --_----------=_17707125376946517--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Hello World with spaces")
    }

    @Test("Parses multipart with base64 encoding")
    func parsesBase64() {
        // "Hello World" in base64
        let content = """
        This is a multi-part message in MIME format.
        --boundary456
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: base64

        SGVsbG8gV29ybGQ=
        --boundary456--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Hello World")
    }

    @Test("Returns nil for non-multipart content")
    func returnsNilForNonMultipart() {
        let content = "Just a plain text email with no MIME boundaries"
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result == nil)
    }

    @Test("Parses real Axis Bank-style email structure")
    func parsesAxisBankStyle() {
        let content = """
        This is a multi-part message in MIME format.
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/plain; charset="utf-8"

        =20=20=20=20Dear Customer,=0A=0AYour account has been credited.
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Dear Customer,</p><p>Your account has been credited.</p></body></html>
        --_----------=_17707125376946517--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText?.contains("Dear Customer") == true)
        #expect(result?.htmlText?.contains("Dear Customer") == true)
    }

    @Test("Handles Content-Type boundary parameter in header")
    func handlesContentTypeBoundary() {
        let content = """
        Content-Type: multipart/alternative; boundary="----=_Part_ABC"

        ------=_Part_ABC
        Content-Type: text/plain

        Plain text content
        ------=_Part_ABC
        Content-Type: text/html

        <p>HTML content</p>
        ------=_Part_ABC--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Plain text content")
        #expect(result?.htmlText?.contains("HTML content") == true)
    }

    // MARK: - stripMIMEFraming

    @Test("Strips MIME framing from plain text, returns decoded content")
    func stripsMIMEFramingPlainText() {
        let content = """
        This is a multi-part message in MIME format.
        --boundary789
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Actual email content here
        --boundary789--
        """
        let result = MIMEDecoder.stripMIMEFraming(content)
        #expect(result == "Actual email content here")
    }

    @Test("Returns original text when no MIME framing detected")
    func preservesNonMIMEText() {
        let content = "Just a regular email with no MIME content."
        let result = MIMEDecoder.stripMIMEFraming(content)
        #expect(result == content)
    }

    @Test("Strips MIME framing and prefers plain text")
    func stripsMIMEPreferPlainText() {
        let content = """
        This is a multi-part message in MIME format.
        --boundary_prefer
        Content-Type: text/plain

        Plain version
        --boundary_prefer
        Content-Type: text/html

        <p>HTML version</p>
        --boundary_prefer--
        """
        let result = MIMEDecoder.stripMIMEFraming(content)
        #expect(result == "Plain version")
    }

    // MARK: - stripMIMEFramingForHTML

    @Test("Strips MIME framing for HTML, prefers HTML part")
    func stripsMIMEForHTML() {
        let content = """
        This is a multi-part message in MIME format.
        --boundary_html
        Content-Type: text/plain

        Plain version
        --boundary_html
        Content-Type: text/html

        <p>HTML version</p>
        --boundary_html--
        """
        let result = MIMEDecoder.stripMIMEFramingForHTML(content)
        #expect(result.contains("<p>HTML version</p>"))
    }

    @Test("Returns original HTML when no MIME framing detected")
    func preservesNonMIMEHTML() {
        let html = "<html><body><p>Normal email</p></body></html>"
        let result = MIMEDecoder.stripMIMEFramingForHTML(html)
        #expect(result == html)
    }

    // MARK: - Quoted-Printable in multipart

    @Test("Decodes multi-line quoted-printable with soft line breaks")
    func decodesMultiLineQP() {
        let content = """
        This is a multi-part message in MIME format.
        --qptest
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: quoted-printable

        This is a long line that has been wrapped with soft=\r\n line breaks for transport.
        --qptest--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText?.contains("soft line breaks") == true)
        #expect(result?.plainText?.contains("=\r\n") == false)
    }

    // MARK: - Edge Cases

    @Test("Handles multipart with only HTML part")
    func handlesHTMLOnlyMultipart() {
        let content = """
        This is a multi-part message in MIME format.
        --htmlonly
        Content-Type: text/html; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        <html><body><p>Only HTML here</p></body></html>
        --htmlonly--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == nil)
        #expect(result?.htmlText?.contains("Only HTML here") == true)
    }

    @Test("Handles multipart with only plain text part")
    func handlesPlainOnlyMultipart() {
        let content = """
        This is a multi-part message in MIME format.
        --plainonly
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Only plain text here
        --plainonly--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Only plain text here")
        #expect(result?.htmlText == nil)
    }

    @Test("Handles boundary with equals signs and underscores")
    func handlesBoundaryWithSpecialChars() {
        let content = """
        This is a multi-part message in MIME format.
        --_----------=_17707125376946517
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Content with unusual boundary
        --_----------=_17707125376946517--
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Content with unusual boundary")
    }

    @Test("Handles trailing IMAP closing paren in stored content")
    func handlesTrailingIMAPParen() {
        let content = """
        This is a multi-part message in MIME format.
        --boundary_imap
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Email content from IMAP
        --boundary_imap
        Content-Type: text/html; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        <p>HTML content from IMAP</p>
        --boundary_imap--
        )
        """
        let result = MIMEDecoder.parseMultipartBody(content)
        #expect(result != nil)
        #expect(result?.plainText == "Email content from IMAP")
        #expect(result?.htmlText?.contains("HTML content from IMAP") == true)
        // Ensure closing paren is not in the content
        #expect(result?.plainText?.contains(")") == false)
    }

    @Test("stripMIMEFraming does not return lone ) for IMAP-contaminated content")
    func stripMIMEFramingNoLoneParen() {
        // Simulates stored content where the IMAP closing paren was included
        let content = """
        This is a multi-part message in MIME format.
        --boundary_paren
        Content-Type: text/plain; charset="utf-8"
        Content-Transfer-Encoding: 7bit

        Actual email content
        --boundary_paren--
        )
        """
        let result = MIMEDecoder.stripMIMEFraming(content)
        #expect(result != ")")
        #expect(result.contains("Actual email content"))
    }

    @Test("processMultipartBody extracts HTML for WebView rendering from bodyPlain")
    func extractsHTMLFromBodyPlain() {
        // This simulates the Axis Bank scenario: bodyHTML=nil, bodyPlain=raw MIME
        let bodyPlain = """
        This is a multi-part message in MIME format.
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/plain; charset="utf-8"

        Dear Customer, your transaction of INR 299
        --_----------=_17707125376946517
        Content-Disposition: inline
        Content-Transfer-Encoding: quoted-printable
        Content-Type: text/html; charset="utf-8"

        <html><body><p>Dear Customer, your transaction of INR 299</p></body></html>
        --_----------=_17707125376946517--
        """
        // The MIME parser should find the HTML part
        #expect(MIMEDecoder.isMultipartContent(bodyPlain) == true)
        let result = MIMEDecoder.parseMultipartBody(bodyPlain)
        #expect(result != nil)
        #expect(result?.htmlText?.contains("transaction of INR 299") == true)
        #expect(result?.plainText?.contains("Dear Customer") == true)
    }
}

@Suite("MIMEDecoder - Existing Functionality")
struct MIMEDecoderExistingTests {

    // MARK: - Header Decoding

    @Test("Decodes RFC 2047 Q-encoded header")
    func decodesQEncodedHeader() {
        let input = "=?UTF-8?Q?Hello=20World?="
        let result = MIMEDecoder.decodeHeaderValue(input)
        #expect(result == "Hello World")
    }

    @Test("Decodes RFC 2047 B-encoded header")
    func decodesBEncodedHeader() {
        // "Hello World" in base64
        let input = "=?UTF-8?B?SGVsbG8gV29ybGQ=?="
        let result = MIMEDecoder.decodeHeaderValue(input)
        #expect(result == "Hello World")
    }

    @Test("Passes through non-encoded headers")
    func passesThroughPlainHeaders() {
        let input = "Just a regular subject"
        let result = MIMEDecoder.decodeHeaderValue(input)
        #expect(result == input)
    }

    // MARK: - Body Decoding

    @Test("Decodes base64 body content")
    func decodesBase64Body() {
        // "Hello World" in base64 with line wrapping
        let input = "SGVsbG8g\nV29ybGQ="
        let result = MIMEDecoder.decodeBody(input, encoding: "BASE64", charset: "UTF-8")
        #expect(result == "Hello World")
    }

    @Test("Decodes quoted-printable body content")
    func decodesQPBody() {
        let input = "Hello=20World"
        let result = MIMEDecoder.decodeBody(input, encoding: "QUOTED-PRINTABLE", charset: "UTF-8")
        #expect(result == "Hello World")
    }

    @Test("Passes through 7BIT content unchanged")
    func passes7BITThrough() {
        let input = "Hello World"
        let result = MIMEDecoder.decodeBody(input, encoding: "7BIT", charset: "UTF-8")
        #expect(result == input)
    }

    @Test("Passes through 8BIT content unchanged")
    func passes8BITThrough() {
        let input = "Hello World"
        let result = MIMEDecoder.decodeBody(input, encoding: "8BIT", charset: "UTF-8")
        #expect(result == input)
    }
}
