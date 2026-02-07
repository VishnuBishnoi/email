import Foundation

/// Provider-agnostic folder type classification.
///
/// Spec ref: Foundation spec Section 5.3
public enum FolderType: String, Codable, CaseIterable, Sendable {
    /// INBOX (Gmail: INBOX)
    case inbox
    /// Sent mail (Gmail: [Gmail]/Sent Mail)
    case sent
    /// Drafts (Gmail: [Gmail]/Drafts)
    case drafts
    /// Trash (Gmail: [Gmail]/Trash)
    case trash
    /// Spam (Gmail: [Gmail]/Spam)
    case spam
    /// Archive / All Mail (Gmail: [Gmail]/All Mail)
    case archive
    /// Starred (Gmail: [Gmail]/Starred)
    case starred
    /// User-created labels
    case custom
}
