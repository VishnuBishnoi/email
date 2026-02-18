import Foundation

/// Static registry of known email provider configurations.
///
/// Shipped with the app — no network calls required. Provides O(1) lookup
/// by email domain and by provider identifier.
///
/// Supported providers (FR-MPROV-01):
/// - **Gmail**: XOAUTH2, port 993/465, 15 connections, 25-min IDLE
/// - **Outlook**: XOAUTH2, port 993/587(STARTTLS), 8 connections, 25-min IDLE
/// - **Yahoo**: PLAIN, port 993/465, 5 connections, 4-min IDLE
/// - **iCloud**: PLAIN, port 993/587(STARTTLS), 10 connections, 25-min IDLE
///
/// Unknown domains return `nil` — the caller should attempt auto-discovery
/// or fall back to manual configuration.
///
/// Spec ref: FR-MPROV-01 (Provider Configuration Registry)
public enum ProviderRegistry {

    // MARK: - Static Configs

    /// Gmail configuration.
    ///
    /// - Auth: XOAUTH2
    /// - IMAP: imap.gmail.com:993 (TLS)
    /// - SMTP: smtp.gmail.com:465 (TLS)
    /// - Gmail auto-copies sent messages; IDLE drops at ~29 min
    public static let gmail = ProviderConfiguration(
        identifier: .gmail,
        displayName: "Gmail",
        domains: ["gmail.com", "googlemail.com"],
        imapHost: "imap.gmail.com",
        imapPort: 993,
        imapSecurity: .tls,
        smtpHost: "smtp.gmail.com",
        smtpPort: 465,
        smtpSecurity: .tls,
        authMethod: .xoauth2,
        maxConnectionsPerAccount: 15,
        idleRefreshInterval: 25 * 60,
        requiresSentAppend: false,
        archiveBehavior: .gmailLabel
    )

    /// Outlook/Hotmail configuration.
    ///
    /// - Auth: XOAUTH2 (blocked on Azure AD client ID — OQ-01)
    /// - IMAP: outlook.office365.com:993 (TLS)
    /// - SMTP: smtp.office365.com:587 (STARTTLS)
    public static let outlook = ProviderConfiguration(
        identifier: .outlook,
        displayName: "Outlook",
        domains: ["outlook.com", "hotmail.com", "live.com", "msn.com"],
        imapHost: "outlook.office365.com",
        imapPort: 993,
        imapSecurity: .tls,
        smtpHost: "smtp.office365.com",
        smtpPort: 587,
        smtpSecurity: .starttls,
        authMethod: .xoauth2,
        maxConnectionsPerAccount: 8,
        idleRefreshInterval: 25 * 60,
        requiresSentAppend: true,
        archiveBehavior: .moveToArchive
    )

    /// Yahoo Mail configuration.
    ///
    /// - Auth: PLAIN (app password required)
    /// - IMAP: imap.mail.yahoo.com:993 (TLS)
    /// - SMTP: smtp.mail.yahoo.com:465 (TLS)
    /// - Short IDLE timeout (~4 min)
    public static let yahoo = ProviderConfiguration(
        identifier: .yahoo,
        displayName: "Yahoo Mail",
        domains: ["yahoo.com", "yahoo.co.uk", "yahoo.co.jp", "ymail.com", "rocketmail.com"],
        imapHost: "imap.mail.yahoo.com",
        imapPort: 993,
        imapSecurity: .tls,
        smtpHost: "smtp.mail.yahoo.com",
        smtpPort: 465,
        smtpSecurity: .tls,
        authMethod: .plain,
        maxConnectionsPerAccount: 5,
        idleRefreshInterval: 4 * 60,
        requiresSentAppend: true,
        archiveBehavior: .moveToArchive,
        appPasswordHelpURL: URL(string: "https://help.yahoo.com/kb/generate-manage-third-party-passwords-sln15241.html")
    )

    /// iCloud Mail configuration.
    ///
    /// - Auth: PLAIN (app-specific password required)
    /// - IMAP: imap.mail.me.com:993 (TLS)
    /// - SMTP: smtp.mail.me.com:587 (STARTTLS)
    public static let icloud = ProviderConfiguration(
        identifier: .icloud,
        displayName: "iCloud Mail",
        domains: ["icloud.com", "me.com", "mac.com"],
        imapHost: "imap.mail.me.com",
        imapPort: 993,
        imapSecurity: .tls,
        smtpHost: "smtp.mail.me.com",
        smtpPort: 587,
        smtpSecurity: .starttls,
        authMethod: .plain,
        maxConnectionsPerAccount: 10,
        idleRefreshInterval: 25 * 60,
        requiresSentAppend: true,
        archiveBehavior: .moveToArchive,
        appPasswordHelpURL: URL(string: "https://support.apple.com/en-us/102654")
    )

    /// All known provider configurations.
    public static let allProviders: [ProviderConfiguration] = [
        gmail, outlook, yahoo, icloud
    ]

    // MARK: - Domain Lookup (Cached)

    /// Pre-built domain → config map for O(1) lookup.
    private static let domainMap: [String: ProviderConfiguration] = {
        var map: [String: ProviderConfiguration] = [:]
        for config in allProviders {
            for domain in config.domains {
                map[domain.lowercased()] = config
            }
        }
        return map
    }()

    // MARK: - Lookup Methods

    /// Returns the provider configuration for an email address.
    ///
    /// Extracts the domain from the email and looks it up in the registry.
    /// Returns `nil` for unknown domains (caller should try auto-discovery).
    ///
    /// - Parameter email: Full email address (e.g., "user@gmail.com")
    /// - Returns: Provider configuration, or `nil` if the domain is unknown.
    public static func provider(for email: String) -> ProviderConfiguration? {
        guard let atIndex = email.lastIndex(of: "@") else { return nil }
        let domain = String(email[email.index(after: atIndex)...]).lowercased()
        return domainMap[domain]
    }

    /// Returns the provider configuration for a known identifier.
    ///
    /// - Parameter identifier: The provider identifier (e.g., `.gmail`)
    /// - Returns: Provider configuration, or `nil` for `.custom`.
    public static func provider(for identifier: ProviderIdentifier) -> ProviderConfiguration? {
        switch identifier {
        case .gmail: return gmail
        case .outlook: return outlook
        case .yahoo: return yahoo
        case .icloud: return icloud
        case .custom: return nil
        }
    }

    /// Creates a provider configuration for a manually configured server.
    ///
    /// Used when auto-discovery fails and the user enters settings manually.
    ///
    /// - Parameters:
    ///   - imapHost: IMAP server hostname
    ///   - imapPort: IMAP server port
    ///   - imapSecurity: IMAP connection security mode
    ///   - smtpHost: SMTP server hostname
    ///   - smtpPort: SMTP server port
    ///   - smtpSecurity: SMTP connection security mode
    ///   - authMethod: Authentication method (default: `.plain`)
    /// - Returns: A custom provider configuration.
    public static func customProvider(
        imapHost: String,
        imapPort: Int,
        imapSecurity: ConnectionSecurity,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: ConnectionSecurity,
        authMethod: AuthMethod = .plain
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            identifier: .custom,
            displayName: "Custom",
            domains: [],
            imapHost: imapHost,
            imapPort: imapPort,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            smtpSecurity: smtpSecurity,
            authMethod: authMethod,
            maxConnectionsPerAccount: 5,
            idleRefreshInterval: 20 * 60,
            requiresSentAppend: true,
            archiveBehavior: .moveToArchive
        )
    }
}
