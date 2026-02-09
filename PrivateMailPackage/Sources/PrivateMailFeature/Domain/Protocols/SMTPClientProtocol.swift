import Foundation

/// Protocol for SMTP client operations.
///
/// Implementations live in the Data layer. The ComposeEmailUseCase
/// depends only on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Email Composer spec FR-COMP-02, Email Sync spec FR-SYNC-07
public protocol SMTPClientProtocol: Sendable {

    /// Connects to the SMTP server using TLS and authenticates with XOAUTH2.
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname (e.g., "smtp.gmail.com")
    ///   - port: SMTP server port (465 for implicit TLS)
    ///   - email: User's email address for XOAUTH2
    ///   - accessToken: OAuth 2.0 access token for XOAUTH2
    /// - Throws: `SMTPError.connectionFailed`, `SMTPError.authenticationFailed`,
    ///           `SMTPError.timeout`
    func connect(host: String, port: Int, email: String, accessToken: String) async throws

    /// Disconnects from the SMTP server gracefully.
    func disconnect() async

    /// Whether the client is currently connected and authenticated.
    var isConnected: Bool { get async }

    /// Sends a raw MIME message via SMTP.
    ///
    /// Executes the full SMTP send transaction:
    /// `MAIL FROM` → `RCPT TO` (for each recipient) → `DATA` → message → `.`
    ///
    /// - Parameters:
    ///   - from: Sender email address (MAIL FROM envelope)
    ///   - recipients: All recipient email addresses (To + CC + BCC)
    ///   - messageData: Complete RFC 2822 MIME message as raw bytes
    /// - Throws: `SMTPError.commandFailed` on rejection,
    ///           `SMTPError.connectionFailed` if not connected
    func sendMessage(
        from: String,
        recipients: [String],
        messageData: Data
    ) async throws
}
