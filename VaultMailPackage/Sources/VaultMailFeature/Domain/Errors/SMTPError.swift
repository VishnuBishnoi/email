import Foundation

/// Errors from SMTP client operations.
///
/// Follows the same pattern as `IMAPError` — each case carries a
/// descriptive message for debugging.
///
/// Spec ref: Email Composer spec FR-COMP-02, Email Sync spec FR-SYNC-07
public enum SMTPError: Error, LocalizedError, Equatable, Sendable {
    /// TLS connection to the SMTP server failed.
    case connectionFailed(String)
    /// XOAUTH2 authentication was rejected by the SMTP server.
    case authenticationFailed(String)
    /// An SMTP command returned an error response.
    case commandFailed(String)
    /// Server response could not be parsed.
    case invalidResponse(String)
    /// The operation was cancelled.
    case operationCancelled
    /// Connection or command exceeded timeout.
    case timeout
    /// Maximum retry attempts exhausted.
    case maxRetriesExhausted
    /// MIME message encoding failed.
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            "SMTP Connection Failed: \(message)"
        case .authenticationFailed(let message):
            "SMTP Authentication Failed: \(message)"
        case .commandFailed(let message):
            "SMTP Command Failed: \(message)"
        case .invalidResponse(let message):
            "SMTP Invalid Response: \(message)"
        case .operationCancelled:
            "SMTP Operation Cancelled"
        case .timeout:
            "SMTP Operation Timed Out"
        case .maxRetriesExhausted:
            "SMTP Maximum Retries Exhausted"
        case .encodingFailed(let message):
            "SMTP Encoding Failed: \(message)"
        }
    }
}
