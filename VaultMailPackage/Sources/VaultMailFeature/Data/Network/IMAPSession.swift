@preconcurrency import Network
import Foundation

// MARK: - IMAPSession

/// Low-level IMAP session managing a single connection.
///
/// Supports two connection modes:
/// - **Implicit TLS** (`.tls`): Uses Network.framework `NWConnection` for
///   platform-native TLS (ports 993). This is the original V1 path.
/// - **STARTTLS** (`.starttls`): Uses `STARTTLSConnection` (Foundation streams)
///   to connect plaintext, then upgrade to TLS in-place (port 143).
///
/// Build vs. library decision (IOS-F-05):
///   **Decision**: Build on Network.framework + Foundation streams.
///   **Rationale**: Zero external dependencies, platform-native TLS, native
///   Swift concurrency support. Foundation streams used only for STARTTLS
///   because NWConnection cannot do in-place TLS upgrade (FR-MPROV-05).
///
/// Spec ref: FR-SYNC-09 (connection management), FR-MPROV-05 (STARTTLS)
actor IMAPSession {

    // MARK: - Properties

    /// Backend for implicit TLS connections (NWConnection).
    private var connection: NWConnection?
    /// Backend for STARTTLS connections (Foundation streams).
    private var starttlsConnection: STARTTLSConnection?
    /// Which connection mode is active.
    private var activeSecurityMode: ConnectionSecurity?

    private var receiveBuffer = Data()
    private var tagCounter = 0
    private var currentIdleTag: String?
    private let timeout: TimeInterval
    private let connectionQueue: DispatchQueue

    var isSessionConnected: Bool {
        switch activeSecurityMode {
        case .tls:
            guard let connection else { return false }
            return connection.state == .ready
        case .starttls:
            guard let stConn = starttlsConnection else { return false }
            return stConn.isConnectedSync
        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else { return false }
            return stConn.isConnectedSync
        #endif
        case nil:
            return false
        }
    }

    // MARK: - Init

    init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.timeout = timeout
        self.connectionQueue = DispatchQueue(
            label: "com.vaultmail.imap.session",
            qos: .userInitiated
        )
    }

    // MARK: - Connect (Implicit TLS — port 993)

    /// Establishes an implicit TLS connection to the IMAP server.
    ///
    /// This is the original V1 code path for Gmail (port 993).
    ///
    /// - Parameters:
    ///   - host: IMAP server hostname (e.g., "imap.gmail.com")
    ///   - port: IMAP port (993 for implicit TLS per FR-SYNC-09)
    /// - Throws: `IMAPError.connectionFailed`, `IMAPError.timeout`
    func connect(host: String, port: Int) async throws {
        try await connect(host: host, port: port, security: .tls)
    }

    /// Establishes a connection to the IMAP server using the specified security mode.
    ///
    /// - Parameters:
    ///   - host: IMAP server hostname
    ///   - port: IMAP port (993 for TLS, 143 for STARTTLS)
    ///   - security: Connection security mode (`.tls` or `.starttls`)
    /// - Throws: `IMAPError.connectionFailed`, `IMAPError.timeout`,
    ///           `IMAPError.starttlsNotSupported`, `IMAPError.tlsUpgradeFailed`
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

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Timeout guard (FR-SYNC-09: 30s)
            queue.asyncAfter(deadline: .now() + timeoutInterval) {
                guard flag.trySet() else { return }
                conn.cancel()
                cont.resume(throwing: IMAPError.timeout)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard flag.trySet() else { return }
                    cont.resume()
                case .failed(let error):
                    guard flag.trySet() else { return }
                    cont.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    guard flag.trySet() else { return }
                    cont.resume(throwing: IMAPError.operationCancelled)
                default:
                    break
                }
            }

            conn.start(queue: queue)
        }

        self.connection = conn
        self.activeSecurityMode = .tls

        // Read and verify server greeting (e.g., "* OK Gimap ready")
        let greeting = try await readLine()
        guard greeting.contains("OK") else {
            conn.cancel()
            self.connection = nil
            self.activeSecurityMode = nil
            throw IMAPError.connectionFailed("Unexpected server greeting: \(greeting)")
        }
    }

    // MARK: - Connect: STARTTLS (FR-MPROV-05)

    /// Connects via STARTTLS: plaintext TCP → CAPABILITY → STARTTLS → TLS → re-CAPABILITY.
    ///
    /// Spec sequence (FR-MPROV-05):
    /// 1. TCP connect (port 143, plaintext)
    /// 2. Read server greeting (* OK ...)
    /// 3. CAPABILITY — check for STARTTLS
    /// 4. STARTTLS command
    /// 5. Server responds OK → TLS handshake
    /// 6. Re-issue CAPABILITY (capabilities may change after TLS)
    private func connectSTARTTLS(host: String, port: Int) async throws {
        let stConn = STARTTLSConnection(timeout: timeout)
        self.starttlsConnection = stConn
        self.activeSecurityMode = .starttls

        do {
            // Step 1: Plaintext TCP connect
            try await stConn.connect(host: host, port: port)

            // Step 2: Read server greeting
            let greeting = try await stConn.readLine()
            guard greeting.contains("OK") else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw IMAPError.connectionFailed("Unexpected server greeting: \(greeting)")
            }

            // Step 3: CAPABILITY — verify STARTTLS is supported
            tagCounter += 1
            let capTag = makeTag()
            try await stConn.sendLine("\(capTag) CAPABILITY")

            var capabilityLine = ""
            while true {
                let line = try await stConn.readLine()
                if line.hasPrefix("* CAPABILITY") {
                    capabilityLine = line
                }
                if line.hasPrefix("\(capTag) OK") {
                    break
                }
                if line.hasPrefix("\(capTag) NO") || line.hasPrefix("\(capTag) BAD") {
                    await stConn.disconnect()
                    self.starttlsConnection = nil
                    self.activeSecurityMode = nil
                    throw IMAPError.commandFailed("CAPABILITY failed: \(line)")
                }
            }

            guard capabilityLine.uppercased().contains("STARTTLS") else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw IMAPError.starttlsNotSupported
            }

            // Step 4: Send STARTTLS command
            tagCounter += 1
            let startTag = makeTag()
            try await stConn.sendLine("\(startTag) STARTTLS")

            let startResponse = try await stConn.readLine()
            guard startResponse.hasPrefix("\(startTag) OK") else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw IMAPError.tlsUpgradeFailed("Server rejected STARTTLS: \(startResponse)")
            }

            // Step 5: Upgrade to TLS
            try await stConn.upgradeTLS(host: host)

            // Step 6: Re-issue CAPABILITY after TLS
            tagCounter += 1
            let reCapTag = makeTag()
            try await stConn.sendLine("\(reCapTag) CAPABILITY")

            while true {
                let line = try await stConn.readLine()
                if line.hasPrefix("\(reCapTag) OK") {
                    break
                }
                if line.hasPrefix("\(reCapTag) NO") || line.hasPrefix("\(reCapTag) BAD") {
                    await stConn.disconnect()
                    self.starttlsConnection = nil
                    self.activeSecurityMode = nil
                    throw IMAPError.commandFailed("Post-TLS CAPABILITY failed: \(line)")
                }
            }
        } catch let error as ConnectionError {
            await stConn.disconnect()
            self.starttlsConnection = nil
            self.activeSecurityMode = nil
            throw mapConnectionError(error)
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

            let greeting = try await stConn.readLine()
            guard greeting.contains("OK") else {
                await stConn.disconnect()
                self.starttlsConnection = nil
                self.activeSecurityMode = nil
                throw IMAPError.connectionFailed("Unexpected server greeting: \(greeting)")
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

    /// Disconnects from the IMAP server gracefully (async version).
    ///
    /// Properly awaits STARTTLS connection cleanup instead of fire-and-forget.
    /// Prefer this over the synchronous `disconnect()` in async contexts.
    func disconnectAsync() async {
        switch activeSecurityMode {
        case .tls:
            if isSessionConnected {
                tagCounter += 1
                let tag = makeTag()
                let cmd = Data("\(tag) LOGOUT\r\n".utf8)
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
        currentIdleTag = nil
        activeSecurityMode = nil
    }

    /// Disconnects from the IMAP server gracefully (synchronous fallback).
    ///
    /// Note: For STARTTLS connections, cleanup runs in an unstructured Task.
    /// Prefer `disconnectAsync()` in async contexts for proper cleanup.
    func disconnect() {
        switch activeSecurityMode {
        case .tls:
            if isSessionConnected {
                tagCounter += 1
                let tag = makeTag()
                let cmd = Data("\(tag) LOGOUT\r\n".utf8)
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
        currentIdleTag = nil
        activeSecurityMode = nil
    }

    // MARK: - XOAUTH2 Authentication

    /// Authenticates using Gmail's XOAUTH2 mechanism.
    ///
    /// Per AC-F-05: XOAUTH2 authentication MUST succeed with valid credentials.
    /// See: https://developers.google.com/gmail/imap/xoauth2-protocol
    func authenticateXOAUTH2(email: String, accessToken: String) async throws {
        // Build XOAUTH2 string: "user=<email>\x01auth=Bearer <token>\x01\x01"
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let base64Auth = Data(authString.utf8).base64EncodedString()

        tagCounter += 1
        let tag = makeTag()
        try await sendRaw("\(tag) AUTHENTICATE XOAUTH2 \(base64Auth)")

        // Read response — either OK (success) or + (failure continuation)
        while true {
            let line = try await readLine()

            if line.hasPrefix(tag + " OK") {
                return // Auth succeeded
            } else if line.hasPrefix("+") {
                // Auth failed — server expects empty continuation before sending NO
                try await sendRaw("")
            } else if line.hasPrefix(tag + " NO") || line.hasPrefix(tag + " BAD") {
                throw IMAPError.authenticationFailed(
                    String(line.dropFirst(tag.count + 1))
                )
            }
            // Ignore other untagged responses during auth
        }
    }

    // MARK: - SASL PLAIN Authentication (FR-MPROV-03)

    /// Authenticates using SASL PLAIN mechanism.
    ///
    /// Used by providers that require app passwords (Yahoo, iCloud, custom).
    /// Sends `LOGIN username password` command per RFC 3501 §6.2.3.
    ///
    /// LOGIN is preferred over `AUTHENTICATE PLAIN` because:
    /// - Simpler wire format (no base64 encoding needed)
    /// - Widely supported across all IMAP servers
    /// - Functionally equivalent for password-based auth
    ///
    /// Spec ref: FR-MPROV-03 (SASL PLAIN authentication)
    func authenticatePLAIN(username: String, password: String) async throws {
        tagCounter += 1
        let tag = makeTag()

        // Sanitize credentials to prevent command injection.
        // IMAP LOGIN quotes both arguments — we escape any embedded
        // quotes and strip CRLF to prevent breakout.
        let safeUser = username.imapQuoteSanitized
        let safePass = password.imapQuoteSanitized
        try await sendRaw("\(tag) LOGIN \"\(safeUser)\" \"\(safePass)\"")

        while true {
            let line = try await readLine()

            if line.hasPrefix(tag + " OK") {
                return // Auth succeeded
            } else if line.hasPrefix(tag + " NO") || line.hasPrefix(tag + " BAD") {
                throw IMAPError.authenticationFailed(
                    String(line.dropFirst(tag.count + 1))
                )
            }
            // Ignore untagged responses during auth
        }
    }

    // MARK: - Command Execution

    /// Executes a tagged IMAP command and returns all untagged responses.
    ///
    /// Automatically tags the command and waits for the tagged OK response.
    /// Throws on NO or BAD responses.
    ///
    /// - Parameter command: The IMAP command without a tag (e.g., "LIST \"\" \"*\"")
    /// - Returns: Array of untagged response lines (lines starting with "* ")
    func execute(_ command: String) async throws -> [String] {
        tagCounter += 1
        let tag = makeTag()
        try await sendRaw("\(tag) \(command)")

        var responses: [String] = []

        while true {
            let line = try await readLine()

            if line.hasPrefix(tag + " ") {
                // Tagged response — command complete
                let afterTag = String(line.dropFirst(tag.count + 1))
                if afterTag.hasPrefix("OK") {
                    return responses
                } else {
                    throw IMAPError.commandFailed(afterTag)
                }
            } else if line.hasPrefix("* ") || line.hasPrefix("+ ") {
                // Untagged or continuation response
                responses.append(line)
            } else if !line.isEmpty {
                // Continuation of previous response (after a literal)
                if !responses.isEmpty {
                    responses[responses.count - 1] += "\n" + line
                }
            }
        }
    }

    // MARK: - IDLE

    /// Starts IMAP IDLE mode. Returns the tag for later DONE.
    func startIDLE() async throws -> String {
        tagCounter += 1
        let tag = makeTag()
        currentIdleTag = tag

        try await sendRaw("\(tag) IDLE")

        let response = try await readLine()
        guard response.hasPrefix("+") else {
            currentIdleTag = nil
            throw IMAPError.commandFailed("IDLE not accepted: \(response)")
        }

        return tag
    }

    /// Reads one line during IDLE.
    ///
    /// Uses a longer read timeout (IDLE refresh interval + 60s buffer) because
    /// the server may not send data for up to 25 minutes during normal IDLE.
    /// A 30s timeout would false-positive during valid IDLE waits.
    func readIDLENotification() async throws -> String {
        return try await readLine(
            timeout: AppConstants.imapIdleRefreshInterval + 60
        )
    }

    /// Stops IDLE mode by sending DONE.
    func stopIDLE() async throws {
        guard let tag = currentIdleTag else { return }

        try await sendRaw("DONE")

        // Read until we get the tagged OK
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag + " ") {
                currentIdleTag = nil
                return
            }
        }
    }

    // MARK: - Literal Data (APPEND)

    /// Sends raw bytes to the server (for APPEND literal data).
    func sendLiteralData(_ data: Data) async throws {
        switch activeSecurityMode {
        case .tls:
            guard let conn = connection, conn.state == .ready else {
                throw IMAPError.connectionFailed("Not connected")
            }

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    } else {
                        cont.resume()
                    }
                })
            }
        case .starttls:
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #endif
        case nil:
            throw IMAPError.connectionFailed("Not connected")
        }
    }

    /// Executes APPEND: sends the command, waits for continuation, sends literal, reads result.
    func executeAPPEND(folder: String, flags: [String], data: Data) async throws {
        tagCounter += 1
        let tag = makeTag()

        let sanitizedFolder = folder.imapQuoteSanitized
        let sanitizedFlags = flags.map { $0.imapCRLFStripped }
        let flagStr = sanitizedFlags.isEmpty ? "" : " (\(sanitizedFlags.joined(separator: " ")))"
        let cmd = "\(tag) APPEND \"\(sanitizedFolder)\"\(flagStr) {\(data.count)}"
        try await sendRaw(cmd)

        // Wait for continuation response (+)
        let contResponse = try await readLine()
        guard contResponse.hasPrefix("+") else {
            throw IMAPError.commandFailed("APPEND not accepted: \(contResponse)")
        }

        // Send the literal data followed by CRLF
        var payload = data
        payload.append(Data("\r\n".utf8))
        try await sendLiteralData(payload)

        // Read until tagged response
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag + " ") {
                let afterTag = String(line.dropFirst(tag.count + 1))
                if afterTag.hasPrefix("OK") {
                    return
                } else {
                    throw IMAPError.commandFailed(afterTag)
                }
            }
        }
    }

    // MARK: - Private: Send

    private func sendRaw(_ line: String) async throws {
        let data = Data("\(line)\r\n".utf8)

        switch activeSecurityMode {
        case .tls:
            guard let conn = connection, conn.state == .ready else {
                throw IMAPError.connectionFailed("Not connected")
            }

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: IMAPError.connectionFailed("Send failed: \(error.localizedDescription)"))
                    } else {
                        cont.resume()
                    }
                })
            }
        case .starttls:
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                try await stConn.send(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #endif
        case nil:
            throw IMAPError.connectionFailed("Not connected")
        }
    }

    // MARK: - Private: Receive

    /// Reads a complete IMAP response line from the connection.
    /// Handles IMAP literal syntax `{NNN}` for multi-line data.
    ///
    /// - Parameter timeout: Optional read timeout override. Defaults to
    ///   `self.timeout` (30s) for normal operations. IDLE reads pass a
    ///   longer timeout to avoid false positives during valid IDLE waits.
    private func readLine(timeout readTimeout: TimeInterval? = nil) async throws -> String {
        while true {
            if let result = consumeLine() {
                return result
            }
            try await receiveMoreData(timeout: readTimeout)
        }
    }

    /// Extracts a complete line from the receive buffer.
    /// Handles IMAP literal `{NNN}` — reads N bytes after the CRLF.
    private func consumeLine() -> String? {
        guard let crlfRange = receiveBuffer.range(of: Data("\r\n".utf8)) else {
            return nil
        }

        let lineData = receiveBuffer[receiveBuffer.startIndex..<crlfRange.lowerBound]
        guard let lineStr = String(data: Data(lineData), encoding: .utf8) else {
            return nil
        }

        // Check for IMAP literal: line ends with {NNN}
        if let literalSize = parseLiteralSize(lineStr) {
            let afterCRLF = crlfRange.upperBound
            let available = receiveBuffer.endIndex - afterCRLF
            guard available >= literalSize else {
                return nil // Need more data for the literal
            }

            let literalEnd = receiveBuffer.index(afterCRLF, offsetBy: literalSize)
            let literalData = Data(receiveBuffer[afterCRLF..<literalEnd])
            let literalStr = String(data: literalData, encoding: .utf8) ?? ""

            receiveBuffer = Data(receiveBuffer[literalEnd...])
            return lineStr + "\n" + literalStr
        }

        // Simple line — consume CRLF and return
        receiveBuffer = Data(receiveBuffer[crlfRange.upperBound...])
        return lineStr
    }

    private func parseLiteralSize(_ line: String) -> Int? {
        guard line.hasSuffix("}"),
              let openBrace = line.lastIndex(of: "{") else { return nil }
        let sizeStr = line[line.index(after: openBrace)..<line.index(before: line.endIndex)]
        return Int(sizeStr)
    }

    /// Receives data from the connection with a timeout guard.
    ///
    /// Per FR-SYNC-01: "Network timeout during fetch MUST trigger a retry"
    /// — this requires a mechanism that *detects* the timeout. Without it
    /// a stale connection would block indefinitely.
    ///
    /// Dispatches to NWConnection (TLS) or STARTTLSConnection (STARTTLS)
    /// based on the active security mode.
    ///
    /// - Parameter timeout: Read timeout override. Defaults to `self.timeout`
    ///   (30s). IDLE reads pass a longer value via `readLine(timeout:)`.
    private func receiveMoreData(timeout readTimeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = readTimeout ?? timeout

        switch activeSecurityMode {
        case .tls:
            guard let conn = connection, conn.state == .ready else {
                throw IMAPError.connectionFailed("Not connected")
            }

            let flag = AtomicFlag()
            let queue = connectionQueue

            let data: Data = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { cont in
                    // Read timeout guard (FR-SYNC-01, FR-SYNC-09)
                    queue.asyncAfter(deadline: .now() + effectiveTimeout) {
                        guard flag.trySet() else { return }
                        cont.resume(throwing: IMAPError.timeout)
                    }

                    conn.receive(minimumIncompleteLength: 1, maximumLength: AppConstants.socketReadBufferSize) { data, _, _, error in
                        guard flag.trySet() else { return }
                        if let error {
                            cont.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                        } else if let data, !data.isEmpty {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(throwing: IMAPError.connectionFailed("Connection closed by server"))
                        }
                    }
                }
            } onCancel: {
                conn.cancel()
            }

            receiveBuffer.append(data)

        case .starttls:
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                let data = try await stConn.receiveData(timeout: effectiveTimeout)
                receiveBuffer.append(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }

        #if DEBUG
        case .some(.none):
            guard let stConn = starttlsConnection else {
                throw IMAPError.connectionFailed("Not connected")
            }
            do {
                let data = try await stConn.receiveData(timeout: effectiveTimeout)
                receiveBuffer.append(data)
            } catch let error as ConnectionError {
                throw mapConnectionError(error)
            }
        #endif

        case nil:
            throw IMAPError.connectionFailed("Not connected")
        }
    }

    private func makeTag() -> String {
        "A\(String(format: "%04d", tagCounter))"
    }

    // MARK: - Error Mapping

    /// Maps `ConnectionError` from `STARTTLSConnection` to `IMAPError`.
    private func mapConnectionError(_ error: ConnectionError) -> IMAPError {
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

// MARK: - IMAP Command Sanitization

/// Internal extensions for safe IMAP command interpolation.
///
/// Prevents command injection by sanitizing strings before they are
/// interpolated into IMAP commands sent over the wire.
///
/// Two levels:
/// - `imapQuoteSanitized`: For strings inside IMAP quoted strings (folder paths).
///   Escapes `\` and `"` per RFC 3501 §4.3, strips CR/LF.
/// - `imapCRLFStripped`: For IMAP atoms (flags, keywords) where backslash is
///   syntactically meaningful. Only strips CR/LF to prevent command injection.
extension String {

    /// Sanitizes for safe interpolation into an IMAP **quoted string**.
    ///
    /// Per RFC 3501 §4.3, quoted strings cannot contain bare CR or LF,
    /// and `\` and `"` must be escaped as `\\` and `\"`.
    ///
    /// This prevents:
    /// - **CRLF injection**: A `\r\n` in a folder name would terminate the
    ///   current command and start a new one on the server.
    /// - **Quote breakout**: A `"` in a folder name would close the quoted
    ///   string and allow arbitrary command content after it.
    var imapQuoteSanitized: String {
        self
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Strips CR and LF for safe interpolation into IMAP **atoms** (flags, etc.).
    ///
    /// Unlike `imapQuoteSanitized`, this does NOT escape backslashes because
    /// IMAP flags (e.g., `\Seen`, `\Flagged`) use bare backslashes as part
    /// of their syntax. Only CRLF is stripped to prevent command injection.
    var imapCRLFStripped: String {
        self
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
