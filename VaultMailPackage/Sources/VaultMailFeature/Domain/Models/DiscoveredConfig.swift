import Foundation

/// The source tier that successfully discovered the configuration.
///
/// Used for diagnostics and to inform the user how reliable the config is.
///
/// Spec ref: FR-MPROV-08 (Provider Auto-Discovery)
public enum DiscoverySource: String, Sendable, Codable, Equatable {
    /// Matched a known provider from the static registry (most reliable).
    case staticRegistry
    /// Discovered via Mozilla ISPDB (Thunderbird autoconfig database).
    case ispdb
    /// Discovered via DNS SRV records or MX fallback.
    case dns
    /// User entered manually (no auto-discovery matched).
    case manual
}

/// Result of auto-discovery for an email domain.
///
/// Contains the discovered IMAP/SMTP settings and the source tier
/// that produced them. Used to pre-fill the manual setup form
/// or to directly configure an account.
///
/// Spec ref: FR-MPROV-08 (Provider Auto-Discovery)
public struct DiscoveredConfig: Sendable, Equatable {
    /// IMAP server hostname
    public let imapHost: String
    /// IMAP server port
    public let imapPort: Int
    /// IMAP connection security mode
    public let imapSecurity: ConnectionSecurity
    /// SMTP server hostname
    public let smtpHost: String
    /// SMTP server port
    public let smtpPort: Int
    /// SMTP connection security mode
    public let smtpSecurity: ConnectionSecurity
    /// Authentication method (XOAUTH2 or PLAIN)
    public let authMethod: AuthMethod
    /// Which discovery tier found this configuration
    public let source: DiscoverySource
    /// Display name of the provider (if known)
    public let displayName: String?

    public init(
        imapHost: String,
        imapPort: Int,
        imapSecurity: ConnectionSecurity,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: ConnectionSecurity,
        authMethod: AuthMethod,
        source: DiscoverySource,
        displayName: String? = nil
    ) {
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapSecurity = imapSecurity
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpSecurity = smtpSecurity
        self.authMethod = authMethod
        self.source = source
        self.displayName = displayName
    }
}

// MARK: - ProviderConfiguration Convenience

extension ProviderConfiguration {
    /// Converts a static provider config to a DiscoveredConfig.
    func toDiscoveredConfig() -> DiscoveredConfig {
        DiscoveredConfig(
            imapHost: imapHost,
            imapPort: imapPort,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            smtpSecurity: smtpSecurity,
            authMethod: authMethod,
            source: .staticRegistry,
            displayName: displayName
        )
    }
}
