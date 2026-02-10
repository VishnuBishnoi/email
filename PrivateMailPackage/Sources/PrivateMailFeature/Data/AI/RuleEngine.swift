import Foundation

/// Rule-based spam/phishing signal analysis.
///
/// Analyzes URLs and email metadata for known spam/phishing indicators.
/// Combined with ML classification in `DetectSpamUseCase` for final decision.
///
/// Signals are scored 0.0–1.0 where higher = more likely spam.
///
/// Spec ref: FR-AI-06, AC-A-09
public struct RuleEngine: Sendable {

    /// Cached NSDataDetector for URL extraction (P2-3: avoid recreating per email).
    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    public init() {}

    /// Combined spam signal from all rule checks.
    public struct SpamSignal: Sendable {
        /// Overall spam probability from rules (0.0–1.0).
        public let score: Double
        /// Individual triggered rules for transparency.
        public let triggeredRules: [String]

        /// Whether rules alone suggest spam (high confidence threshold).
        public var isSpam: Bool { score >= 0.7 }
    }

    /// Analyze an email for spam/phishing signals.
    ///
    /// - Parameters:
    ///   - subject: Email subject line.
    ///   - sender: Sender email address.
    ///   - bodyText: Plain text email body.
    ///   - bodyHTML: HTML email body (for URL extraction).
    ///   - authenticationResults: Raw Authentication-Results header (SPF/DKIM/DMARC).
    /// - Returns: Combined spam signal with score and triggered rules.
    ///
    /// Spec ref: FR-AI-06, AC-A-09
    public func analyze(
        subject: String,
        sender: String,
        bodyText: String?,
        bodyHTML: String?,
        authenticationResults: String? = nil
    ) -> SpamSignal {
        var totalScore: Double = 0
        var rules: [String] = []

        // Check subject line
        let subjectResult = checkSubject(subject)
        totalScore += subjectResult.score
        rules.append(contentsOf: subjectResult.rules)

        // Check sender
        let senderResult = checkSender(sender)
        totalScore += senderResult.score
        rules.append(contentsOf: senderResult.rules)

        // Check URLs in body
        let urlResult = checkURLs(in: bodyText ?? "", html: bodyHTML ?? "")
        totalScore += urlResult.score
        rules.append(contentsOf: urlResult.rules)

        // Check body content patterns
        let bodyResult = checkBodyPatterns(bodyText ?? "")
        totalScore += bodyResult.score
        rules.append(contentsOf: bodyResult.rules)

        // Check email authentication headers (SPF/DKIM/DMARC)
        // Spec ref: FR-AI-06 (header authentication signal path)
        if let authHeader = authenticationResults {
            let authResult = checkAuthentication(authHeader)
            totalScore += authResult.score
            rules.append(contentsOf: authResult.rules)
        }

        // Normalize score to 0.0–1.0
        let normalizedScore = min(totalScore, 1.0)

        return SpamSignal(score: normalizedScore, triggeredRules: rules)
    }

    // MARK: - Subject Analysis

    private struct RuleResult {
        let score: Double
        let rules: [String]
    }

    private func checkSubject(_ subject: String) -> RuleResult {
        let lower = subject.lowercased()
        var score: Double = 0
        var rules: [String] = []

        // Urgency/pressure patterns
        let urgencyPatterns = [
            "urgent", "act now", "limited time", "expires",
            "immediate action", "don't miss", "last chance",
            "hurry", "deadline", "time sensitive"
        ]
        for pattern in urgencyPatterns where lower.contains(pattern) {
            score += 0.15
            rules.append("subject_urgency: \(pattern)")
            break // One hit is enough
        }

        // Financial bait
        let financialPatterns = [
            "winner", "won", "prize", "lottery", "inheritance",
            "million", "reward", "cash", "free money", "claim your"
        ]
        for pattern in financialPatterns where lower.contains(pattern) {
            score += 0.25
            rules.append("subject_financial_bait: \(pattern)")
            break
        }

        // Excessive capitalization (>50% uppercase and length > 10)
        if subject.count > 10 {
            let uppercaseCount = subject.filter(\.isUppercase).count
            if Double(uppercaseCount) / Double(subject.count) > 0.5 {
                score += 0.1
                rules.append("subject_excessive_caps")
            }
        }

        return RuleResult(score: score, rules: rules)
    }

    // MARK: - Sender Analysis

    private func checkSender(_ sender: String) -> RuleResult {
        let lower = sender.lowercased()
        var score: Double = 0
        var rules: [String] = []

        // Suspicious TLDs
        let suspiciousTLDs = [".xyz", ".top", ".click", ".loan", ".work",
                              ".gq", ".cf", ".tk", ".ml", ".ga",
                              ".buzz", ".icu", ".win", ".bid"]
        for tld in suspiciousTLDs where lower.hasSuffix(tld) {
            score += 0.2
            rules.append("sender_suspicious_tld: \(tld)")
            break
        }

        // Random-looking local part (many consecutive digits)
        if let atIndex = lower.firstIndex(of: "@") {
            let localPart = String(lower[lower.startIndex..<atIndex])
            let digitCount = localPart.filter(\.isNumber).count
            if localPart.count > 5 && Double(digitCount) / Double(localPart.count) > 0.6 {
                score += 0.15
                rules.append("sender_numeric_local")
            }
        }

        return RuleResult(score: score, rules: rules)
    }

    // MARK: - URL Analysis

    private func checkURLs(in text: String, html: String) -> RuleResult {
        var score: Double = 0
        var rules: [String] = []

        // Extract URLs from both text and HTML using cached detector (P2-3)
        let combined = text + " " + html
        let matches = Self.urlDetector?.matches(in: combined, range: NSRange(combined.startIndex..., in: combined)) ?? []

        let urls = matches.compactMap { match -> URL? in
            guard let range = Range(match.range, in: combined) else { return nil }
            return URL(string: String(combined[range]))
        }

        if urls.isEmpty { return RuleResult(score: 0, rules: []) }

        var foundHighPriorityURL = false

        for url in urls {
            guard !foundHighPriorityURL else { break } // P2-12: break outer loop consistently
            guard let host = url.host?.lowercased() else { continue }

            // IP address URLs — IPv4 (P2-14: also detect IPv6 with brackets/colons)
            if host.allSatisfy({ $0.isNumber || $0 == "." }) ||
               host.contains(":") || host.hasPrefix("[") {
                score += 0.3
                rules.append("url_ip_address")
                foundHighPriorityURL = true
                continue
            }

            // Suspicious TLDs in URLs
            let suspiciousTLDs = [".xyz", ".top", ".click", ".loan",
                                  ".work", ".gq", ".cf", ".tk"]
            for tld in suspiciousTLDs where host.hasSuffix(tld) {
                score += 0.15
                rules.append("url_suspicious_tld: \(tld)")
                foundHighPriorityURL = true
                break
            }
            if foundHighPriorityURL { continue }

            // URL shorteners
            let shorteners = ["bit.ly", "tinyurl.com", "t.co", "goo.gl",
                             "ow.ly", "is.gd", "buff.ly", "adf.ly"]
            if shorteners.contains(host) {
                score += 0.1
                rules.append("url_shortener: \(host)")
                foundHighPriorityURL = true
            }
        }

        // Many URLs in body (> 10)
        if urls.count > 10 {
            score += 0.1
            rules.append("url_count_high: \(urls.count)")
        }

        return RuleResult(score: min(score, 0.5), rules: rules)
    }

    // MARK: - Body Pattern Analysis

    private func checkBodyPatterns(_ text: String) -> RuleResult {
        let lower = text.lowercased()
        var score: Double = 0
        var rules: [String] = []

        // Phishing patterns
        let phishingPatterns = [
            "verify your account", "confirm your identity",
            "update your payment", "click here to verify",
            "your account has been compromised",
            "your account will be suspended",
            "enter your password", "social security number",
            "bank account details"
        ]
        for pattern in phishingPatterns where lower.contains(pattern) {
            score += 0.25
            rules.append("body_phishing: \(pattern)")
            break
        }

        // Unsubscribe absence check is NOT a spam signal (legit emails may lack it)
        // Instead, check for known spam body patterns
        let spamPatterns = [
            "nigerian prince", "wire transfer",
            "congratulations you have been selected",
            "act now before it's too late",
            "this is not spam", "this is not junk"
        ]
        for pattern in spamPatterns where lower.contains(pattern) {
            score += 0.3
            rules.append("body_spam_pattern: \(pattern)")
            break
        }

        return RuleResult(score: min(score, 0.5), rules: rules)
    }

    // MARK: - Authentication Header Analysis (SPF/DKIM/DMARC)

    /// Analyze Authentication-Results header for failed auth checks.
    ///
    /// Parses SPF, DKIM, and DMARC results from the header value.
    /// Failed authentication is a strong signal for spoofing/phishing.
    ///
    /// Header format (RFC 8601): "spf=pass; dkim=pass; dmarc=pass"
    /// Possible values: pass, fail, softfail, neutral, none, temperror, permerror
    ///
    /// Spec ref: FR-AI-06 (header authentication signal path)
    private func checkAuthentication(_ header: String) -> RuleResult {
        let lower = header.lowercased()
        var score: Double = 0
        var rules: [String] = []

        // SPF check
        if lower.contains("spf=fail") || lower.contains("spf=softfail") {
            score += 0.2
            rules.append("auth_spf_fail")
        } else if lower.contains("spf=none") {
            score += 0.1
            rules.append("auth_spf_none")
        }

        // DKIM check
        if lower.contains("dkim=fail") {
            score += 0.25
            rules.append("auth_dkim_fail")
        } else if lower.contains("dkim=none") {
            score += 0.1
            rules.append("auth_dkim_none")
        }

        // DMARC check
        if lower.contains("dmarc=fail") {
            score += 0.3
            rules.append("auth_dmarc_fail")
        } else if lower.contains("dmarc=none") {
            score += 0.1
            rules.append("auth_dmarc_none")
        }

        return RuleResult(score: min(score, 0.5), rules: rules)
    }
}
