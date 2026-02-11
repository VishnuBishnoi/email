import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("OAuthToken")
struct OAuthTokenTests {

    @Test("isExpired returns true when past expiresAt")
    func isExpiredWhenPastExpiresAt() {
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-60) // 1 minute ago
        )
        #expect(token.isExpired == true)
    }

    @Test("isExpired returns false when expiresAt is in the future")
    func isNotExpiredWhenFutureExpiresAt() {
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600) // 1 hour from now
        )
        #expect(token.isExpired == false)
    }

    @Test("isNearExpiry returns true within refresh buffer (5 min)")
    func isNearExpiryWithinBuffer() {
        // Token expires in 2 minutes, buffer is 5 minutes (300s)
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(120) // 2 minutes from now
        )
        #expect(token.isNearExpiry == true)
    }

    @Test("isNearExpiry returns false outside refresh buffer")
    func isNotNearExpiryOutsideBuffer() {
        // Token expires in 10 minutes, buffer is 5 minutes (300s)
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(600) // 10 minutes from now
        )
        #expect(token.isNearExpiry == false)
    }

    @Test("default tokenType is Bearer")
    func defaultsTokenTypeBearer() {
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date()
        )
        #expect(token.tokenType == "Bearer")
    }

    @Test("default scope matches AppConstants.oauthScope")
    func defaultsScopeFromConstants() {
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date()
        )
        #expect(token.scope == AppConstants.oauthScope)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = OAuthToken(
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1700000000),
            tokenType: "Bearer",
            scope: "https://mail.google.com/"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)

        #expect(decoded == original)
        #expect(decoded.accessToken == "my-access-token")
        #expect(decoded.refreshToken == "my-refresh-token")
        #expect(decoded.tokenType == "Bearer")
        #expect(decoded.scope == "https://mail.google.com/")
    }
}
