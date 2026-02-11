import Foundation
import Testing
@testable import VaultMailFeature

/// Verify OAuthManager PKCE, XOAUTH2 formatting, and token handling (AC-F-04).
@Suite("OAuth Manager")
struct OAuthManagerTests {

    // MARK: - PKCE Code Verifier

    @Test("Code verifier has valid length and characters")
    func codeVerifierFormat() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let verifier = await manager.generateCodeVerifier()

        // Base64URL of 32 random bytes = 43 chars
        #expect(verifier.count >= 43)
        #expect(verifier.count <= 128)

        // Verify only base64url-safe characters
        let allowedCharacterSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for char in verifier.unicodeScalars {
            #expect(allowedCharacterSet.contains(char), "Invalid character in verifier: \(char)")
        }
    }

    @Test("Code verifiers are unique")
    func codeVerifierUniqueness() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let v1 = await manager.generateCodeVerifier()
        let v2 = await manager.generateCodeVerifier()

        #expect(v1 != v2)
    }

    // MARK: - PKCE Code Challenge

    @Test("Code challenge is deterministic for same verifier")
    func codeChallengeIsDeterministic() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let verifier = "test-verifier-string-for-determinism"

        let challenge1 = await manager.generateCodeChallenge(from: verifier)
        let challenge2 = await manager.generateCodeChallenge(from: verifier)

        #expect(challenge1 == challenge2)
    }

    @Test("Code challenge differs from verifier")
    func challengeDiffersFromVerifier() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let verifier = await manager.generateCodeVerifier()

        let challenge = await manager.generateCodeChallenge(from: verifier)

        #expect(challenge != verifier)
    }

    @Test("Code challenge uses base64url encoding")
    func challengeUsesBase64URL() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let verifier = "a-simple-test-verifier"

        let challenge = await manager.generateCodeChallenge(from: verifier)

        // Should not contain standard base64 chars that differ from base64url
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
    }

    // MARK: - XOAUTH2 String

    @Test("XOAUTH2 string has correct format")
    func xoauth2Format() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let result = manager.formatXOAUTH2String(
            email: "user@gmail.com",
            accessToken: "ya29.test-token"
        )

        // Decode and verify format
        guard let data = Data(base64Encoded: result),
              let decoded = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to decode XOAUTH2 string")
            return
        }

        #expect(decoded.hasPrefix("user=user@gmail.com\u{01}"))
        #expect(decoded.contains("auth=Bearer ya29.test-token\u{01}"))
        #expect(decoded.hasSuffix("\u{01}"))
    }

    @Test("XOAUTH2 string produces valid base64")
    func xoauth2ProducesValidBase64() async {
        let manager = await OAuthManager(clientId: "test-client-id")
        let result = manager.formatXOAUTH2String(
            email: "test@example.com",
            accessToken: "token123"
        )

        // Should be valid base64
        let data = Data(base64Encoded: result)
        #expect(data != nil)
    }

    // MARK: - OAuthToken

    @Test("OAuthToken reports expired correctly")
    func tokenExpiredCheck() {
        let expired = OAuthToken(
            accessToken: "expired",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-60) // 1 minute ago
        )
        #expect(expired.isExpired)

        let valid = OAuthToken(
            accessToken: "valid",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600) // 1 hour from now
        )
        #expect(!valid.isExpired)
    }

    @Test("OAuthToken reports near-expiry correctly")
    func tokenNearExpiryCheck() {
        let nearExpiry = OAuthToken(
            accessToken: "near",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(60) // 1 minute from now (within 5-min buffer)
        )
        #expect(nearExpiry.isNearExpiry)

        let notNear = OAuthToken(
            accessToken: "far",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(600) // 10 minutes from now
        )
        #expect(!notNear.isNearExpiry)
    }

    @Test("OAuthToken round-trips through Codable")
    func tokenCodable() throws {
        let original = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1700000000),
            tokenType: "Bearer",
            scope: "https://mail.google.com/"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)

        #expect(decoded == original)
    }
}
