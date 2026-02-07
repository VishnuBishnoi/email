import Foundation
import SwiftData

/// Join entity for the many-to-many relationship between Email and Folder.
///
/// In Gmail, a single email can have multiple labels (folders), and each
/// label contains multiple emails. The `imapUID` is folder-scoped — the same
/// email (by `messageId`) can have different UIDs in different folders.
///
/// Spec ref: Foundation spec Sections 5.1, 5.4
@Model
public final class EmailFolder {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// IMAP UID for this email within this specific folder (folder-scoped)
    public var imapUID: Int

    /// The email in this association
    public var email: Email?
    /// The folder in this association
    public var folder: Folder?

    public init(
        id: String = UUID().uuidString,
        imapUID: Int = 0
    ) {
        self.id = id
        self.imapUID = imapUID
    }
}
