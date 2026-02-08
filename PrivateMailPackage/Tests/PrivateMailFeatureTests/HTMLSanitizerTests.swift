import Testing
@testable import PrivateMailFeature

@Suite("HTMLSanitizer")
struct HTMLSanitizerTests {

    // MARK: - Tag Stripping (with content)

    @Test("Strips script tags with content")
    func stripsScriptTags() {
        let html = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<script"))
        #expect(!result.html.contains("alert"))
        #expect(result.html.contains("<p>Hello</p>"))
        #expect(result.html.contains("<p>World</p>"))
    }

    @Test("Strips noscript tags with content")
    func stripsNoscriptTags() {
        let html = "<div>Content</div><noscript>Enable JS</noscript>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<noscript"))
        #expect(!result.html.contains("Enable JS"))
        #expect(result.html.contains("<div>Content</div>"))
    }

    @Test("Strips style tags with content")
    func stripsStyleTags() {
        let html = "<style>body{color:red}</style><p>Visible</p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<style"))
        #expect(!result.html.contains("body{color:red}"))
        #expect(result.html.contains("<p>Visible</p>"))
    }

    @Test("Strips iframe tags")
    func stripsIframeTags() {
        let html = "<p>Before</p><iframe src=\"https://evil.com\"></iframe><p>After</p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<iframe"))
        #expect(!result.html.contains("</iframe>"))
        #expect(result.html.contains("<p>Before</p>"))
        #expect(result.html.contains("<p>After</p>"))
    }

    @Test("Strips form elements: form, input, button, select, textarea")
    func stripsFormElements() {
        let html = """
        <form action="/submit">
        <input type="text" name="user">
        <select><option>A</option></select>
        <textarea>Notes</textarea>
        <button>Submit</button>
        </form>
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<form"))
        #expect(!result.html.contains("<input"))
        #expect(!result.html.contains("<button"))
        #expect(!result.html.contains("<select"))
        #expect(!result.html.contains("<textarea"))
    }

    @Test("Strips object, embed, and applet tags")
    func stripsObjectEmbedApplet() {
        let html = """
        <object data="flash.swf"></object>\
        <embed src="plugin.swf">\
        <applet code="App.class"></applet>
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<object"))
        #expect(!result.html.contains("<embed"))
        #expect(!result.html.contains("<applet"))
    }

    @Test("Removes meta refresh tags")
    func removesMetaRefresh() {
        let html = """
        <meta http-equiv="refresh" content="0;url=https://evil.com">\
        <p>Content</p>
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<meta"))
        #expect(!result.html.contains("refresh"))
        #expect(result.html.contains("<p>Content</p>"))
    }

    @Test("Removes external stylesheet link tags")
    func removesExternalStylesheetLinks() {
        let html = """
        <link rel="stylesheet" href="https://evil.com/tracker.css">\
        <p>Content</p>
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("<link"))
        #expect(!result.html.contains("stylesheet"))
        #expect(result.html.contains("<p>Content</p>"))
    }

    // MARK: - Attribute Cleaning

    @Test("Strips event handler attributes")
    func stripsEventHandlers() {
        let html = """
        <div onclick="alert('xss')" onmouseover="track()">Click</div>\
        <img src="x.png" onerror="steal()">
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("onclick"))
        #expect(!result.html.contains("onmouseover"))
        #expect(!result.html.contains("onerror"))
        #expect(!result.html.contains("alert"))
        #expect(!result.html.contains("steal"))
        #expect(result.html.contains("Click"))
    }

    // MARK: - URI Neutralization

    @Test("Neutralizes javascript: URIs in href")
    func neutralizesJavaScriptURIs() {
        let html = "<a href=\"javascript:alert('xss')\">Click me</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("javascript:"))
        #expect(result.html.contains("href=\"#\""))
        #expect(result.html.contains("Click me"))
    }

    @Test("Neutralizes data: URIs in non-img attributes but preserves data: in img src")
    func handlesDataURIs() {
        let html = """
        <a href="data:text/html,<script>alert(1)</script>">Link</a>\
        <img src="data:image/png;base64,abc123">
        """
        let result = HTMLSanitizer.sanitize(html)
        // The <a> data: URI should be neutralized
        #expect(result.html.contains("href=\"#\""))
        // The <img> data: URI should be preserved
        #expect(result.html.contains("data:image/png;base64,abc123"))
    }

    // MARK: - Remote Image Handling

    @Test("Blocks remote images when loadRemoteImages is false and counts them")
    func blocksRemoteImages() {
        let html = """
        <p>Text</p>\
        <img src="https://tracker.com/pixel.gif">\
        <img src="http://example.com/photo.jpg">\
        <img src="data:image/png;base64,abc123">
        """
        let result = HTMLSanitizer.sanitize(html, loadRemoteImages: false)
        #expect(result.hasBlockedRemoteContent)
        #expect(result.remoteImageCount == 2)
        #expect(!result.html.contains("tracker.com"))
        #expect(!result.html.contains("example.com/photo"))
        #expect(result.html.contains("<!-- remote-image-blocked -->"))
        // data: image should be preserved
        #expect(result.html.contains("data:image/png;base64,abc123"))
    }

    @Test("Allows remote images when loadRemoteImages is true")
    func allowsRemoteImages() {
        let html = "<img src=\"https://example.com/photo.jpg\">"
        let result = HTMLSanitizer.sanitize(html, loadRemoteImages: true)
        #expect(!result.hasBlockedRemoteContent)
        #expect(result.remoteImageCount == 0)
        #expect(result.html.contains("https://example.com/photo.jpg"))
    }

    // MARK: - Safe Content Preservation

    @Test("Preserves safe HTML tags and content")
    func preservesSafeHTML() {
        let html = """
        <h1>Title</h1>\
        <p>Paragraph with <strong>bold</strong> and <em>italic</em>.</p>\
        <ul><li>Item 1</li><li>Item 2</li></ul>\
        <ol><li>Ordered</li></ol>\
        <blockquote>Quote</blockquote>\
        <pre><code>let x = 1</code></pre>\
        <table><tr><th>Header</th><td>Cell</td></tr></table>\
        <a href="https://safe.com">Link</a>\
        <br><div><span>Span</span></div>\
        <b>Bold</b> <i>Italic</i>\
        <h2>H2</h2><h3>H3</h3><h4>H4</h4><h5>H5</h5><h6>H6</h6>
        """
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.html.contains("<h1>Title</h1>"))
        #expect(result.html.contains("<p>"))
        #expect(result.html.contains("<strong>bold</strong>"))
        #expect(result.html.contains("<em>italic</em>"))
        #expect(result.html.contains("<ul>"))
        #expect(result.html.contains("<li>Item 1</li>"))
        #expect(result.html.contains("<ol>"))
        #expect(result.html.contains("<blockquote>Quote</blockquote>"))
        #expect(result.html.contains("<pre>"))
        #expect(result.html.contains("<code>let x = 1</code>"))
        #expect(result.html.contains("<table>"))
        #expect(result.html.contains("<th>Header</th>"))
        #expect(result.html.contains("<td>Cell</td>"))
        #expect(result.html.contains("<a href=\"https://safe.com\">Link</a>"))
        #expect(result.html.contains("<br>"))
        #expect(result.html.contains("<div>"))
        #expect(result.html.contains("<span>Span</span>"))
        #expect(result.html.contains("<b>Bold</b>"))
        #expect(result.html.contains("<i>Italic</i>"))
        #expect(result.html.contains("<h2>H2</h2>"))
    }

    // MARK: - Edge Cases

    @Test("Handles empty input")
    func handlesEmptyInput() {
        let result = HTMLSanitizer.sanitize("")
        #expect(result.html == "")
        #expect(!result.hasBlockedRemoteContent)
        #expect(result.remoteImageCount == 0)
    }

    @Test("Handles malformed HTML gracefully")
    func handlesMalformedHTML() {
        let html = "<p>Unclosed paragraph<div>Nested<span>deeply"
        let result = HTMLSanitizer.sanitize(html)
        // Should not crash and should preserve the text content
        #expect(result.html.contains("Unclosed paragraph"))
        #expect(result.html.contains("Nested"))
        #expect(result.html.contains("deeply"))
    }

    // MARK: - Dynamic Type CSS Injection

    @Test("Injects Dynamic Type CSS correctly")
    func injectsDynamicTypeCSS() {
        let html = "<p>Hello World</p>"
        let wrapped = HTMLSanitizer.injectDynamicTypeCSS(html, fontSizePoints: 16)
        #expect(wrapped.contains("<html>"))
        #expect(wrapped.contains("</html>"))
        #expect(wrapped.contains("<head>"))
        #expect(wrapped.contains("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"))
        #expect(wrapped.contains("font-size:16pt"))
        #expect(wrapped.contains("word-wrap:break-word"))
        #expect(wrapped.contains("overflow-wrap:break-word"))
        #expect(wrapped.contains("-webkit-text-size-adjust:none"))
        #expect(wrapped.contains("<body><p>Hello World</p></body>"))
    }

    // MARK: - Complex Real-World Email

    @Test("Handles complex real-world HTML email")
    func handlesComplexRealWorldEmail() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta http-equiv="refresh" content="5;url=https://phishing.com">
            <link rel="stylesheet" href="https://tracker.com/style.css">
            <style>body { font-family: Arial; } @import url('https://fonts.com/track');</style>
        </head>
        <body>
            <div onclick="trackClick()" style="color: blue;">
                <h1>Important Newsletter</h1>
                <p>Dear <strong>Customer</strong>,</p>
                <p>Check out our <a href="https://safe-link.com">latest offer</a>!</p>
                <p>Also see <a href="javascript:void(0)">this link</a></p>
                <img src="https://tracker.com/pixel.gif" width="1" height="1">
                <img src="data:image/png;base64,iVBORw0KGgo=">
                <table>
                    <tr><th>Product</th><th>Price</th></tr>
                    <tr><td>Widget</td><td>$9.99</td></tr>
                </table>
                <script>document.cookie</script>
                <iframe src="https://evil.com/frame"></iframe>
                <form action="https://phishing.com/steal">
                    <input type="text" name="password">
                    <button type="submit">Submit</button>
                </form>
                <object data="flash.swf"></object>
                <blockquote>Great product! - User</blockquote>
                <ul>
                    <li>Feature 1</li>
                    <li>Feature 2</li>
                </ul>
            </div>
        </body>
        </html>
        """
        let result = HTMLSanitizer.sanitize(html, loadRemoteImages: false)

        // Dangerous content removed
        #expect(!result.html.contains("<script"))
        #expect(!result.html.contains("document.cookie"))
        #expect(!result.html.contains("<style"))
        #expect(!result.html.contains("@import"))
        #expect(!result.html.contains("http-equiv"))
        #expect(!result.html.contains("refresh"))
        #expect(!result.html.contains("<link"))
        #expect(!result.html.contains("stylesheet"))
        #expect(!result.html.contains("<iframe"))
        #expect(!result.html.contains("<form"))
        #expect(!result.html.contains("<input"))
        #expect(!result.html.contains("<button"))
        #expect(!result.html.contains("<object"))
        #expect(!result.html.contains("onclick"))
        #expect(!result.html.contains("javascript:"))

        // Safe content preserved
        #expect(result.html.contains("<h1>Important Newsletter</h1>"))
        #expect(result.html.contains("<strong>Customer</strong>"))
        #expect(result.html.contains("<a href=\"https://safe-link.com\">latest offer</a>"))
        #expect(result.html.contains("<table>"))
        #expect(result.html.contains("Widget"))
        #expect(result.html.contains("<blockquote>"))
        #expect(result.html.contains("<li>Feature 1</li>"))

        // Remote images blocked, inline data image kept
        #expect(result.hasBlockedRemoteContent)
        #expect(result.remoteImageCount == 1)
        #expect(result.html.contains("data:image/png;base64,iVBORw0KGgo="))

        // javascript: URI neutralized
        #expect(result.html.contains("href=\"#\""))
    }

    // MARK: - Additional Edge Cases

    @Test("Strips case-insensitive tag variations")
    func caseInsensitiveStripping() {
        let html = "<SCRIPT>alert(1)</SCRIPT><Script>track()</Script>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("alert"))
        #expect(!result.html.contains("track"))
        #expect(!result.html.lowercased().contains("<script"))
    }

    @Test("Handles multiple script tags in sequence")
    func multipleScriptTags() {
        let html = "<script>a()</script><p>Keep</p><script>b()</script>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("a()"))
        #expect(!result.html.contains("b()"))
        #expect(result.html.contains("<p>Keep</p>"))
    }

    @Test("SanitizationResult reports no blocked content when none present")
    func noRemoteImages() {
        let html = "<p>Simple text with <b>bold</b></p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.hasBlockedRemoteContent)
        #expect(result.remoteImageCount == 0)
    }

    // MARK: - URI Scheme Allow-list (PR #8 Comment 5)

    @Test("Allow-list blocks ftp: scheme in href")
    func allowListBlocksFtpInHref() {
        let html = "<a href=\"ftp://evil.com/file\">Link</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("ftp://"))
        #expect(result.html.contains("href=\"#\""))
    }

    @Test("Allow-list blocks tel: scheme in href")
    func allowListBlocksTelInHref() {
        let html = "<a href=\"tel:+1234567890\">Call</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("tel:"))
        #expect(result.html.contains("href=\"#\""))
    }

    @Test("Allow-list blocks sms: scheme in href")
    func allowListBlocksSmsInHref() {
        let html = "<a href=\"sms:+1234567890\">Text</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("sms:"))
        #expect(result.html.contains("href=\"#\""))
    }

    @Test("Allow-list blocks file: scheme in href")
    func allowListBlocksFileInHref() {
        let html = "<a href=\"file:///etc/passwd\">Open</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("file:"))
        #expect(result.html.contains("href=\"#\""))
    }

    @Test("Allow-list permits http and https in href")
    func allowListPermitsHttpInHref() {
        let html = "<a href=\"http://example.com\">HTTP</a><a href=\"https://safe.com\">HTTPS</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.html.contains("href=\"http://example.com\""))
        #expect(result.html.contains("href=\"https://safe.com\""))
    }

    @Test("Allow-list permits mailto: in href")
    func allowListPermitsMailtoInHref() {
        let html = "<a href=\"mailto:user@example.com\">Email</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.html.contains("mailto:user@example.com"))
    }

    @Test("Allow-list permits fragment (#) links in href")
    func allowListPermitsFragmentInHref() {
        let html = "<a href=\"#section-2\">Jump</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.html.contains("href=\"#section-2\""))
    }

    @Test("Allow-list preserves data:image/ in src")
    func allowListPreservesDataImageInSrc() {
        let html = "<img src=\"data:image/gif;base64,R0lGO\">"
        let result = HTMLSanitizer.sanitize(html, loadRemoteImages: true)
        #expect(result.html.contains("data:image/gif;base64,R0lGO"))
    }

    @Test("Allow-list blocks ftp: scheme in src")
    func allowListBlocksFtpInSrc() {
        let html = "<img src=\"ftp://evil.com/img.png\">"
        let result = HTMLSanitizer.sanitize(html, loadRemoteImages: true)
        #expect(!result.html.contains("ftp://"))
    }

    @Test("Allow-list blocks custom scheme in action")
    func allowListBlocksCustomSchemeInAction() {
        let html = "<div action=\"custom://launch\">Form</div>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("custom://"))
        #expect(result.html.contains("action=\"#\""))
    }

    @Test("Allow-list handles single-quoted attributes")
    func allowListSingleQuotedAttributes() {
        let html = "<a href='tel:123'>Call</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.html.contains("tel:"))
        #expect(result.html.contains("href='#'"))
    }
}
