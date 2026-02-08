import Foundation

/// Errors specific to email detail operations.
///
/// Spec ref: Email Detail FR-ED-01
public enum EmailDetailError: Error, Sendable, Equatable {
    /// Thread not found by ID (defensive — should not happen in normal flow).
    case threadNotFound(id: String)
    /// Failed to load thread data from local store.
    case loadFailed(String)
    /// Failed to mark emails as read.
    case markReadFailed(String)
    /// Thread action failed (archive, delete, star, etc.).
    case actionFailed(String)
    /// Attachment download failed.
    case downloadFailed(String)
}
