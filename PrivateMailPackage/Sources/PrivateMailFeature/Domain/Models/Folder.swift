import Foundation
import SwiftData

/// An IMAP folder (Gmail label) belonging to an account.
///
/// Spec ref: Foundation spec Section 5.1
@Model
public final class Folder {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Human-readable folder name
    public var name: String
    /// IMAP path (e.g., "[Gmail]/Sent Mail")
    public var imapPath: String
    /// Number of unread messages in this folder
    public var unreadCount: Int
    /// Total number of messages in this folder
    public var totalCount: Int
    /// Folder type classification (raw value of FolderType)
    public var folderType: String
    /// IMAP UIDVALIDITY value for incremental sync (Section 5.4)
    public var uidValidity: Int
    /// Last successful sync date for this folder
    public var lastSyncDate: Date?

    /// Parent account
    public var account: Account?

    /// Email-folder associations (join table for many-to-many Email↔Folder).
    /// Cascade: deleting a Folder deletes its EmailFolder join entries.
    @Relationship(deleteRule: .cascade, inverse: \EmailFolder.folder)
    public var emailFolders: [EmailFolder]

    public init(
        id: String = UUID().uuidString,
        name: String,
        imapPath: String,
        unreadCount: Int = 0,
        totalCount: Int = 0,
        folderType: String = FolderType.custom.rawValue,
        uidValidity: Int = 0,
        lastSyncDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.imapPath = imapPath
        self.unreadCount = unreadCount
        self.totalCount = totalCount
        self.folderType = folderType
        self.uidValidity = uidValidity
        self.lastSyncDate = lastSyncDate
        self.emailFolders = []
    }
}
