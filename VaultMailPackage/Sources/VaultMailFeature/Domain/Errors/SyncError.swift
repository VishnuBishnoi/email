import Foundation

/// Errors specific to the email sync engine.
///
/// Spec ref: Email Sync spec FR-SYNC-01
public enum SyncError: Error, Sendable, Equatable, LocalizedError {
    /// Account not found in SwiftData.
    case accountNotFound(String)
    /// Account exists but is inactive (needs re-authentication).
    case accountInactive(String)
    /// Required folder not found.
    case folderNotFound(String)
    /// OAuth token refresh failed.
    case tokenRefreshFailed(String)
    /// IMAP connection could not be established.
    case connectionFailed(String)
    /// General sync failure wrapping an underlying error description.
    case syncFailed(String)
    /// Sync exceeded the maximum allowed duration.
    case timeout

    public var errorDescription: String? {
        switch self {
        case .accountNotFound(let id):
            return "Account not found: \(id)"
        case .accountInactive(let id):
            return "Account inactive, re-authentication needed: \(id)"
        case .folderNotFound(let id):
            return "Folder not found: \(id)"
        case .tokenRefreshFailed(let reason):
            return "Token refresh failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .timeout:
            return "Sync timed out. Please try again."
        }
    }
}
