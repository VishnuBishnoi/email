import Foundation

// MARK: - Provider Identifier

/// Identifies a supported email provider.
///
/// Each identifier maps to a static `ProviderConfiguration` in the registry.
/// `.custom` is used for manually configured IMAP/SMTP servers.
///
/// Spec ref: FR-MPROV-01 (Provider Configuration Registry)
public enum ProviderIdentifier: String, Sendable, Codable, CaseIterable, Equatable {
    case gmail
    case outlook
    case yahoo
    case icloud
    case custom
}

// MARK: - Auth Type

/// Authentication mechanism for connecting to the provider.
///
/// - `.xoauth2`: OAuth 2.0 XOAUTH2 SASL mechanism (Gmail, Outlook)
/// - `.plain`: SASL PLAIN with username/app-password (Yahoo, iCloud, custom)
///
/// Spec ref: FR-MPROV-02, FR-MPROV-03
public enum AuthMethod: String, Sendable, Codable, CaseIterable, Equatable {
    /// OAuth 2.0 XOAUTH2 SASL mechanism
    case xoauth2
    /// SASL PLAIN (username + app password)
    case plain
}

// MARK: - Archive Behavior

/// How a provider handles the "archive" action.
///
/// Gmail uses label semantics (remove INBOX label). Other providers
/// physically move the message to an Archive folder.
///
/// Spec ref: FR-MPROV-12
public enum ArchiveBehavior: String, Sendable, Codable, Equatable {
    /// Gmail: Remove from INBOX (message stays in All Mail via label semantics).
    case gmailLabel
    /// Standard: COPY to Archive folder + DELETE from current folder + EXPUNGE.
    case moveToArchive
}

// MARK: - Provider Configuration

/// Static, shipped-with-app configuration for an email provider.
///
/// Defines connection endpoints, security settings, authentication method,
/// and provider-specific behaviors (IDLE interval, sent append, archive).
///
/// This is a value type — immutable after creation, thread-safe by design.
///
/// Spec ref: FR-MPROV-01 (Provider Configuration Registry)
public struct ProviderConfiguration: Sendable, Equatable {

    // MARK: - Identity

    /// Which provider this config represents.
    public let identifier: ProviderIdentifier

    /// Human-readable display name (e.g., "Gmail", "iCloud Mail").
    public let displayName: String

    /// Email domains associated with this provider (e.g., ["gmail.com", "googlemail.com"]).
    public let domains: [String]

    // MARK: - IMAP Settings

    /// IMAP server hostname (e.g., "imap.gmail.com")
    public let imapHost: String

    /// IMAP server port (993 for TLS, 143 for STARTTLS)
    public let imapPort: Int

    /// IMAP connection security mode
    public let imapSecurity: ConnectionSecurity

    // MARK: - SMTP Settings

    /// SMTP server hostname (e.g., "smtp.gmail.com")
    public let smtpHost: String

    /// SMTP server port (465 for TLS, 587 for STARTTLS)
    public let smtpPort: Int

    /// SMTP connection security mode
    public let smtpSecurity: ConnectionSecurity

    // MARK: - Authentication

    /// Authentication mechanism for this provider
    public let authMethod: AuthMethod

    // MARK: - Connection Limits

    /// Maximum concurrent IMAP connections per account.
    ///
    /// Gmail allows up to 15 simultaneous connections.
    /// Conservative defaults for other providers.
    public let maxConnectionsPerAccount: Int

    /// IMAP IDLE refresh interval in seconds.
    ///
    /// Gmail drops IDLE connections after ~29 minutes; re-issue at 25 min.
    /// Yahoo has a much shorter idle timeout (~4 min).
    public let idleRefreshInterval: TimeInterval

    // MARK: - Provider-Specific Behaviors

    /// Whether the provider requires the client to APPEND sent messages
    /// to the Sent folder after SMTP send.
    ///
    /// Gmail auto-copies to Sent Mail via label semantics — skip APPEND.
    /// All other providers require explicit APPEND.
    ///
    /// Spec ref: FR-MPROV-12
    public let requiresSentAppend: Bool

    /// How the "archive" action is implemented for this provider.
    ///
    /// Spec ref: FR-MPROV-12
    public let archiveBehavior: ArchiveBehavior

    /// Provider-specific URL for app password setup instructions.
    ///
    /// Shown during onboarding for providers that use SASL PLAIN auth.
    public let appPasswordHelpURL: URL?

    // MARK: - Init

    public init(
        identifier: ProviderIdentifier,
        displayName: String,
        domains: [String],
        imapHost: String,
        imapPort: Int,
        imapSecurity: ConnectionSecurity,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: ConnectionSecurity,
        authMethod: AuthMethod,
        maxConnectionsPerAccount: Int,
        idleRefreshInterval: TimeInterval,
        requiresSentAppend: Bool,
        archiveBehavior: ArchiveBehavior,
        appPasswordHelpURL: URL? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.domains = domains
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapSecurity = imapSecurity
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpSecurity = smtpSecurity
        self.authMethod = authMethod
        self.maxConnectionsPerAccount = maxConnectionsPerAccount
        self.idleRefreshInterval = idleRefreshInterval
        self.requiresSentAppend = requiresSentAppend
        self.archiveBehavior = archiveBehavior
        self.appPasswordHelpURL = appPasswordHelpURL
    }
}
