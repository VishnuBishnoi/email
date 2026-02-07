import Foundation
import SwiftData

/// A configured email account.
///
/// Spec ref: Foundation spec Section 5.1
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
    /// Authentication type (e.g., "xoauth2")
    public var authType: String
    /// Last successful sync date
    public var lastSyncDate: Date?
    /// Whether the account is active (false = re-authentication needed)
    public var isActive: Bool
    /// Sync window in days (7, 14, 30, 60, 90; default: 30)
    public var syncWindowDays: Int

    /// All folders belonging to this account.
    /// Cascade: deleting an Account deletes all Folders (FR-FOUND-03).
    @Relationship(deleteRule: .cascade, inverse: \Folder.account)
    public var folders: [Folder]

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
        syncWindowDays: Int = 30
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
        self.folders = []
    }
}
