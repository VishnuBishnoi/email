import Foundation
import SwiftData

/// Cached contact entry for privacy-preserving autocomplete.
///
/// Populated exclusively from email headers (From, To, CC) during
/// email sync. NO system Contacts access, NO external lookups.
///
/// Each entry is scoped to an account and cascade-deleted when
/// the account is removed.
///
/// Spec ref: Email Composer spec FR-COMP-04
@Model
public final class ContactCacheEntry {
    /// Unique identifier.
    @Attribute(.unique) public var id: String
    /// Account this contact belongs to.
    public var accountId: String
    /// Email address.
    public var emailAddress: String
    /// Display name (from email headers).
    public var displayName: String?
    /// Last time this contact appeared in synced emails.
    public var lastSeenDate: Date
    /// Number of times this contact appeared (for ranking).
    public var frequency: Int

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        emailAddress: String,
        displayName: String? = nil,
        lastSeenDate: Date = Date(),
        frequency: Int = 1
    ) {
        self.id = id
        self.accountId = accountId
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.lastSeenDate = lastSeenDate
        self.frequency = frequency
    }
}
