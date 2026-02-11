import Foundation

/// Detects and removes tracking pixels from HTML email content.
///
/// Tracking pixels are invisible images embedded in emails to track
/// when a recipient opens the message. This detector identifies them
/// by size attributes, CSS styles, known tracking domains, and
/// hidden container elements.
///
/// Spec ref: FR-ED-04
public enum TrackingPixelDetector {

    // MARK: - Types

    /// Result of scanning HTML for tracking pixels.
    public struct DetectionResult: Sendable, Equatable {
        /// The HTML with tracking pixel `<img>` tags removed.
        public let sanitizedHTML: String
        /// Number of tracking pixels that were removed.
        public let trackerCount: Int
    }

    // MARK: - Cached Tracking Domains

    /// Cached set of known tracking domains loaded from the bundled JSON.
    private static let _cachedDomains: Set<String> = {
        loadTrackingDomainsFromBundle(.module)
    }()

    // MARK: - Public API

    /// Detect and strip tracking pixels from the given HTML string.
    ///
    /// Detection criteria:
    /// 1. Images with `width="1" height="1"` or `width="0" height="0"` in attributes
    /// 2. Images with CSS inline styles containing `width:1px`, `height:1px`, `width:0`, `height:0`
    /// 3. Images whose `src` URL hostname matches a known tracking domain
    /// 4. Images inside elements with `display:none`, `visibility:hidden`, or `opacity:0`
    ///
    /// - Parameter html: The raw HTML content of an email.
    /// - Returns: A ``DetectionResult`` with sanitized HTML and tracker count.
    public static func detect(in html: String) -> DetectionResult {
        guard !html.isEmpty else {
            return DetectionResult(sanitizedHTML: "", trackerCount: 0)
        }

        let domains = _cachedDomains
        var result = html
        var trackerCount = 0

        // Find all <img ...> tags (self-closing or not).
        // We use a case-insensitive regex to match various HTML styles.
        let imgPattern = #"<img\b[^>]*/?>"#
        guard let imgRegex = try? NSRegularExpression(
            pattern: imgPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return DetectionResult(sanitizedHTML: html, trackerCount: 0)
        }

        // Collect matches in reverse order so we can remove them
        // without invalidating indices.
        let fullRange = NSRange(result.startIndex..., in: result)
        let matches = imgRegex.matches(in: result, range: fullRange)

        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let imgTag = String(result[swiftRange])

            if isTrackingPixel(imgTag, knownDomains: domains) || isInsideHiddenContainer(at: swiftRange, in: result) {
                result.removeSubrange(swiftRange)
                trackerCount += 1
            }
        }

        return DetectionResult(sanitizedHTML: result, trackerCount: trackerCount)
    }

    /// Load tracking domains from a JSON resource file in the given bundle.
    ///
    /// Expected JSON format:
    /// ```json
    /// { "version": "1.0.0", "domains": ["domain1.com", "domain2.com"] }
    /// ```
    ///
    /// - Parameter bundle: The bundle containing `tracking_domains.json`. Defaults to `.module`.
    /// - Returns: A set of lowercase domain strings, or an empty set if the file is not found.
    public static func loadTrackingDomains(from bundle: Bundle? = nil) -> Set<String> {
        let resolvedBundle = bundle ?? .module
        if resolvedBundle == .module {
            return _cachedDomains
        }
        return loadTrackingDomainsFromBundle(resolvedBundle)
    }

    // MARK: - Private Helpers

    /// Internal loader without caching, used to populate the cache.
    private static func loadTrackingDomainsFromBundle(_ bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "tracking_domains", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(TrackingDomainsFile.self, from: data)
            return Set(decoded.domains.map { $0.lowercased() })
        } catch {
            return []
        }
    }

    /// Determines whether a single `<img>` tag is a tracking pixel.
    private static func isTrackingPixel(_ imgTag: String, knownDomains: Set<String>) -> Bool {
        // Criterion 1: HTML attribute-based size (1x1 or 0x0)
        if hasTrackingSizeAttributes(imgTag) {
            return true
        }

        // Criterion 2: CSS inline style-based size
        if hasTrackingSizeInStyle(imgTag) {
            return true
        }

        // Criterion 3: src hostname matches a known tracking domain
        if matchesTrackingDomain(imgTag, knownDomains: knownDomains) {
            return true
        }

        return false
    }

    /// Check for `width="0"` or `width="1"` combined with matching height in HTML attributes.
    private static func hasTrackingSizeAttributes(_ imgTag: String) -> Bool {
        let widthPattern = #"width\s*=\s*["']?\s*([01])\s*["']?"#
        let heightPattern = #"height\s*=\s*["']?\s*([01])\s*["']?"#

        guard let widthRegex = try? NSRegularExpression(pattern: widthPattern, options: .caseInsensitive),
              let heightRegex = try? NSRegularExpression(pattern: heightPattern, options: .caseInsensitive) else {
            return false
        }

        let range = NSRange(imgTag.startIndex..., in: imgTag)

        let hasSmallWidth = widthRegex.firstMatch(in: imgTag, range: range) != nil
        let hasSmallHeight = heightRegex.firstMatch(in: imgTag, range: range) != nil

        return hasSmallWidth && hasSmallHeight
    }

    /// Check for tracking-size CSS in the `style` attribute.
    private static func hasTrackingSizeInStyle(_ imgTag: String) -> Bool {
        guard let styleValue = extractAttributeValue(named: "style", from: imgTag) else {
            return false
        }

        let style = styleValue.lowercased()

        let hasSmallWidth = style.contains("width:1px") || style.contains("width: 1px")
            || style.contains("width:0") || style.contains("width: 0")
        let hasSmallHeight = style.contains("height:1px") || style.contains("height: 1px")
            || style.contains("height:0") || style.contains("height: 0")

        return hasSmallWidth && hasSmallHeight
    }

    /// Check whether the `src` URL's hostname is in the known tracking domains set.
    private static func matchesTrackingDomain(_ imgTag: String, knownDomains: Set<String>) -> Bool {
        guard let srcValue = extractAttributeValue(named: "src", from: imgTag) else {
            return false
        }

        guard let url = URL(string: srcValue), let host = url.host?.lowercased() else {
            return false
        }

        // Check exact match or if the host ends with a known tracking domain.
        if knownDomains.contains(host) {
            return true
        }

        for domain in knownDomains {
            if host.hasSuffix(".\(domain)") {
                return true
            }
        }

        return false
    }

    /// Check whether the `<img>` tag at the given range sits inside an element
    /// with `display:none`, `visibility:hidden`, or `opacity:0` in its style.
    private static func isInsideHiddenContainer(at imgRange: Range<String.Index>, in html: String) -> Bool {
        // Look backwards from the img tag for the nearest opening tag with a style attribute
        // that contains a hiding CSS property.
        let prefix = html[html.startIndex..<imgRange.lowerBound]

        // Find all opening tags with style attributes in the prefix.
        let tagPattern = #"<(\w+)\b[^>]*style\s*=\s*["']([^"']*)["'][^>]*>"#
        guard let tagRegex = try? NSRegularExpression(
            pattern: tagPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return false
        }

        let prefixString = String(prefix)
        let range = NSRange(prefixString.startIndex..., in: prefixString)
        let matches = tagRegex.matches(in: prefixString, range: range)

        // Check each containing element's style for hiding properties.
        // We need to verify the tag hasn't been closed before our img.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let tagNameRange = Range(match.range(at: 1), in: prefixString),
                  let styleRange = Range(match.range(at: 2), in: prefixString) else {
                continue
            }

            let tagName = String(prefixString[tagNameRange]).lowercased()
            let styleValue = String(prefixString[styleRange]).lowercased()

            // Check if this tag is still open (no matching closing tag between it and the img).
            let afterTag = prefixString[match.range(at: 0).upperBound(in: prefixString)...]
            let closingTag = "</\(tagName)"
            if afterTag.range(of: closingTag, options: .caseInsensitive) != nil {
                // Tag was closed before the img, so it's not a container.
                continue
            }

            let isHidden = styleValue.contains("display:none") || styleValue.contains("display: none")
                || styleValue.contains("visibility:hidden") || styleValue.contains("visibility: hidden")
                || styleValue.contains("opacity:0") || styleValue.contains("opacity: 0")

            if isHidden {
                return true
            }
        }

        return false
    }

    /// Extract the value of an HTML attribute from a tag string.
    private static func extractAttributeValue(named name: String, from tag: String) -> String? {
        // Match attribute="value" or attribute='value'
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }

        return String(tag[valueRange])
    }
}

// MARK: - JSON Model

private struct TrackingDomainsFile: Decodable {
    let version: String
    let domains: [String]
}

// MARK: - NSRange Extension

private extension NSRange {
    func upperBound(in string: String) -> String.Index {
        let utf16 = string.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: self.location + self.length)
        return start
    }
}
