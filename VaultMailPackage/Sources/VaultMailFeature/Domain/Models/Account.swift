import Foundation
import SwiftData

/// A configured email account.
///
/// Supports both OAuth providers (Gmail, Outlook) and app-password
/// providers (Yahoo, iCloud, custom IMAP). The `provider`, `imapSecurity`,
/// and `smtpSecurity` fields are nullable for backward compatibility —
/// existing Gmail accounts keep `nil` values, and computed properties
/// resolve to Gmail/TLS defaults.
///
/// SwiftData lightweight migration handles the new nullable fields
/// automatically — no manual migration code required.
///
/// Spec ref: Foundation spec Section 5.1, FR-MPROV-04
@Model
public final class Account {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Email address for this account
    public var email: String
    /// User-configurable display name
    public var displayName: String
    /// IMAP server hostname
    public var imapHost: String
    /// IMAP server port (default: 993 for TLS)
    public var imapPort: Int
    /// SMTP server hostname
    public var smtpHost: String
    /// SMTP server port (default: 465 for TLS, or 587 for STARTTLS)
    public var smtpPort: Int
    /// Authentication type (e.g., "xoauth2", "plain")
    public var authType: String
    /// Last successful sync date
    public var lastSyncDate: Date?
    /// Whether the account is active (false = re-authentication needed)
    public var isActive: Bool
    /// Sync window in days (7, 14, 30, 60, 90; default: 30)
    public var syncWindowDays: Int

    // MARK: - Multi-Provider Fields (FR-MPROV-04)

    /// Provider identifier string. `nil` means legacy Gmail account.
    ///
    /// Stored as raw `String` for SwiftData compatibility.
    /// Use `resolvedProvider` for the typed value.
    public var provider: String?

    /// IMAP connection security mode. `nil` defaults to TLS (legacy behavior).
    ///
    /// Stored as raw `String` for SwiftData compatibility.
    /// Use `resolvedImapSecurity` for the typed value.
    public var imapSecurity: String?

    /// SMTP connection security mode. `nil` defaults to TLS (legacy behavior).
    ///
    /// Stored as raw `String` for SwiftData compatibility.
    /// Use `resolvedSmtpSecurity` for the typed value.
    public var smtpSecurity: String?

    /// All folders belonging to this account.
    /// Cascade: deleting an Account deletes all Folders (FR-FOUND-03).
    @Relationship(deleteRule: .cascade, inverse: \Folder.account)
    public var folders: [Folder]

    // MARK: - Computed Properties (Safe Defaults)

    /// Resolved provider identifier with safe default.
    ///
    /// `nil` → `.gmail` (backward compatibility with V1 accounts).
    @Transient
    public var resolvedProvider: ProviderIdentifier {
        guard let raw = provider else { return .gmail }
        return ProviderIdentifier(rawValue: raw) ?? .gmail
    }

    /// Resolved IMAP connection security with safe default.
    ///
    /// `nil` → `.tls` (backward compatibility with V1 Gmail accounts).
    @Transient
    public var resolvedImapSecurity: ConnectionSecurity {
        guard let raw = imapSecurity else { return .tls }
        return ConnectionSecurity(rawValue: raw) ?? .tls
    }

    /// Resolved SMTP connection security with safe default.
    ///
    /// `nil` → `.tls` (backward compatibility with V1 Gmail accounts).
    @Transient
    public var resolvedSmtpSecurity: ConnectionSecurity {
        guard let raw = smtpSecurity else { return .tls }
        return ConnectionSecurity(rawValue: raw) ?? .tls
    }

    /// Resolved authentication method with safe default.
    ///
    /// Derives from the `authType` string field.
    @Transient
    public var resolvedAuthMethod: AuthMethod {
        AuthMethod(rawValue: authType) ?? .xoauth2
    }

    // MARK: - Init

    /// Creates a new Account.
    ///
    /// **Backward compatibility note**: The default values for `imapHost`, `imapPort`,
    /// `smtpHost`, `smtpPort`, and `authType` are Gmail-specific. These defaults exist
    /// for backward compatibility with V1 (Gmail-only) code paths and tests that
    /// create accounts without specifying server details. New multi-provider accounts
    /// should always supply explicit values via the `ProviderConfiguration` convenience
    /// initializer instead of relying on these defaults.
    public init(
        id: String = UUID().uuidString,
        email: String,
        displayName: String,
        imapHost: String = "imap.gmail.com",
        imapPort: Int = 993,
        smtpHost: String = "smtp.gmail.com",
        smtpPort: Int = 465,
        authType: String = "xoauth2",
        lastSyncDate: Date? = nil,
        isActive: Bool = true,
        syncWindowDays: Int = 30,
        provider: String? = nil,
        imapSecurity: String? = nil,
        smtpSecurity: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.authType = authType
        self.lastSyncDate = lastSyncDate
        self.isActive = isActive
        self.syncWindowDays = syncWindowDays
        self.provider = provider
        self.imapSecurity = imapSecurity
        self.smtpSecurity = smtpSecurity
        self.folders = []
    }

    // MARK: - Convenience Init (from ProviderConfiguration)

    /// Creates an Account from a provider configuration.
    ///
    /// Pre-fills host, port, security, and auth settings from the provider
    /// registry. Used during the "Add Account" flow.
    public convenience init(
        email: String,
        displayName: String,
        providerConfig: ProviderConfiguration
    ) {
        self.init(
            email: email,
            displayName: displayName,
            imapHost: providerConfig.imapHost,
            imapPort: providerConfig.imapPort,
            smtpHost: providerConfig.smtpHost,
            smtpPort: providerConfig.smtpPort,
            authType: providerConfig.authMethod.rawValue,
            provider: providerConfig.identifier.rawValue,
            imapSecurity: providerConfig.imapSecurity.rawValue,
            smtpSecurity: providerConfig.smtpSecurity.rawValue
        )
    }
}
