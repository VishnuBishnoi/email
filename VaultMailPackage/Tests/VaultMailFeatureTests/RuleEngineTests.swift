import Testing
import Foundation
@testable import VaultMailFeature

@Suite("RuleEngine")
struct RuleEngineTests {
    let engine = RuleEngine()

    // MARK: - Clean Emails

    @Test("legitimate email has low spam score")
    func legitimateEmail() {
        let signal = engine.analyze(
            subject: "Meeting notes from today",
            sender: "alice@company.com",
            bodyText: "Hi team, please find the meeting notes attached.",
            bodyHTML: nil
        )
        #expect(signal.score < 0.3)
        #expect(!signal.isSpam)
    }

    @Test("clean email with no body has zero score")
    func cleanEmailNoBody() {
        let signal = engine.analyze(
            subject: "Hello",
            sender: "friend@gmail.com",
            bodyText: nil,
            bodyHTML: nil
        )
        #expect(signal.score == 0)
        #expect(signal.triggeredRules.isEmpty)
    }

    // MARK: - Subject Analysis

    @Test("urgency patterns increase score")
    func urgencySubject() {
        let signal = engine.analyze(
            subject: "URGENT: Act now before it's too late!",
            sender: "alerts@company.com",
            bodyText: "Please update your information.",
            bodyHTML: nil
        )
        #expect(signal.score > 0)
        #expect(signal.triggeredRules.contains(where: { $0.contains("urgency") }))
    }

    @Test("financial bait patterns increase score")
    func financialBaitSubject() {
        let signal = engine.analyze(
            subject: "You are the WINNER of $1,000,000!",
            sender: "lottery@free.tk",
            bodyText: "Claim your prize now.",
            bodyHTML: nil
        )
        #expect(signal.score > 0.3)
        #expect(signal.triggeredRules.contains(where: { $0.contains("financial_bait") }))
    }

    @Test("excessive caps in subject increases score")
    func excessiveCapsSubject() {
        let signal = engine.analyze(
            subject: "THIS IS ALL CAPS FOR NO REASON AT ALL",
            sender: "test@example.com",
            bodyText: "Normal body text.",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("excessive_caps") }))
    }

    // MARK: - Sender Analysis

    @Test("suspicious TLD increases score")
    func suspiciousTLD() {
        let signal = engine.analyze(
            subject: "Hello",
            sender: "admin@secure-bank.xyz",
            bodyText: "Please verify your account.",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("suspicious_tld") }))
    }

    @Test("numeric sender local part increases score")
    func numericSender() {
        let signal = engine.analyze(
            subject: "Check this out",
            sender: "8374625193@example.com",
            bodyText: "Click here for deals.",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("numeric_local") }))
    }

    // MARK: - URL Analysis

    @Test("IP address URL increases score")
    func ipAddressURL() {
        let signal = engine.analyze(
            subject: "Login Required",
            sender: "admin@example.com",
            bodyText: "Click here: http://192.168.1.1/login",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("ip_address") }))
    }

    @Test("URL shortener increases score")
    func urlShortener() {
        let signal = engine.analyze(
            subject: "Check this out",
            sender: "friend@example.com",
            bodyText: "Look at this: https://bit.ly/abc123",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("shortener") }))
    }

    // MARK: - Body Pattern Analysis

    @Test("phishing patterns increase score")
    func phishingBody() {
        let signal = engine.analyze(
            subject: "Security Alert",
            sender: "security@bank.com",
            bodyText: "Your account has been compromised. Click here to verify your account immediately.",
            bodyHTML: nil
        )
        #expect(signal.triggeredRules.contains(where: { $0.contains("phishing") }))
    }

    @Test("spam patterns increase score")
    func spamBody() {
        let signal = engine.analyze(
            subject: "Opportunity",
            sender: "prince@country.ng",
            bodyText: "Dear friend, I am a Nigerian prince and need your help with a wire transfer.",
            bodyHTML: nil
        )
        #expect(signal.score > 0.2)
    }

    // MARK: - Combined Signals

    @Test("multiple signals combine for high score")
    func combinedSignals() {
        let signal = engine.analyze(
            subject: "URGENT: You are the WINNER!",
            sender: "lottery@free.tk",
            bodyText: "Congratulations you have been selected for a $1,000,000 prize. Click here to verify your account: http://192.168.1.1/claim",
            bodyHTML: nil
        )
        #expect(signal.isSpam)
        #expect(signal.triggeredRules.count >= 2)
    }

    @Test("spam signal score is capped at 1.0")
    func scoreCapped() {
        let signal = engine.analyze(
            subject: "URGENT WINNER PRIZE LOTTERY ACT NOW",
            sender: "28472638@spam.xyz",
            bodyText: "Nigerian prince wire transfer verify your account click here immediately http://192.168.1.1/malware",
            bodyHTML: nil
        )
        #expect(signal.score <= 1.0)
    }
}
