@preconcurrency import Network
import Foundation

// MARK: - SMTPSession

/// Low-level SMTP session managing a single connection.
///
/// Supports two connection modes:
/// - **Implicit TLS** (`.tls`): Uses Network.framework `NWConnection` for
///   platform-native TLS (port 465). This is the original V1 path.
/// - **STARTTLS** (`.starttls`): Uses `STARTTLSConnection` (Foundation streams)
///   to connect plaintext, then upgrade to TLS in-place (port 587).
///
/// Handles SMTP command/response, XOAUTH2 authentication, and the
/// DATA transaction for sending messages.
///
/// Spec ref: Email Composer spec FR-COMP-02, FR-MPROV-05 (STARTTLS)
actor SMTPSession {

    // MARK: - Properties

    /// Backend for implicit TLS connections (NWConnection).
    private var connection: NWConnection?
    /// Backend for STARTTLS connections (Foundation streams).
    private var starttlsConnection: STARTTLSConnection?
    /// Which connection mode is active.
    private var activeSecurityMode: ConnectionSecurity?

    private var receiveBuffer = Data()
    private let timeout: TimeInterval
    private let connectionQueue: DispatchQueue

    var isSessionConnected: Bool {
        switch activeSecurityMode {
        case .tls:
            guard let connection else { return false }
            return connection.state == .ready
        case .starttls:
            return starttlsConnection != nil
        #if DEBUG
        case .some(.none):
            return starttlsConnection != nil
        #endif
        case nil:
            return false
        }
    }

    // MARK: - Init

    init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.timeout = timeout
        self.connectionQueue = DispatchQueue(
            label: "com.vaultmail.smtp.session",
            qos: .userInitiated
        )
    }

    // MARK: - Connect (Implicit TLS — port 465)

    /// Establishes an implicit TLS connection to the SMTP server.
    ///
    /// This is the original V1 code path for Gmail (port 465).
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname (e.g., "smtp.gmail.com")
    ///   - port: SMTP port (465 for implicit TLS)
    /// - Throws: `SMTPError.connectionFailed`, `SMTPError.timeout`
    func connect(host: String, port: Int) async throws {
        try await connect(host: host, port: port, security: .tls)
    }

    /// Establishes a connection to the SMTP server using the specified security mode.
    ///
    /// - Parameters:
    ///   - host: SMTP server hostname
    ///   - port: SMTP port (465 for TLS, 587 for STARTTLS)
    ///   - security: Connection security mode
    /// - Throws: `SMTPError.connectionFailed`, `SMTPError.timeout`,
    ///           `SMTPError.starttlsNotSupported`, `SMTPError.tlsUpgradeFailed`
    func connect(host: String, port: Int, security: ConnectionSecurity) async throws {
        switch security {
        case .tls:
            try await connectImplicitTLS(host: host, port: port)
        case .starttls:
            try await connectSTARTTLS(host: host, port: port)
        #if DEBUG
        case .none:
            try await connectPlaintext(host: host, port: port)
        #endif
        }
    }

    // MARK: - Connect: Implicit TLS

    private func connectImplicitTLS(host: String, port: Int) async throws {
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let conn = NWConnection(
            host: .init(host),
            port: .init(integerLiteral: UInt16(port)),
            using: params
        )

        let flag = AtomicFlag()
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
        self.activeSecurityMode = .tls

        // Read server greeting (220 service ready)
        let greeting = try await readResponse()
        guard greeting.code == 220 else {
            conn.cancel()
            self.connection = nil
            self.activeSecurityMode = nil
            throw SMTPError.connectionFailed("Unexpected greeting: \(greeting.text)")
        }

        // Send EHLO to identify ourselves
        let ehloResponse = try await sendCommand("EHLO vaultmail.local")
        guard ehloResponse.code == 250 else {
            throw SMTPError.commandFailed("EHLO rejected: \(ehloResponse.text)")
        }
    }

    // MARK: - Connect: STARTTLS (FR-MPROV-05)

    /// Connects via STARTTLS: plaintext TCP → EHLO → STARTTLS → TLS → re-EHLO.
    ///
    /// Spec sequence (FR-MPROV-05):
    /// 1. TCP connect (port 587, plaintext)
    /// 2. Read server greeting (220)
    /// 3. EHLO — check for STARTTLS in capabilities
    /// 4. STARTTLS command
    /// 5. Server responds 220 → TLS handshake
    /// 6. Re-issue EHLO (capabilities may change after TLS)
    private func connectSTARTTLS(host: String, port: Int) async throws {
        let stConn = STARTTLSConnection(timeout: timeout)
        self.starttlsConnection = stConn
        self.activeSecurityMode = .starttls

        do {
            // Step 1: Plaintext TCP connect
            try await stConn.connect(host: host, port: port)

            // Step 2: Read server greeting
            let (greetingCode, greetingText) = try await stConn.readSMTPResponse()
            guard greetingCode == 220 else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.connectionFailed("Unexpected greeting: \(greetingText)")
            }

            // Step 3: EHLO — check for STARTTLS
            try await stConn.sendLine("EHLO vaultmail.local")
            let (ehloCode, ehloText) = try await stConn.readSMTPResponse()
            guard ehloCode == 250 else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.commandFailed("EHLO rejected: \(ehloText)")
            }

            guard ehloText.uppercased().contains("STARTTLS") else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.starttlsNotSupported
            }

            // Step 4: Send STARTTLS command
            try await stConn.sendLine("STARTTLS")
            let (startCode, startText) = try await stConn.readSMTPResponse()
            guard startCode == 220 else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.tlsUpgradeFailed("Server rejected STARTTLS: \(startCode) \(startText)")
            }

            // Step 5: Upgrade to TLS
            try await stConn.upgradeTLS(host: host)

            // Step 6: Re-issue EHLO after TLS
            try await stConn.sendLine("EHLO vaultmail.local")
            let (reEhloCode, reEhloText) = try await stConn.readSMTPResponse()
            guard reEhloCode == 250 else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.commandFailed("Post-TLS EHLO rejected: \(reEhloText)")
            }
        } catch let error as ConnectionError {
            await stConn.disconnect()
            self.starttlsConnection = nil
            self.activeSecurityMode = nil
            throw mapConnectionError(error)
        } catch let error as SMTPError {
            await stConn.disconnect()
            self.starttlsConnection = nil
            self.activeSecurityMode = nil
            throw error
        }
    }

    #if DEBUG
    // MARK: - Connect: Plaintext (debug only, FR-MPROV-05)

    private func connectPlaintext(host: String, port: Int) async throws {
        let stConn = STARTTLSConnection(timeout: timeout)
        self.starttlsConnection = stConn
        self.activeSecurityMode = ConnectionSecurity.none

        do {
            try await stConn.connect(host: host, port: port)

            let (greetingCode, greetingText) = try await stConn.readSMTPResponse()
            guard greetingCode == 220 else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw SMTPError.connectionFailed("Unexpected greeting: \(greetingText)")
            }

            try await stConn.sendLine("EHLO vaultmail.local")
            let (ehloCode, ehloText) = try await stConn.readSMTPResponse()
            guard ehloCode == 250 else {
                throw SMTPError.commandFailed("EHLO rejected: \(ehloText)")
            }
        } catch let error as ConnectionError {
            await stConn.disconnect()
            self.starttlsConnection = nil
            self.activeSecurityMode = nil
            throw mapConnectionError(error)
        }
    }
    #endif

    // MARK: - Disconnect

    /// Disconnects from the SMTP server gracefully (async version).
    ///
    /// Properly awaits STARTTLS connection cleanup instead of fire-and-forget.
    /// Prefer this over the synchronous `disconnect()` in async contexts.
    func disconnectAsync() async {
        switch activeSecurityMode {
        case .tls:
            if isSessionConnected {
                let cmd = Data("QUIT\r\n".utf8)
                connection?.send(content: cmd, completion: .idempotent)
            }
            connection?.cancel()
            connection = nil
        case .starttls:
            let conn = starttlsConnection
            starttlsConnection = nil
            if let conn { await conn.disconnect() }
        #if DEBUG
        case .some(.none):
            let conn = starttlsConnection
            starttlsConnection = nil
            if let conn { await conn.disconnect() }
        #endif
        case nil:
            break
        }
        receiveBuffer.removeAll()
        activeSecurityMode = nil
    }

    /// Disconnects from the SMTP server gracefully (synchronous fallback).
    ///
    /// Note: For STARTTLS connections, cleanup runs in an unstructured Task.
    /// Prefer `disconnectAsync()` in async contexts for proper cleanup.
    func disconnect() {
        switch activeSecurityMode {
        case .tls:
            if isSessionConnected {
                let cmd = Data("QUIT\r\n".utf8)
                connection?.send(content: cmd, completion: .idempotent)
            }
            connection?.cancel()
            connection = nil
        case .starttls:
            let conn = starttlsConnection
            starttlsConnection = nil
            if let conn { Task { await conn.disconnect() } }
        #if DEBUG
        case .some(.none):
            let conn = starttlsConnection
            starttlsConnection = nil
            if let conn { Task { await conn.disconnect() } }
        #endif
        case nil:
            break
        }
        receiveBuffer.removeAll()
        activeSecurityMode = nil
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

    // MARK: - SASL PLAIN Authentication (FR-MPROV-03)

    /// Authenticates using SASL PLAIN mechanism over SMTP.
    ///
    /// Used by providers that require app passwords (Yahoo, iCloud, custom).
    /// Sends `AUTH PLAIN <base64>` where the base64 payload is:
    /// `\0<username>\0<password>` per RFC 4616.
    ///
    /// Spec ref: FR-MPROV-03 (SASL PLAIN authentication)
    ///
    /// - Parameters:
    ///   - username: User's email address (or login username)
    ///   - password: App-specific password
    /// - Throws: `SMTPError.authenticationFailed`
    func authenticatePLAIN(username: String, password: String) async throws {
        // Sanitize null bytes from inputs to prevent SASL structure corruption
        let cleanUser = username.replacingOccurrences(of: "\u{00}", with: "")
        let cleanPass = password.replacingOccurrences(of: "\u{00}", with: "")
        // Build SASL PLAIN string: "\0username\0password" → base64
        let authString = "\u{00}\(cleanUser)\u{00}\(cleanPass)"
        let base64Auth = Data(authString.utf8).base64EncodedString()

        let response = try await sendCommand("AUTH PLAIN \(base64Auth)")

        if response.code == 235 {
            return // Authentication successful
        }

        // Auth failed — some servers return 535 directly
        if response.code == 334 {
            // Server wants a continuation — send empty line to cancel
            try await sendRaw("\r\n")
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
        switch activeSecurityMode {
        case .tls:
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
        case .starttls:
            guard let stConn = starttlsConnection else {
                throw SMTPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else {
                throw SMTPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #endif
        case nil:
            throw SMTPError.connectionFailed("Not connected")
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
    ///
    /// Dispatches to NWConnection (TLS) or STARTTLSConnection (STARTTLS)
    /// based on the active security mode.
    private func receiveMoreData() async throws {
        switch activeSecurityMode {
        case .tls:
            guard let conn = connection, conn.state == .ready else {
                throw SMTPError.connectionFailed("Not connected")
            }

            let flag = AtomicFlag()
            let effectiveTimeout = timeout

            let data: Data = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Data.self) { group in
                    // Receive task
                    group.addTask {
                        try await withCheckedThrowingContinuation { cont in
                            conn.receive(minimumIncompleteLength: 1, maximumLength: AppConstants.socketReadBufferSize) { data, _, _, error in
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

        case .starttls:
            guard let stConn = starttlsConnection else {
                throw SMTPError.connectionFailed("Not connected")
            }
            do {
                let data = try await stConn.receiveData(timeout: timeout)
                receiveBuffer.append(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }

        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else {
                throw SMTPError.connectionFailed("Not connected")
            }
            do {
                let data = try await stConn.receiveData(timeout: timeout)
                receiveBuffer.append(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #endif

        case nil:
            throw SMTPError.connectionFailed("Not connected")
        }
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

    // MARK: - Error Mapping

    /// Maps `ConnectionError` from `STARTTLSConnection` to `SMTPError`.
    private func mapConnectionError(_ error: ConnectionError) -> SMTPError {
        switch error {
        case .connectionFailed(let msg):
            return .connectionFailed(msg)
        case .timeout:
            return .timeout
        case .tlsUpgradeFailed(let msg):
            return .tlsUpgradeFailed(msg)
        case .certificateValidationFailed(let msg):
            return .certificateValidationFailed(msg)
        case .invalidResponse(let msg):
            return .invalidResponse(msg)
        }
    }
}

