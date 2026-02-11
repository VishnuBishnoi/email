import Foundation

/// Error types for email composition operations.
///
/// Follows the same pattern as `ThreadListError` — wraps underlying
/// errors with context-specific cases.
///
/// Spec ref: Email Composer spec FR-COMP-01, FR-COMP-02
public enum ComposerError: Error, Sendable, Equatable, LocalizedError {
    /// Draft save failed (auto-save or manual save).
    case saveDraftFailed(String)
    /// Email send failed (SMTP pipeline error).
    case sendFailed(String)
    /// Draft deletion failed.
    case deleteDraftFailed(String)
    /// Invalid email address format.
    case invalidRecipient(String)
    /// Total attachment size exceeds limit.
    case attachmentTooLarge(totalMB: Int)
    /// Contact autocomplete query failed.
    case contactQueryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .saveDraftFailed(let msg):
            "Failed to save draft: \(msg)"
        case .sendFailed(let msg):
            "Failed to send email: \(msg)"
        case .deleteDraftFailed(let msg):
            "Failed to delete draft: \(msg)"
        case .invalidRecipient(let addr):
            "Invalid recipient: \(addr)"
        case .attachmentTooLarge(let mb):
            "Attachments too large: \(mb) MB exceeds limit"
        case .contactQueryFailed(let msg):
            "Contact query failed: \(msg)"
        }
    }
}
