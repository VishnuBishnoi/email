@preconcurrency import Network
import Foundation

// MARK: - Thread-Safe Resume Guard

/// Atomic flag ensuring a continuation is resumed exactly once.
///
/// NWConnection callbacks run on arbitrary dispatch queues, so
/// multiple state transitions or a timeout can race to resume
/// the same continuation. This guard prevents double-resume crashes.
private final class AtomicFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    /// Tries to claim the flag. Returns `true` on the first call only.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_value else { return false }
        _value = true
        return true
    }
}

// MARK: - IMAPSession

/// Low-level IMAP session managing a single TLS connection.
///
/// Uses Network.framework for platform-native TLS (P-07: Security as a Requirement).
/// Handles command tagging, response buffering, and connection lifecycle.
///
/// Build vs. library decision (IOS-F-05):
///   **Decision**: Build on Network.framework.
///   **Rationale**: Zero external dependencies, platform-native TLS, native
///   Swift concurrency support, focused Gmail scope for V1. The ~12 IMAP
///   commands needed for Gmail don't justify importing swift-nio-imap (pre-1.0).
actor IMAPSession {

    // MARK: - Properties

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var tagCounter = 0
    private var currentIdleTag: String?
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
            label: "com.vaultmail.imap.session",
            qos: .userInitiated
        )
    }

    // MARK: - Connect

    /// Establishes a TLS connection to the IMAP server.
    ///
    /// - Parameters:
    ///   - host: IMAP server hostname (e.g., "imap.gmail.com")
    ///   - port: IMAP port (993 for implicit TLS per FR-SYNC-09)
    /// - Throws: `IMAPError.connectionFailed`, `IMAPError.timeout`
    func connect(host: String, port: Int) async throws {
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

        // Read and verify server greeting (e.g., "* OK Gimap ready")
        let greeting = try await readLine()
        guard greeting.contains("OK") else {
            conn.cancel()
            self.connection = nil
            throw IMAPError.connectionFailed("Unexpected server greeting: \(greeting)")
        }
    }

    // MARK: - Disconnect

    /// Disconnects from the IMAP server gracefully.
    func disconnect() {
        if isSessionConnected {
            tagCounter += 1
            let tag = makeTag()
            let cmd = Data("\(tag) LOGOUT\r\n".utf8)
            connection?.send(content: cmd, completion: .idempotent)
        }
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        currentIdleTag = nil
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
        guard let conn = connection, conn.state == .ready else {
            throw IMAPError.connectionFailed("Not connected")
        }

        let data = Data("\(line)\r\n".utf8)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: IMAPError.connectionFailed("Send failed: \(error.localizedDescription)"))
                } else {
                    cont.resume()
                }
            })
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
    /// Uses the same `AtomicFlag` + `asyncAfter` pattern as `connect()`
    /// for consistency and proven correctness.
    ///
    /// - Parameter timeout: Read timeout override. Defaults to `self.timeout`
    ///   (30s). IDLE reads pass a longer value via `readLine(timeout:)`.
    private func receiveMoreData(timeout readTimeout: TimeInterval? = nil) async throws {
        guard let conn = connection, conn.state == .ready else {
            throw IMAPError.connectionFailed("Not connected")
        }

        let effectiveTimeout = readTimeout ?? timeout
        let flag = AtomicFlag()
        let queue = connectionQueue

        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // Read timeout guard (FR-SYNC-01, FR-SYNC-09)
                queue.asyncAfter(deadline: .now() + effectiveTimeout) {
                    guard flag.trySet() else { return }
                    cont.resume(throwing: IMAPError.timeout)
                }

                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
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
    }

    private func makeTag() -> String {
        "A\(String(format: "%04d", tagCounter))"
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
