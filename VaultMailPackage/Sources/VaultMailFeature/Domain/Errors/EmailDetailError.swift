import Foundation

/// Errors specific to email detail operations.
///
/// Spec ref: Email Detail FR-ED-01
public enum EmailDetailError: Error, Sendable, Equatable, LocalizedError {
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

    public var errorDescription: String? {
        switch self {
        case .threadNotFound(let id):
            "Thread not found: \(id)"
        case .loadFailed(let msg):
            "Failed to load: \(msg)"
        case .markReadFailed(let msg):
            "Failed to mark as read: \(msg)"
        case .actionFailed(let msg):
            "Action failed: \(msg)"
        case .downloadFailed(let msg):
            "Download failed: \(msg)"
        }
    }
}
