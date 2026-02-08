import Foundation

/// Errors specific to thread list operations.
///
/// Spec ref: Thread List spec FR-TL-01, FR-TL-03
public enum ThreadListError: Error, Sendable, Equatable {
    /// Thread fetch failed (pagination, category filter, or unified query).
    case fetchFailed(String)
    /// Thread action failed (archive, delete, move, toggle).
    case actionFailed(String)
    /// Thread not found by ID.
    case threadNotFound(id: String)
    /// Folder not found by ID.
    case folderNotFound(id: String)
}
