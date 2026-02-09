@preconcurrency import Network
import Foundation

// MARK: - SMTPSession

/// Low-level SMTP session managing a single TLS connection.
///
/// Uses Network.framework for platform-native TLS, matching the
/// `IMAPSession` architecture pattern (P-07: Security as a Requirement).
///
/// Handles SMTP command/response, XOAUTH2 authentication, and the
/// DATA transaction for sending messages.
///
/// Spec ref: Email Composer spec FR-COMP-02
actor SMTPSession {

    // MARK: - Properties

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let timeout: TimeInterval
    private let connectionQueue: DispatchQueue

    var isSessionConnected: Bool {
        guard let connection else { return false }
        return connection.state == .ready
    }

    // MARK: - Init

    init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.timeout = timeout
        self.connectionQueue = DispatchQueue(
            label: "com.privatemail.smtp.session",
            qos: .userInitiated
        )
    }

    // MARK: - Connect

    /// Establishes a TLS connection to the SMTP server.
    ///
    /// Port 465 uses implicit TLS (direct TLS handshake on connect).
    /// Reads the server greeting (220) after connection.
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname (e.g., "smtp.gmail.com")
    ///   - port: SMTP port (465 for implicit TLS)
    /// - Throws: `SMTPError.connectionFailed`, `SMTPError.timeout`
    func connect(host: String, port: Int) async throws {
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let conn = NWConnection(
            host: .init(host),
            port: .init(integerLiteral: UInt16(port)),
            using: params
        )

        let flag = SMTPAtomicFlag()
        let timeoutInterval = timeout
        let queue = connectionQueue

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    conn.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard flag.trySet() else { return }
                            cont.resume()
                        case .failed(let error):
                            guard flag.trySet() else { return }
                            cont.resume(throwing: SMTPError.connectionFailed(error.localizedDescription))
                        case .cancelled:
                            guard flag.trySet() else { return }
                            cont.resume(throwing: SMTPError.operationCancelled)
                        default:
                            break
                        }
                    }

                    conn.start(queue: queue)
                }
            }

            // Timeout task — fires if connection takes too long
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutInterval))
                guard flag.trySet() else { return }
                conn.cancel()
                throw SMTPError.timeout
            }

            // Wait for the first task to finish (connect or timeout),
            // then cancel the remaining task.
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }

        // Clear stateUpdateHandler to avoid retain cycles and stale
        // continuation references after the connection is established.
        conn.stateUpdateHandler = nil
        self.connection = conn

        // Read server greeting (220 service ready)
        let greeting = try await readResponse()
        guard greeting.code == 220 else {
            conn.cancel()
            self.connection = nil
            throw SMTPError.connectionFailed("Unexpected greeting: \(greeting.text)")
        }

        // Send EHLO to identify ourselves
        let ehloResponse = try await sendCommand("EHLO privatemail.local")
        guard ehloResponse.code == 250 else {
            throw SMTPError.commandFailed("EHLO rejected: \(ehloResponse.text)")
        }
    }

    // MARK: - Disconnect

    /// Disconnects from the SMTP server gracefully.
    func disconnect() {
        if isSessionConnected {
            let cmd = Data("QUIT\r\n".utf8)
            connection?.send(content: cmd, completion: .idempotent)
        }
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
    }

    // MARK: - XOAUTH2 Authentication

    /// Authenticates using Gmail's XOAUTH2 mechanism over SMTP.
    ///
    /// SMTP AUTH XOAUTH2 uses the same SASL string as IMAP:
    /// base64("user=<email>\x01auth=Bearer <token>\x01\x01")
    ///
    /// - Parameters:
    ///   - email: User's email address
    ///   - accessToken: OAuth 2.0 access token
    /// - Throws: `SMTPError.authenticationFailed`
    func authenticateXOAUTH2(email: String, accessToken: String) async throws {
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let base64Auth = Data(authString.utf8).base64EncodedString()

        let response = try await sendCommand("AUTH XOAUTH2 \(base64Auth)")

        if response.code == 235 {
            return // Authentication successful
        }

        // Auth failed — Gmail returns 334 with error details, then expects empty line
        if response.code == 334 {
            // Send empty line to cancel
            try await sendRaw("\r\n")
            // Read the final error response
            let errorResponse = try await readResponse()
            throw SMTPError.authenticationFailed(errorResponse.text)
        }

        throw SMTPError.authenticationFailed("Code \(response.code): \(response.text)")
    }

    // MARK: - Send Message

    /// Sends a complete SMTP message transaction.
    ///
    /// Sequence: MAIL FROM → RCPT TO (each) → DATA → message → .
    ///
    /// - Parameters:
    ///   - from: Sender email (envelope sender)
    ///   - recipients: All recipient emails
    ///   - messageData: Raw RFC 2822 MIME message
    func sendMessage(from: String, recipients: [String], messageData: Data) async throws {
        // MAIL FROM
        let mailFromResp = try await sendCommand("MAIL FROM:<\(from)>")
        guard mailFromResp.code == 250 else {
            throw SMTPError.commandFailed("MAIL FROM rejected: \(mailFromResp.text)")
        }

        // RCPT TO for each recipient
        for recipient in recipients {
            let rcptResp = try await sendCommand("RCPT TO:<\(recipient)>")
            guard rcptResp.code == 250 || rcptResp.code == 251 else {
                throw SMTPError.commandFailed("RCPT TO <\(recipient)> rejected: \(rcptResp.text)")
            }
        }

        // DATA command
        let dataResp = try await sendCommand("DATA")
        guard dataResp.code == 354 else {
            throw SMTPError.commandFailed("DATA rejected: \(dataResp.text)")
        }

        // Send message body with dot-stuffing
        let stuffedData = dotStuff(messageData)
        try await sendRawData(stuffedData)

        // End with CRLF.CRLF
        try await sendRaw("\r\n.\r\n")

        // Read final response (250 OK)
        let sendResp = try await readResponse()
        guard sendResp.code == 250 else {
            throw SMTPError.commandFailed("Message rejected: \(sendResp.text)")
        }
    }

    // MARK: - Private: SMTP Response

    /// Parsed SMTP response with numeric code and text.
    struct Response {
        let code: Int
        let text: String
    }

    /// Sends an SMTP command and reads the response.
    private func sendCommand(_ command: String) async throws -> Response {
        try await sendRaw("\(command)\r\n")
        return try await readResponse()
    }

    /// Reads a complete SMTP response (handles multi-line responses).
    ///
    /// SMTP multi-line responses use `NNN-text` for continuation
    /// and `NNN text` for the final line.
    private func readResponse() async throws -> Response {
        var allText = ""

        while true {
            let line = try await readLine()

            // Parse response code from first 3 characters
            guard line.count >= 3,
                  let code = Int(line.prefix(3)) else {
                throw SMTPError.invalidResponse(line)
            }

            // Check continuation indicator (4th character)
            let separator = line.count > 3 ? line[line.index(line.startIndex, offsetBy: 3)] : " "
            let text = line.count > 4 ? String(line[line.index(line.startIndex, offsetBy: 4)...]) : ""

            if !allText.isEmpty { allText += "\n" }
            allText += text

            if separator == " " {
                // Final line of response
                return Response(code: code, text: allText)
            }
            // Continue reading (separator is "-")
        }
    }

    // MARK: - Private: Send

    private func sendRaw(_ text: String) async throws {
        let data = Data(text.utf8)
        try await sendRawData(data)
    }

    private func sendRawData(_ data: Data) async throws {
        guard let conn = connection, conn.state == .ready else {
            throw SMTPError.connectionFailed("Not connected")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: SMTPError.connectionFailed("Send failed: \(error.localizedDescription)"))
                } else {
                    cont.resume()
                }
            })
        }
    }

    // MARK: - Private: Receive

    /// Reads a complete line from the connection (CRLF-terminated).
    private func readLine() async throws -> String {
        while true {
            if let result = consumeLine() {
                return result
            }
            try await receiveMoreData()
        }
    }

    /// Extracts a CRLF-terminated line from the receive buffer.
    private func consumeLine() -> String? {
        guard let crlfRange = receiveBuffer.range(of: Data("\r\n".utf8)) else {
            return nil
        }

        let lineData = receiveBuffer[receiveBuffer.startIndex..<crlfRange.lowerBound]
        let lineStr = String(data: Data(lineData), encoding: .utf8)

        receiveBuffer = Data(receiveBuffer[crlfRange.upperBound...])
        return lineStr
    }

    /// Receives data from the connection with a timeout guard.
    private func receiveMoreData() async throws {
        guard let conn = connection, conn.state == .ready else {
            throw SMTPError.connectionFailed("Not connected")
        }

        let flag = SMTPAtomicFlag()
        let effectiveTimeout = timeout

        let data: Data = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                // Receive task
                group.addTask {
                    try await withCheckedThrowingContinuation { cont in
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                            guard flag.trySet() else { return }
                            if let error {
                                cont.resume(throwing: SMTPError.connectionFailed(error.localizedDescription))
                            } else if let data, !data.isEmpty {
                                cont.resume(returning: data)
                            } else {
                                cont.resume(throwing: SMTPError.connectionFailed("Connection closed by server"))
                            }
                        }
                    }
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(effectiveTimeout))
                    guard flag.trySet() else {
                        throw CancellationError()
                    }
                    throw SMTPError.timeout
                }

                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw SMTPError.connectionFailed("No data received")
                }
                return result
            }
        } onCancel: {
            conn.cancel()
        }

        receiveBuffer.append(data)
    }

    // MARK: - Private: Dot Stuffing

    /// Applies SMTP dot-stuffing per RFC 5321 §4.5.2.
    ///
    /// Any line in the message body that begins with "." must be
    /// prepended with an additional "." to prevent the SMTP server
    /// from interpreting it as the end-of-data marker.
    private func dotStuff(_ data: Data) -> Data {
        guard let str = String(data: data, encoding: .utf8) else { return data }
        let lines = str.components(separatedBy: "\r\n")
        let stuffed = lines.map { line in
            if line.hasPrefix(".") {
                return "." + line
            }
            return line
        }
        return Data(stuffed.joined(separator: "\r\n").utf8)
    }
}

// MARK: - Thread-Safe Resume Guard

/// Atomic flag ensuring a continuation is resumed exactly once.
/// Same pattern as IMAPSession's AtomicFlag, scoped to SMTP module.
private final class SMTPAtomicFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_value else { return false }
        _value = true
        return true
    }
}
