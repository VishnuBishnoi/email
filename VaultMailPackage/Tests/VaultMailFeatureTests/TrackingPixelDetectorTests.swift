import Testing
@testable import VaultMailFeature

@Suite("TrackingPixelDetector")
struct TrackingPixelDetectorTests {

    // MARK: - Size Attribute Detection

    @Test("Detects 1x1 pixel images by width/height attributes")
    func detects1x1PixelByAttributes() {
        let html = """
        <p>Hello</p>
        <img src="https://example.com/pixel.gif" width="1" height="1">
        <p>World</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("<img"))
        #expect(result.sanitizedHTML.contains("Hello"))
        #expect(result.sanitizedHTML.contains("World"))
    }

    @Test("Detects 0x0 pixel images by width/height attributes")
    func detects0x0PixelByAttributes() {
        let html = """
        <img src="https://example.com/track.png" width="0" height="0">
        <p>Content</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("<img"))
        #expect(result.sanitizedHTML.contains("Content"))
    }

    // MARK: - CSS Style Detection

    @Test("Detects 1x1 pixels in CSS inline styles")
    func detects1x1PixelInCSSStyle() {
        let html = """
        <img src="https://example.com/t.gif" style="width:1px;height:1px;">
        <p>Text</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("<img"))
    }

    @Test("Detects 0-size pixels in CSS inline styles with spaces")
    func detects0SizePixelInCSSStyleWithSpaces() {
        let html = """
        <img src="https://example.com/t.gif" style="width: 0; height: 0;">
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("<img"))
    }

    // MARK: - Tracking Domain Detection

    @Test("Detects known tracking domain URLs")
    func detectsKnownTrackingDomain() {
        let html = """
        <p>Newsletter</p>
        <img src="https://pixel.mailchimp.com/open/abc123">
        <img src="https://ct.sendgrid.net/wf/open?abc">
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 2)
        #expect(!result.sanitizedHTML.contains("mailchimp"))
        #expect(!result.sanitizedHTML.contains("sendgrid"))
        #expect(result.sanitizedHTML.contains("Newsletter"))
    }

    // MARK: - Hidden Container Detection

    @Test("Detects images in display:none elements")
    func detectsImageInDisplayNone() {
        let html = """
        <div style="display:none;">
        <img src="https://example.com/normal-image.jpg">
        </div>
        <p>Visible content</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("normal-image.jpg"))
        #expect(result.sanitizedHTML.contains("Visible content"))
    }

    @Test("Detects images with visibility:hidden container")
    func detectsImageInVisibilityHidden() {
        let html = """
        <span style="visibility:hidden;">
        <img src="https://example.com/track.png">
        </span>
        <p>Real content</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("track.png"))
    }

    @Test("Detects images with opacity:0 container")
    func detectsImageInOpacityZero() {
        let html = """
        <div style="opacity:0;">
        <img src="https://example.com/beacon.gif">
        </div>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("beacon.gif"))
    }

    // MARK: - Preservation of Legitimate Content

    @Test("Preserves legitimate images with normal size and non-tracking domain")
    func preservesLegitimateImages() {
        let html = """
        <p>Hello</p>
        <img src="https://example.com/photo.jpg" width="600" height="400" alt="Photo">
        <img src="https://cdn.images.com/logo.png">
        <p>Goodbye</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 0)
        #expect(result.sanitizedHTML.contains("photo.jpg"))
        #expect(result.sanitizedHTML.contains("logo.png"))
        #expect(result.sanitizedHTML == html)
    }

    @Test("Returns zero count for clean HTML with no tracking pixels")
    func returnsZeroCountForCleanHTML() {
        let html = """
        <html>
        <body>
        <h1>Welcome</h1>
        <p>This is a clean email with no tracking.</p>
        <img src="https://example.com/banner.jpg" width="800" height="200">
        </body>
        </html>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 0)
        #expect(result.sanitizedHTML == html)
    }

    // MARK: - Edge Cases

    @Test("Handles empty input gracefully")
    func handlesEmptyInput() {
        let result = TrackingPixelDetector.detect(in: "")
        #expect(result.trackerCount == 0)
        #expect(result.sanitizedHTML == "")
    }

    @Test("Counts multiple tracking pixels correctly")
    func countsMultipleTrackingPixels() {
        let html = """
        <img src="https://pixel.mailchimp.com/open/1" width="1" height="1">
        <p>Content</p>
        <img src="https://ct.sendgrid.net/wf/open" width="0" height="0">
        <img src="https://t.yesware.com/track/abc">
        <img src="https://example.com/real-photo.jpg" width="300" height="200">
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 3)
        #expect(result.sanitizedHTML.contains("real-photo.jpg"))
        #expect(!result.sanitizedHTML.contains("mailchimp"))
        #expect(!result.sanitizedHTML.contains("sendgrid"))
        #expect(!result.sanitizedHTML.contains("yesware"))
    }

    // MARK: - Domain Loading

    @Test("Loads tracking domains from bundled JSON")
    func loadsTrackingDomains() {
        let domains = TrackingPixelDetector.loadTrackingDomains()
        #expect(!domains.isEmpty)
        #expect(domains.contains("pixel.mailchimp.com"))
        #expect(domains.contains("ct.sendgrid.net"))
        #expect(domains.contains("mailtrack.io"))
    }

    @Test("Self-closing img tags are detected")
    func detectsSelfClosingImgTags() {
        let html = """
        <img src="https://mailtrack.io/trace/abc" />
        <p>Email body</p>
        """
        let result = TrackingPixelDetector.detect(in: html)
        #expect(result.trackerCount == 1)
        #expect(!result.sanitizedHTML.contains("mailtrack.io"))
    }
}
