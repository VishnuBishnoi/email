import Foundation

/// Production SMTP client conforming to `SMTPClientProtocol`.
///
/// Uses `SMTPSession` for TLS connection management. Follows the
/// same actor-based architecture as `IMAPClient`.
///
/// Architecture (AI-01): Data layer implementation of Domain protocol.
/// Spec ref: Email Composer spec FR-COMP-02, Email Sync spec FR-SYNC-07
public actor SMTPClient: SMTPClientProtocol {

    // MARK: - Properties

    private let session: SMTPSession
    private var _isConnected = false

    // MARK: - Init

    /// Creates an SMTP client with the specified timeout.
    ///
    /// - Parameter timeout: Connection timeout in seconds (default: 30s)
    public init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.session = SMTPSession(timeout: timeout)
    }

    // MARK: - SMTPClientProtocol: Connection

    public var isConnected: Bool {
        _isConnected
    }

    /// Connects to the SMTP server using TLS and authenticates with XOAUTH2.
    ///
    /// Per FR-SYNC-09:
    /// - Connection timeout: 30 seconds
    /// - Retry with exponential backoff: 5s, 15s, 45s
    /// - Don't retry authentication failures
    public func connect(host: String, port: Int, email: String, accessToken: String) async throws {
        var lastError: Error?

        for attempt in 0...AppConstants.imapMaxRetries {
            do {
                try await session.connect(host: host, port: port)
                try await session.authenticateXOAUTH2(email: email, accessToken: accessToken)
                _isConnected = true
                return
            } catch {
                lastError = error

                // Don't retry auth failures — they won't resolve with retries
                if let smtpError = error as? SMTPError,
                   case .authenticationFailed = smtpError {
                    throw error
                }

                if attempt < AppConstants.imapMaxRetries {
                    let delay = AppConstants.imapRetryBaseDelay * pow(3.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await session.disconnect()
                }
            }
        }

        throw lastError ?? SMTPError.maxRetriesExhausted
    }

    /// Disconnects from the SMTP server gracefully.
    public func disconnect() async {
        await session.disconnect()
        _isConnected = false
    }

    // MARK: - SMTPClientProtocol: Send

    /// Sends a raw MIME message via SMTP.
    ///
    /// Delegates to the session for the full SMTP transaction.
    public func sendMessage(
        from: String,
        recipients: [String],
        messageData: Data
    ) async throws {
        guard _isConnected else {
            throw SMTPError.connectionFailed("Not connected to SMTP server")
        }

        try await session.sendMessage(
            from: from,
            recipients: recipients,
            messageData: messageData
        )
    }
}
