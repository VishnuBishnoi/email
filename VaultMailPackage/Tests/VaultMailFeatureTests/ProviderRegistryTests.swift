import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for ProviderRegistry — the static email provider configuration registry.
///
/// Validates domain lookup, provider identifier lookup, custom provider factory,
/// and that all known provider configs are correct per the multi-provider spec.
///
/// Spec ref: FR-MPROV-01 (Provider Configuration Registry)
@Suite("ProviderRegistry — FR-MPROV-01")
struct ProviderRegistryTests {

    // MARK: - Domain Lookup

    @Test("Gmail domain lookup returns Gmail config")
    func gmailDomainLookup() {
        let config = ProviderRegistry.provider(for: "user@gmail.com")
        #expect(config != nil)
        #expect(config?.identifier == .gmail)
        #expect(config?.displayName == "Gmail")
    }

    @Test("Googlemail domain maps to Gmail")
    func googlemailDomain() {
        let config = ProviderRegistry.provider(for: "user@googlemail.com")
        #expect(config?.identifier == .gmail)
    }

    @Test("Outlook domain lookup returns Outlook config")
    func outlookDomainLookup() {
        let config = ProviderRegistry.provider(for: "user@outlook.com")
        #expect(config != nil)
        #expect(config?.identifier == .outlook)
    }

    @Test("Hotmail domain maps to Outlook")
    func hotmailDomain() {
        let config = ProviderRegistry.provider(for: "user@hotmail.com")
        #expect(config?.identifier == .outlook)
    }

    @Test("Live.com domain maps to Outlook")
    func liveDomain() {
        let config = ProviderRegistry.provider(for: "user@live.com")
        #expect(config?.identifier == .outlook)
    }

    @Test("Yahoo domain lookup returns Yahoo config")
    func yahooDomainLookup() {
        let config = ProviderRegistry.provider(for: "user@yahoo.com")
        #expect(config != nil)
        #expect(config?.identifier == .yahoo)
    }

    @Test("Yahoo UK domain maps to Yahoo")
    func yahooUKDomain() {
        let config = ProviderRegistry.provider(for: "user@yahoo.co.uk")
        #expect(config?.identifier == .yahoo)
    }

    @Test("ymail domain maps to Yahoo")
    func ymailDomain() {
        let config = ProviderRegistry.provider(for: "user@ymail.com")
        #expect(config?.identifier == .yahoo)
    }

    @Test("iCloud domain lookup returns iCloud config")
    func icloudDomainLookup() {
        let config = ProviderRegistry.provider(for: "user@icloud.com")
        #expect(config != nil)
        #expect(config?.identifier == .icloud)
    }

    @Test("me.com domain maps to iCloud")
    func meDomain() {
        let config = ProviderRegistry.provider(for: "user@me.com")
        #expect(config?.identifier == .icloud)
    }

    @Test("mac.com domain maps to iCloud")
    func macDomain() {
        let config = ProviderRegistry.provider(for: "user@mac.com")
        #expect(config?.identifier == .icloud)
    }

    @Test("Unknown domain returns nil")
    func unknownDomain() {
        let config = ProviderRegistry.provider(for: "user@example.com")
        #expect(config == nil)
    }

    @Test("Invalid email without @ returns nil")
    func invalidEmail() {
        let config = ProviderRegistry.provider(for: "not-an-email")
        #expect(config == nil)
    }

    @Test("Domain lookup is case-insensitive")
    func caseInsensitiveLookup() {
        let config = ProviderRegistry.provider(for: "user@Gmail.COM")
        #expect(config?.identifier == .gmail)
    }

    // MARK: - Identifier Lookup

    @Test("Lookup by .gmail identifier returns Gmail config")
    func gmailIdentifierLookup() {
        let config = ProviderRegistry.provider(for: .gmail)
        #expect(config != nil)
        #expect(config?.imapHost == "imap.gmail.com")
    }

    @Test("Lookup by .outlook identifier returns Outlook config")
    func outlookIdentifierLookup() {
        let config = ProviderRegistry.provider(for: .outlook)
        #expect(config != nil)
        #expect(config?.imapHost == "outlook.office365.com")
    }

    @Test("Lookup by .yahoo identifier returns Yahoo config")
    func yahooIdentifierLookup() {
        let config = ProviderRegistry.provider(for: .yahoo)
        #expect(config != nil)
        #expect(config?.imapHost == "imap.mail.yahoo.com")
    }

    @Test("Lookup by .icloud identifier returns iCloud config")
    func icloudIdentifierLookup() {
        let config = ProviderRegistry.provider(for: .icloud)
        #expect(config != nil)
        #expect(config?.imapHost == "imap.mail.me.com")
    }

    @Test("Lookup by .custom identifier returns nil")
    func customIdentifierLookup() {
        let config = ProviderRegistry.provider(for: .custom)
        #expect(config == nil)
    }

    // MARK: - Custom Provider Factory

    @Test("customProvider creates a valid configuration")
    func customProviderFactory() {
        let config = ProviderRegistry.customProvider(
            imapHost: "mail.example.com",
            imapPort: 993,
            imapSecurity: .tls,
            smtpHost: "smtp.example.com",
            smtpPort: 587,
            smtpSecurity: .starttls
        )

        #expect(config.identifier == .custom)
        #expect(config.imapHost == "mail.example.com")
        #expect(config.imapPort == 993)
        #expect(config.imapSecurity == .tls)
        #expect(config.smtpHost == "smtp.example.com")
        #expect(config.smtpPort == 587)
        #expect(config.smtpSecurity == .starttls)
        #expect(config.authMethod == .plain) // Default for custom
        #expect(config.requiresSentAppend == true)
        #expect(config.archiveBehavior == .moveToArchive)
        #expect(config.maxConnectionsPerAccount == 5)
    }

    // MARK: - Gmail Config Validation

    @Test("Gmail config has correct settings")
    func gmailConfig() {
        let gmail = ProviderRegistry.gmail
        #expect(gmail.identifier == .gmail)
        #expect(gmail.imapHost == "imap.gmail.com")
        #expect(gmail.imapPort == 993)
        #expect(gmail.imapSecurity == .tls)
        #expect(gmail.smtpHost == "smtp.gmail.com")
        #expect(gmail.smtpPort == 465)
        #expect(gmail.smtpSecurity == .tls)
        #expect(gmail.authMethod == .xoauth2)
        #expect(gmail.maxConnectionsPerAccount == 15)
        #expect(gmail.idleRefreshInterval == 25 * 60)
        #expect(gmail.requiresSentAppend == false) // Gmail auto-copies
        #expect(gmail.archiveBehavior == .gmailLabel)
    }

    // MARK: - Outlook Config Validation

    @Test("Outlook config has correct settings")
    func outlookConfig() {
        let outlook = ProviderRegistry.outlook
        #expect(outlook.identifier == .outlook)
        #expect(outlook.imapHost == "outlook.office365.com")
        #expect(outlook.imapPort == 993)
        #expect(outlook.imapSecurity == .tls)
        #expect(outlook.smtpHost == "smtp.office365.com")
        #expect(outlook.smtpPort == 587)
        #expect(outlook.smtpSecurity == .starttls)
        #expect(outlook.authMethod == .xoauth2)
        #expect(outlook.maxConnectionsPerAccount == 8)
        #expect(outlook.requiresSentAppend == true)
        #expect(outlook.archiveBehavior == .moveToArchive)
    }

    // MARK: - Yahoo Config Validation

    @Test("Yahoo config has correct settings")
    func yahooConfig() {
        let yahoo = ProviderRegistry.yahoo
        #expect(yahoo.identifier == .yahoo)
        #expect(yahoo.imapHost == "imap.mail.yahoo.com")
        #expect(yahoo.imapPort == 993)
        #expect(yahoo.imapSecurity == .tls)
        #expect(yahoo.smtpHost == "smtp.mail.yahoo.com")
        #expect(yahoo.smtpPort == 465)
        #expect(yahoo.smtpSecurity == .tls)
        #expect(yahoo.authMethod == .plain)
        #expect(yahoo.maxConnectionsPerAccount == 5)
        #expect(yahoo.idleRefreshInterval == 4 * 60) // Short IDLE
        #expect(yahoo.requiresSentAppend == true)
        #expect(yahoo.appPasswordHelpURL != nil)
    }

    // MARK: - iCloud Config Validation

    @Test("iCloud config has correct settings")
    func icloudConfig() {
        let icloud = ProviderRegistry.icloud
        #expect(icloud.identifier == .icloud)
        #expect(icloud.imapHost == "imap.mail.me.com")
        #expect(icloud.imapPort == 993)
        #expect(icloud.imapSecurity == .tls)
        #expect(icloud.smtpHost == "smtp.mail.me.com")
        #expect(icloud.smtpPort == 587)
        #expect(icloud.smtpSecurity == .starttls)
        #expect(icloud.authMethod == .plain)
        #expect(icloud.maxConnectionsPerAccount == 10)
        #expect(icloud.requiresSentAppend == true)
        #expect(icloud.appPasswordHelpURL != nil)
    }

    // MARK: - All Providers

    @Test("allProviders contains exactly 4 providers")
    func allProvidersCount() {
        #expect(ProviderRegistry.allProviders.count == 4)
    }

    @Test("Every domain across all providers maps to correct provider")
    func allDomainsMapCorrectly() {
        for provider in ProviderRegistry.allProviders {
            for domain in provider.domains {
                let result = ProviderRegistry.provider(for: "test@\(domain)")
                #expect(result?.identifier == provider.identifier,
                       "Domain \(domain) should map to \(provider.identifier)")
            }
        }
    }
}
