import Foundation

/// Protocol for SMTP client operations.
///
/// Implementations live in the Data layer. The ComposeEmailUseCase
/// depends only on this protocol (FR-FOUND-01: dependency inversion).
///
/// Spec ref: Email Composer spec FR-COMP-02, Email Sync spec FR-SYNC-07
public protocol SMTPClientProtocol: Sendable {

    /// Connects to the SMTP server and authenticates.
    ///
    /// Supports multiple security modes and authentication mechanisms:
    /// - **TLS** (port 465): Implicit TLS — handshake starts immediately.
    /// - **STARTTLS** (port 587): Plaintext → STARTTLS → TLS upgrade.
    /// - **XOAUTH2**: OAuth 2.0 for Gmail/Outlook.
    /// - **PLAIN**: App password for Yahoo/iCloud/custom.
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname (e.g., "smtp.gmail.com")
    ///   - port: SMTP server port (465 for TLS, 587 for STARTTLS)
    ///   - security: Connection security mode
    ///   - credential: Authentication credential (XOAUTH2 or PLAIN)
    /// - Throws: `SMTPError.connectionFailed`, `SMTPError.authenticationFailed`,
    ///           `SMTPError.timeout`, `SMTPError.starttlsNotSupported`
    func connect(host: String, port: Int, security: ConnectionSecurity, credential: SMTPCredential) async throws

    /// Connects to the SMTP server using implicit TLS and XOAUTH2.
    ///
    /// Convenience overload for backward compatibility with existing call sites.
    /// Equivalent to `connect(host:port:security:.tls, credential:.xoauth2(...))`.
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
