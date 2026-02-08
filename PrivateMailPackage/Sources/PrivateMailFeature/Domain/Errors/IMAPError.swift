import Foundation

/// Errors from IMAP client operations.
///
/// Spec ref: Email Sync spec FR-SYNC-09 (Connection Management)
public enum IMAPError: Error, LocalizedError, Equatable, Sendable {
    /// TLS connection to the IMAP server failed.
    case connectionFailed(String)
    /// XOAUTH2 authentication was rejected by the server.
    case authenticationFailed(String)
    /// An IMAP command returned an error response.
    case commandFailed(String)
    /// Server response could not be parsed.
    case invalidResponse(String)
    /// The requested folder does not exist on the server.
    case folderNotFound(String)
    /// The requested message UID was not found.
    case messageNotFound(String)
    /// MIME body structure or header parsing failed.
    case parsingFailed(String)
    /// The operation was cancelled (e.g., IDLE stopped).
    case operationCancelled
    /// Connection or command exceeded the 30-second timeout (FR-SYNC-09).
    case timeout
    /// Maximum retry attempts exhausted (3 retries per FR-SYNC-09).
    case maxRetriesExhausted

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            "IMAP Connection Failed: \(message)"
        case .authenticationFailed(let message):
            "IMAP Authentication Failed: \(message)"
        case .commandFailed(let message):
            "IMAP Command Failed: \(message)"
        case .invalidResponse(let message):
            "IMAP Invalid Response: \(message)"
        case .folderNotFound(let name):
            "IMAP Folder Not Found: \(name)"
        case .messageNotFound(let uid):
            "IMAP Message Not Found: UID \(uid)"
        case .parsingFailed(let message):
            "IMAP Parsing Failed: \(message)"
        case .operationCancelled:
            "IMAP Operation Cancelled"
        case .timeout:
            "IMAP Operation Timed Out"
        case .maxRetriesExhausted:
            "IMAP Maximum Retries Exhausted"
        }
    }
}
