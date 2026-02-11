import Foundation

/// Errors specific to thread list operations.
///
/// Spec ref: Thread List spec FR-TL-01, FR-TL-03
public enum ThreadListError: Error, Sendable, Equatable, LocalizedError {
    /// Thread fetch failed (pagination, category filter, or unified query).
    case fetchFailed(String)
    /// Thread action failed (archive, delete, move, toggle).
    case actionFailed(String)
    /// Thread not found by ID.
    case threadNotFound(id: String)
    /// Folder not found by ID.
    case folderNotFound(id: String)

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let msg):
            "Fetch failed: \(msg)"
        case .actionFailed(let msg):
            "Action failed: \(msg)"
        case .threadNotFound(let id):
            "Thread not found: \(id)"
        case .folderNotFound(let id):
            "Folder not found: \(id)"
        }
    }
}
