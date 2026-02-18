import Foundation
import Testing
import SwiftData
@testable import VaultMailFeature

/// Tests for Account model multi-provider extensions (FR-MPROV-04).
///
/// Validates that:
/// 1. Nil fields resolve to Gmail/TLS defaults (backward compatibility)
/// 2. Explicit values are returned correctly
/// 3. ProviderConfiguration convenience init works
/// 4. SwiftData round-trip preserves new fields
@Suite("Account Model Extensions — FR-MPROV-04")
@MainActor
struct AccountModelExtensionTests {

    // MARK: - Nil Resolution (Backward Compatibility)

    @Test("Nil provider resolves to .gmail")
    func nilProviderResolvesToGmail() {
        let account = Account(email: "user@gmail.com", displayName: "Test")
        #expect(account.provider == nil)
        #expect(account.resolvedProvider == .gmail)
    }

    @Test("Nil imapSecurity resolves to .tls")
    func nilImapSecurityResolvesToTLS() {
        let account = Account(email: "user@gmail.com", displayName: "Test")
        #expect(account.imapSecurity == nil)
        #expect(account.resolvedImapSecurity == .tls)
    }

    @Test("Nil smtpSecurity resolves to .tls")
    func nilSmtpSecurityResolvesToTLS() {
        let account = Account(email: "user@gmail.com", displayName: "Test")
        #expect(account.smtpSecurity == nil)
        #expect(account.resolvedSmtpSecurity == .tls)
    }

    @Test("Default authType resolves to .xoauth2")
    func defaultAuthMethodResolvesToXOAuth2() {
        let account = Account(email: "user@gmail.com", displayName: "Test")
        #expect(account.authType == "xoauth2")
        #expect(account.resolvedAuthMethod == .xoauth2)
    }

    // MARK: - Explicit Values

    @Test("Explicit provider is returned correctly")
    func explicitProvider() {
        let account = Account(
            email: "user@yahoo.com",
            displayName: "Yahoo User",
            provider: "yahoo"
        )
        #expect(account.resolvedProvider == .yahoo)
    }

    @Test("Explicit imapSecurity is returned correctly")
    func explicitImapSecurity() {
        let account = Account(
            email: "user@example.com",
            displayName: "Test",
            imapSecurity: "starttls"
        )
        #expect(account.resolvedImapSecurity == .starttls)
    }

    @Test("Explicit smtpSecurity is returned correctly")
    func explicitSmtpSecurity() {
        let account = Account(
            email: "user@example.com",
            displayName: "Test",
            smtpSecurity: "starttls"
        )
        #expect(account.resolvedSmtpSecurity == .starttls)
    }

    @Test("PLAIN authType resolves correctly")
    func plainAuthType() {
        let account = Account(
            email: "user@yahoo.com",
            displayName: "Test",
            authType: "plain"
        )
        #expect(account.resolvedAuthMethod == .plain)
    }

    @Test("Invalid provider string falls back to .gmail")
    func invalidProviderFallback() {
        let account = Account(
            email: "user@test.com",
            displayName: "Test",
            provider: "nonexistent_provider"
        )
        #expect(account.resolvedProvider == .gmail)
    }

    @Test("Invalid security string falls back to .tls")
    func invalidSecurityFallback() {
        let account = Account(
            email: "user@test.com",
            displayName: "Test",
            imapSecurity: "invalid",
            smtpSecurity: "invalid"
        )
        #expect(account.resolvedImapSecurity == .tls)
        #expect(account.resolvedSmtpSecurity == .tls)
    }

    // MARK: - ProviderConfiguration Convenience Init

    @Test("Init from ProviderConfiguration sets all fields")
    func initFromProviderConfig() {
        let config = ProviderRegistry.yahoo
        let account = Account(
            email: "user@yahoo.com",
            displayName: "Yahoo User",
            providerConfig: config
        )

        #expect(account.imapHost == "imap.mail.yahoo.com")
        #expect(account.imapPort == 993)
        #expect(account.smtpHost == "smtp.mail.yahoo.com")
        #expect(account.smtpPort == 465)
        #expect(account.authType == "plain")
        #expect(account.provider == "yahoo")
        #expect(account.imapSecurity == "tls")
        #expect(account.smtpSecurity == "tls")
        #expect(account.resolvedProvider == .yahoo)
        #expect(account.resolvedAuthMethod == .plain)
    }

    @Test("Init from iCloud config sets STARTTLS for SMTP")
    func initFromICloudConfig() {
        let config = ProviderRegistry.icloud
        let account = Account(
            email: "user@icloud.com",
            displayName: "iCloud User",
            providerConfig: config
        )

        #expect(account.smtpSecurity == "starttls")
        #expect(account.resolvedSmtpSecurity == .starttls)
        #expect(account.smtpPort == 587)
    }

    @Test("Init from custom provider config sets correct values")
    func initFromCustomConfig() {
        let config = ProviderRegistry.customProvider(
            imapHost: "mail.custom.org",
            imapPort: 143,
            imapSecurity: .starttls,
            smtpHost: "smtp.custom.org",
            smtpPort: 587,
            smtpSecurity: .starttls
        )
        let account = Account(
            email: "user@custom.org",
            displayName: "Custom User",
            providerConfig: config
        )

        #expect(account.imapHost == "mail.custom.org")
        #expect(account.imapPort == 143)
        #expect(account.resolvedImapSecurity == .starttls)
        #expect(account.smtpHost == "smtp.custom.org")
        #expect(account.smtpPort == 587)
        #expect(account.resolvedSmtpSecurity == .starttls)
        #expect(account.resolvedProvider == .custom)
        #expect(account.resolvedAuthMethod == .plain)
    }

    // MARK: - SwiftData Round-Trip

    @Test("SwiftData round-trip preserves new fields")
    func swiftDataRoundTrip() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Folder.self, Email.self,
            VaultMailFeature.Thread.self, EmailFolder.self,
            Attachment.self, SearchIndex.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Create account with multi-provider fields
        let account = Account(
            email: "user@yahoo.com",
            displayName: "Yahoo Test",
            imapHost: "imap.mail.yahoo.com",
            imapPort: 993,
            smtpHost: "smtp.mail.yahoo.com",
            smtpPort: 465,
            authType: "plain",
            provider: "yahoo",
            imapSecurity: "tls",
            smtpSecurity: "tls"
        )
        context.insert(account)
        try context.save()

        // Fetch back
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.email == "user@yahoo.com" }
        )
        let fetched = try context.fetch(descriptor)
        let result = try #require(fetched.first)

        #expect(result.provider == "yahoo")
        #expect(result.imapSecurity == "tls")
        #expect(result.smtpSecurity == "tls")
        #expect(result.resolvedProvider == .yahoo)
        #expect(result.resolvedAuthMethod == .plain)
    }

    @Test("Legacy account without new fields resolves correctly after migration")
    func legacyAccountMigration() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Folder.self, Email.self,
            VaultMailFeature.Thread.self, EmailFolder.self,
            Attachment.self, SearchIndex.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Create legacy-style account (no provider/security fields)
        let account = Account(
            email: "user@gmail.com",
            displayName: "Gmail User"
        )
        context.insert(account)
        try context.save()

        // Fetch back
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.email == "user@gmail.com" }
        )
        let fetched = try context.fetch(descriptor)
        let result = try #require(fetched.first)

        // Nil fields should resolve to Gmail/TLS defaults
        #expect(result.provider == nil)
        #expect(result.imapSecurity == nil)
        #expect(result.smtpSecurity == nil)
        #expect(result.resolvedProvider == .gmail)
        #expect(result.resolvedImapSecurity == .tls)
        #expect(result.resolvedSmtpSecurity == .tls)
        #expect(result.resolvedAuthMethod == .xoauth2)
    }
}
