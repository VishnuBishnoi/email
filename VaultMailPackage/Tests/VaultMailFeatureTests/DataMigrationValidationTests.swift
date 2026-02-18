import Foundation
import SwiftData
import Testing
@testable import VaultMailFeature

/// Validates that existing Gmail-only data continues to work
/// after the multi-provider schema changes.
///
/// Covers:
/// - Old Account (no provider/security fields) resolves to Gmail defaults
/// - Legacy OAuthToken JSON decodes as .oauth(token) via AccountCredential
/// - Full flow: old-format Account + old-format token → successful credential resolution
///
/// Spec ref: FR-MPROV-14 (Data Migration Validation)
@Suite("Data Migration Validation Tests")
@MainActor
struct DataMigrationValidationTests {

    // MARK: - Account Model Backward Compatibility

    @Test("Account with nil provider resolves to .gmail")
    func nilProviderResolvesToGmail() {
        let account = Account(
            email: "user@gmail.com",
            displayName: "Test User",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587
        )

        // provider is nil — resolvedProvider should default to .gmail
        #expect(account.provider == nil)
        #expect(account.resolvedProvider == .gmail)
    }

    @Test("Account with nil security resolves to .tls")
    func nilSecurityResolvesToTLS() {
        let account = Account(
            email: "user@gmail.com",
            displayName: "Test User",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587
        )

        #expect(account.imapSecurity == nil)
        #expect(account.smtpSecurity == nil)
        #expect(account.resolvedImapSecurity == .tls)
        #expect(account.resolvedSmtpSecurity == .tls)
    }

    @Test("Account with explicit provider preserves value")
    func explicitProviderPreserved() {
        let account = Account(
            email: "user@icloud.com",
            displayName: "Test User",
            imapHost: "imap.mail.me.com",
            imapPort: 993,
            smtpHost: "smtp.mail.me.com",
            smtpPort: 587
        )
        account.provider = ProviderIdentifier.icloud.rawValue

        #expect(account.resolvedProvider == .icloud)
    }

    @Test("Account with explicit security preserves STARTTLS")
    func explicitSecurityPreserved() {
        let account = Account(
            email: "user@icloud.com",
            displayName: "Test User",
            imapHost: "imap.mail.me.com",
            imapPort: 993,
            smtpHost: "smtp.mail.me.com",
            smtpPort: 587
        )
        account.imapSecurity = ConnectionSecurity.tls.rawValue
        account.smtpSecurity = ConnectionSecurity.starttls.rawValue

        #expect(account.resolvedImapSecurity == .tls)
        #expect(account.resolvedSmtpSecurity == .starttls)
    }

    // MARK: - Keychain Credential Backward Compatibility

    @Test("Legacy OAuthToken stored via legacy API can be retrieved as AccountCredential")
    func legacyOAuthTokenRetrievedAsCredential() async throws {
        let keychain = MockKeychainManager()
        let token = OAuthToken(
            accessToken: "legacy-access-token",
            refreshToken: "legacy-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "https://mail.google.com/"
        )

        // Store using legacy API
        try await keychain.store(token, for: "acc-1")

        // Retrieve using new API
        let credential = try await keychain.retrieveCredential(for: "acc-1")

        #expect(credential != nil)
        if case .oauth(let retrievedToken) = credential {
            #expect(retrievedToken.accessToken == "legacy-access-token")
            #expect(retrievedToken.refreshToken == "legacy-refresh-token")
        } else {
            Issue.record("Expected .oauth credential, got \(String(describing: credential))")
        }
    }

    @Test("Legacy OAuthToken stored via legacy API can still be retrieved via legacy API")
    func legacyOAuthTokenRetrievedViaLegacyAPI() async throws {
        let keychain = MockKeychainManager()
        let token = OAuthToken(
            accessToken: "legacy-access-token",
            refreshToken: "legacy-refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )

        try await keychain.store(token, for: "acc-1")

        // Retrieve using legacy API
        let retrieved = try await keychain.retrieve(for: "acc-1")

        #expect(retrieved != nil)
        #expect(retrieved?.accessToken == "legacy-access-token")
        #expect(retrieved?.refreshToken == "legacy-refresh-token")
    }

    @Test("App password credential returns nil via legacy OAuthToken API")
    func appPasswordReturnsNilViaLegacyAPI() async throws {
        let keychain = MockKeychainManager()

        // Store as app password
        try await keychain.storeCredential(.password("my-app-password"), for: "acc-2")

        // Legacy API returns nil for non-OAuth credentials
        let legacyToken = try await keychain.retrieve(for: "acc-2")
        #expect(legacyToken == nil)

        // New API returns the credential
        let credential = try await keychain.retrieveCredential(for: "acc-2")
        if case .password(let pw) = credential {
            #expect(pw == "my-app-password")
        } else {
            Issue.record("Expected .password credential")
        }
    }

    @Test("Update via legacy API preserves credential type as OAuth")
    func legacyUpdatePreservesOAuth() async throws {
        let keychain = MockKeychainManager()
        let original = OAuthToken(
            accessToken: "original",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )

        try await keychain.store(original, for: "acc-1")

        let updated = OAuthToken(
            accessToken: "refreshed",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(7200)
        )
        try await keychain.update(updated, for: "acc-1")

        let credential = try await keychain.retrieveCredential(for: "acc-1")
        if case .oauth(let token) = credential {
            #expect(token.accessToken == "refreshed")
        } else {
            Issue.record("Expected .oauth credential after update")
        }
    }

    @Test("Delete via legacy API removes credential")
    func legacyDeleteRemovesCredential() async throws {
        let keychain = MockKeychainManager()
        try await keychain.store(
            OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: Date()),
            for: "acc-1"
        )

        try await keychain.delete(for: "acc-1")

        let credential = try await keychain.retrieveCredential(for: "acc-1")
        #expect(credential == nil)
    }

    // MARK: - Full Flow: Old Account + Old Token → Credential Resolution

    @Test("Old-format Gmail Account + OAuth token resolves to XOAUTH2 IMAP credential")
    func oldGmailAccountResolvesToXOAUTH2() async throws {
        let keychain = MockKeychainManager()
        let account = Account(
            email: "user@gmail.com",
            displayName: "Gmail User",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587
        )

        // Store OAuth token (legacy format)
        try await keychain.store(
            OAuthToken(
                accessToken: "ya29.test-token",
                refreshToken: "1//refresh",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            for: account.id
        )

        // Resolve IMAP credential (as use cases do)
        guard let credential = try await keychain.retrieveCredential(for: account.id) else {
            Issue.record("No credential found")
            return
        }

        let imapCredential: IMAPCredential
        switch credential {
        case .oauth(let token):
            imapCredential = .xoauth2(email: account.email, accessToken: token.accessToken)
        case .password(let pw):
            imapCredential = .plain(username: account.email, password: pw)
        }

        // Verify correct resolution
        #expect(account.resolvedProvider == .gmail)
        #expect(account.resolvedImapSecurity == .tls)
        if case .xoauth2(let email, let accessToken) = imapCredential {
            #expect(email == "user@gmail.com")
            #expect(accessToken == "ya29.test-token")
        } else {
            Issue.record("Expected XOAUTH2 credential")
        }
    }

    @Test("New iCloud Account + app password resolves to PLAIN IMAP credential")
    func icloudAccountResolvesToPLAIN() async throws {
        let keychain = MockKeychainManager()
        let account = Account(
            email: "user@icloud.com",
            displayName: "iCloud User",
            imapHost: "imap.mail.me.com",
            imapPort: 993,
            smtpHost: "smtp.mail.me.com",
            smtpPort: 587
        )
        account.provider = ProviderIdentifier.icloud.rawValue
        account.smtpSecurity = ConnectionSecurity.starttls.rawValue

        // Store app password
        try await keychain.storeCredential(.password("abcd-efgh-ijkl-mnop"), for: account.id)

        // Resolve
        guard let credential = try await keychain.retrieveCredential(for: account.id) else {
            Issue.record("No credential found")
            return
        }

        let imapCredential: IMAPCredential
        switch credential {
        case .oauth(let token):
            imapCredential = .xoauth2(email: account.email, accessToken: token.accessToken)
        case .password(let pw):
            imapCredential = .plain(username: account.email, password: pw)
        }

        #expect(account.resolvedProvider == .icloud)
        #expect(account.resolvedImapSecurity == .tls)
        #expect(account.resolvedSmtpSecurity == .starttls)
        if case .plain(let username, let password) = imapCredential {
            #expect(username == "user@icloud.com")
            #expect(password == "abcd-efgh-ijkl-mnop")
        } else {
            Issue.record("Expected PLAIN credential")
        }
    }

    // MARK: - AccountCredential Codable

    @Test("AccountCredential.oauth round-trips through Codable")
    func oauthCredentialCodable() throws {
        let token = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1700000000)
        )
        let credential = AccountCredential.oauth(token)

        let data = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(AccountCredential.self, from: data)

        #expect(decoded == credential)
        if case .oauth(let decodedToken) = decoded {
            #expect(decodedToken.accessToken == "access")
            #expect(decodedToken.refreshToken == "refresh")
        }
    }

    @Test("AccountCredential.password round-trips through Codable")
    func passwordCredentialCodable() throws {
        let credential = AccountCredential.password("my-secret-password")

        let data = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(AccountCredential.self, from: data)

        #expect(decoded == credential)
        if case .password(let pw) = decoded {
            #expect(pw == "my-secret-password")
        }
    }

    @Test("AccountCredential.needsRefresh returns true for expired OAuth")
    func needsRefreshForExpiredOAuth() {
        let expired = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-60) // expired 1 min ago
        )
        let credential = AccountCredential.oauth(expired)
        #expect(credential.needsRefresh == true)
    }

    @Test("AccountCredential.needsRefresh returns false for valid OAuth")
    func noRefreshNeededForValidOAuth() {
        let valid = OAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600) // expires in 1 hour
        )
        let credential = AccountCredential.oauth(valid)
        #expect(credential.needsRefresh == false)
    }

    @Test("AccountCredential.needsRefresh returns false for password")
    func noRefreshNeededForPassword() {
        let credential = AccountCredential.password("password")
        #expect(credential.needsRefresh == false)
    }
}
