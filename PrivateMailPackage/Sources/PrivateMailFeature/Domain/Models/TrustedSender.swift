import Foundation
import SwiftData

/// Stores per-sender "Always Load Remote Images" preference.
///
/// Feature-local entity introduced by Email Detail spec (not Foundation).
/// Local-only — not synced via IMAP.
///
/// Spec ref: Email Detail FR-ED-04
@Model
public final class TrustedSender {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Sender email address (exact match key)
    public var senderEmail: String
    /// When the preference was created
    public var createdDate: Date

    public init(
        id: String = UUID().uuidString,
        senderEmail: String,
        createdDate: Date = .now
    ) {
        self.id = id
        self.senderEmail = senderEmail
        self.createdDate = createdDate
    }
}
