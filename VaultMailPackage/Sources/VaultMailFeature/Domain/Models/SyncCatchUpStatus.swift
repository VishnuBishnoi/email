import Foundation

/// Catch-up lifecycle states for folder historical sync.
///
/// Spec ref: Email Sync FR-SYNC-01, FR-SYNC-02 (v1.3.0)
public enum SyncCatchUpStatus: String, Sendable, Codable, CaseIterable {
    case idle
    case running
    case paused
    case completed
    case error
}
