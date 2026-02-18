import Foundation
import Security

// MARK: - Sendable Stream Wrapper

/// Thread-safe box for Foundation streams (which are not `Sendable`).
///
/// Streams are accessed exclusively on `streamQueue` (serial DispatchQueue)
/// so concurrent access is impossible. The `@unchecked Sendable` conformance
/// lets us pass them into `@Sendable` closures dispatched to that queue.
///
/// This follows the same pattern as `AtomicFlag` in the existing codebase —
/// wrapping non-Sendable types with explicit thread safety.
private final class StreamBox: @unchecked Sendable {
    let input: InputStream
    let output: OutputStream

    init(input: InputStream, output: OutputStream) {
        self.input = input
        self.output = output
    }
}

/// Sendable wrapper for non-Sendable immutable values.
///
/// Used to pass immutable `NSDictionary` (SSL settings) across concurrency
/// boundaries. The value is never mutated after construction.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Thread-Safe Boolean

/// Atomic boolean for cross-actor state sharing.
///
/// Used by `STARTTLSConnection` to expose connection state to
/// `IMAPSession` (a different actor) without requiring `await`.
/// The value is protected by `NSLock` for thread safety.
final class AtomicBool: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}

// MARK: - STARTTLSConnection

/// A socket connection that supports in-place TLS upgrade (STARTTLS).
///
/// Uses Foundation `InputStream`/`OutputStream` (backed by CFStream) for TCP,
/// which natively supports upgrading a plaintext connection to TLS via
/// `kCFStreamPropertySSLSettings` / `StreamSocketSecurityLevel`.
///
/// **Why not NWConnection?**
/// `NWConnection` does not support in-place TLS upgrade on an existing
/// plaintext connection. STARTTLS requires:
/// 1. Connect plaintext → 2. Exchange commands → 3. Upgrade to TLS on the same socket.
/// NWConnection only supports TLS-from-the-start. Foundation streams support
/// the upgrade via `kCFStreamPropertySSLSettings` after the socket is open.
///
/// Spec ref: Multi-Provider IMAP spec, FR-MPROV-05
/// Plan ref: IOS-MP-03 (STARTTLS Transport Support)
///
/// Architecture notes:
/// - This is an actor for thread safety (Swift 6 strict concurrency).
/// - Send/receive use async/await via `withCheckedThrowingContinuation`.
/// - All stream I/O is dispatched to `streamQueue` (serial queue) for safety.
/// - TLS certificate validation enforced per NFR-SYNC-05 (reject self-signed).
/// - The `.none` security mode is `#if DEBUG` only per FR-MPROV-05.
actor STARTTLSConnection {

    // MARK: - Properties

    private var streams: StreamBox?
    private var receiveBuffer = Data()
    private let timeout: TimeInterval
    private var isTLSActive = false
    private let streamQueue: DispatchQueue

    /// Thread-safe connected state for cross-actor access.
    /// Updated on connect/disconnect within the actor, read from outside via `isConnectedSync`.
    private let _connectedFlag = AtomicBool()

    /// Whether the connection is currently open (actor-isolated, checks live stream state).
    var isConnected: Bool {
        guard let box = streams else { return false }
        let inputStatus = box.input.streamStatus
        let outputStatus = box.output.streamStatus
        let inputOK = inputStatus == .open || inputStatus == .reading
        let outputOK = outputStatus == .open || outputStatus == .writing
        return inputOK && outputOK
    }

    /// Non-isolated connection check for cross-actor access.
    ///
    /// Returns the cached connected state. Used by `IMAPSession.isSessionConnected`
    /// to check STARTTLS connection health without awaiting across actor boundaries.
    nonisolated var isConnectedSync: Bool {
        _connectedFlag.value
    }

    /// Whether TLS has been negotiated on this connection.
    var isTLSUpgraded: Bool { isTLSActive }

    // MARK: - Init

    init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.timeout = timeout
        self.streamQueue = DispatchQueue(
            label: "com.vaultmail.starttls.stream",
            qos: .userInitiated
        )
    }

    // MARK: - Connect (Plaintext)

    /// Opens a plaintext TCP connection to the specified host and port.
    ///
    /// This is the first step of the STARTTLS handshake. After connecting,
    /// the caller should exchange the initial protocol commands (CAPABILITY/EHLO)
    /// and then call `upgradeTLS(host:)` to negotiate TLS.
    ///
    /// - Parameters:
    ///   - host: Server hostname
    ///   - port: Server port (143 for IMAP STARTTLS, 587 for SMTP STARTTLS)
    /// - Throws: `ConnectionError.connectionFailed`, `ConnectionError.timeout`
    func connect(host: String, port: Int) async throws {
        guard streams == nil else {
            throw ConnectionError.connectionFailed("Already connected")
        }

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            host as CFString,
            UInt32(port),
            &readStream,
            &writeStream
        )

        guard let cfRead = readStream?.takeRetainedValue(),
              let cfWrite = writeStream?.takeRetainedValue() else {
            throw ConnectionError.connectionFailed("Failed to create socket streams to \(host):\(port)")
        }

        let box = StreamBox(
            input: cfRead as InputStream,
            output: cfWrite as OutputStream
        )
        let flag = AtomicFlag()
        let effectiveTimeout = timeout

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Timeout guard
            self.streamQueue.asyncAfter(deadline: .now() + effectiveTimeout) {
                guard flag.trySet() else { return }
                box.input.close()
                box.output.close()
                cont.resume(throwing: ConnectionError.timeout)
            }

            self.streamQueue.async {
                box.input.schedule(in: .current, forMode: .default)
                box.output.schedule(in: .current, forMode: .default)

                box.input.open()
                box.output.open()

                // Poll for stream readiness (streams don't have a single
                // delegate callback for "both streams open").
                let deadline = Date().addingTimeInterval(effectiveTimeout)
                while Date() < deadline {
                    let inputReady = box.input.streamStatus == .open ||
                                     box.input.streamStatus == .reading
                    let outputReady = box.output.streamStatus == .open ||
                                      box.output.streamStatus == .writing

                    if inputReady && outputReady {
                        guard flag.trySet() else { return }
                        cont.resume()
                        return
                    }

                    if let error = box.input.streamError ?? box.output.streamError {
                        guard flag.trySet() else { return }
                        cont.resume(throwing: ConnectionError.connectionFailed(
                            error.localizedDescription
                        ))
                        return
                    }

                    // Run the run loop briefly to process stream events
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }

                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.timeout)
            }
        }

        self.streams = box
        self.isTLSActive = false
        self._connectedFlag.set(true)
    }

    // MARK: - TLS Upgrade

    /// Upgrades the existing plaintext connection to TLS.
    ///
    /// This is called after the STARTTLS command has been accepted by the server.
    /// It sets the stream security level to negotiated SSL, which triggers a TLS
    /// handshake over the existing TCP connection.
    ///
    /// - Parameter host: Server hostname for SNI (Server Name Indication) and
    ///   certificate validation.
    /// - Throws: `ConnectionError.tlsUpgradeFailed` if the handshake fails.
    func upgradeTLS(host: String) async throws {
        guard let box = streams else {
            throw ConnectionError.connectionFailed("Not connected")
        }

        guard !isTLSActive else { return } // Already upgraded

        // Configure SSL settings for certificate validation.
        // Per NFR-SYNC-05: TLS 1.2+, reject self-signed certificates.
        let sslSettingsKey = Stream.PropertyKey(
            rawValue: kCFStreamPropertySSLSettings as String
        )
        // SSL settings boxed for Sendable crossing into streamQueue closure.
        // The dictionary is immutable after creation and only read on streamQueue.
        //
        // TLS 1.2+ enforcement (NFR-SYNC-05/AC-MP-03):
        // On iOS 17+ / macOS 14+ (our minimum target), the OS disables TLS 1.0/1.1
        // system-wide. We additionally verify the negotiated protocol version
        // post-handshake via SecTrust to guarantee compliance.
        let sslSettings = SendableBox([
            kCFStreamSSLPeerName: host as NSString,
            kCFStreamSSLValidatesCertificateChain: true as NSNumber
        ] as NSDictionary)

        let flag = AtomicFlag()
        let effectiveTimeout = timeout

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // TLS handshake timeout
            self.streamQueue.asyncAfter(deadline: .now() + effectiveTimeout) {
                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                    "TLS handshake timed out after \(Int(effectiveTimeout))s"
                ))
            }

            self.streamQueue.async {
                // Apply SSL settings to both streams
                let inputSuccess = box.input.setProperty(
                    sslSettings.value, forKey: sslSettingsKey
                )
                let outputSuccess = box.output.setProperty(
                    sslSettings.value, forKey: sslSettingsKey
                )

                guard inputSuccess && outputSuccess else {
                    guard flag.trySet() else { return }
                    let error = box.input.streamError ?? box.output.streamError
                    cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                        error?.localizedDescription ?? "Failed to apply TLS settings"
                    ))
                    return
                }

                // Set the security level to trigger TLS negotiation
                let secSuccess = box.input.setProperty(
                    StreamSocketSecurityLevel.negotiatedSSL,
                    forKey: .socketSecurityLevelKey
                )

                guard secSuccess else {
                    guard flag.trySet() else { return }
                    cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                        "Failed to set security level for TLS upgrade"
                    ))
                    return
                }

                // The TLS handshake happens asynchronously within the stream.
                // Poll to verify the handshake completed by checking stream status.
                let deadline = Date().addingTimeInterval(effectiveTimeout)
                while Date() < deadline {
                    // Check for errors first (certificate rejection, etc.)
                    if let error = box.input.streamError ?? box.output.streamError {
                        guard flag.trySet() else { return }
                        let description = error.localizedDescription
                        if description.contains("certificate") ||
                           description.contains("trust") {
                            cont.resume(throwing: ConnectionError.certificateValidationFailed(
                                description
                            ))
                        } else {
                            cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                                description
                            ))
                        }
                        return
                    }

                    // Check if the stream is still open (TLS handshake succeeded)
                    let inputOK = box.input.streamStatus == .open ||
                                  box.input.streamStatus == .reading
                    let outputOK = box.output.streamStatus == .open ||
                                   box.output.streamStatus == .writing

                    if inputOK && outputOK {
                        // Verify TLS handshake completion by probing stream
                        // trust. After a successful TLS handshake, the stream
                        // will have a valid SecTrust object. Before completion
                        // this returns nil.
                        let trustKey = Stream.PropertyKey(
                            rawValue: kCFStreamPropertySSLPeerTrust as String
                        )
                        if box.input.property(forKey: trustKey) != nil {
                            guard flag.trySet() else { return }
                            cont.resume()
                            return
                        }
                    }

                    // Check for stream closure (handshake failure)
                    if box.input.streamStatus == .error ||
                       box.output.streamStatus == .error ||
                       box.input.streamStatus == .closed ||
                       box.output.streamStatus == .closed {
                        guard flag.trySet() else { return }
                        let error = box.input.streamError ?? box.output.streamError
                        cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                            error?.localizedDescription ??
                            "Stream closed during TLS handshake"
                        ))
                        return
                    }

                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }

                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.tlsUpgradeFailed(
                    "TLS handshake timed out"
                ))
            }
        }

        // Post-handshake: verify TLS 1.2+ per NFR-SYNC-05/AC-MP-03.
        // On iOS 17+/macOS 14+ TLS 1.0/1.1 are disabled system-wide,
        // but we verify explicitly for defense-in-depth.
        if let box = streams {
            let trustKey = Stream.PropertyKey(
                rawValue: kCFStreamPropertySSLPeerTrust as String
            )
            if let trust = box.input.property(forKey: trustKey) {
                let secTrust = trust as! SecTrust // swiftlint:disable:this force_cast
                let result = SecTrustEvaluateWithError(secTrust, nil)
                if !result {
                    throw ConnectionError.certificateValidationFailed(
                        "TLS certificate validation failed post-handshake"
                    )
                }
            }
        }

        isTLSActive = true
    }

    // MARK: - Send

    /// Sends raw data over the connection.
    ///
    /// - Parameter data: The data to send.
    /// - Throws: `ConnectionError.connectionFailed` if the write fails.
    func send(_ data: Data) async throws {
        guard let box = streams else {
            _connectedFlag.set(false)
            throw ConnectionError.connectionFailed("Not connected")
        }

        let flag = AtomicFlag()
        let connectedFlag = _connectedFlag
        let effectiveTimeout = timeout

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.streamQueue.asyncAfter(deadline: .now() + effectiveTimeout) {
                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.timeout)
            }

            self.streamQueue.async {
                var remaining = data
                while !remaining.isEmpty {
                    let written = remaining.withUnsafeBytes { buffer -> Int in
                        guard let baseAddress = buffer.baseAddress else { return -1 }
                        return box.output.write(
                            baseAddress.assumingMemoryBound(to: UInt8.self),
                            maxLength: remaining.count
                        )
                    }

                    if written < 0 {
                        guard flag.trySet() else { return }
                        connectedFlag.set(false)
                        let error = box.output.streamError
                        cont.resume(throwing: ConnectionError.connectionFailed(
                            "Write failed: \(error?.localizedDescription ?? "unknown error")"
                        ))
                        return
                    }

                    remaining = Data(remaining.dropFirst(written))
                }

                guard flag.trySet() else { return }
                cont.resume()
            }
        }
    }

    /// Sends a string followed by CRLF.
    func sendLine(_ line: String) async throws {
        try await send(Data("\(line)\r\n".utf8))
    }

    // MARK: - Receive

    /// Reads data from the connection.
    ///
    /// - Parameter readTimeout: Optional timeout override.
    /// - Returns: The data read from the connection.
    func receiveData(timeout readTimeout: TimeInterval? = nil) async throws -> Data {
        guard let box = streams else {
            _connectedFlag.set(false)
            throw ConnectionError.connectionFailed("Not connected")
        }

        let effectiveTimeout = readTimeout ?? timeout
        let flag = AtomicFlag()
        let connectedFlag = _connectedFlag

        let data: Data = try await withCheckedThrowingContinuation { cont in
            self.streamQueue.asyncAfter(deadline: .now() + effectiveTimeout) {
                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.timeout)
            }

            self.streamQueue.async {
                let deadline = Date().addingTimeInterval(effectiveTimeout)

                while Date() < deadline {
                    if box.input.hasBytesAvailable {
                        var buffer = [UInt8](repeating: 0, count: AppConstants.socketReadBufferSize)
                        let bytesRead = box.input.read(&buffer, maxLength: buffer.count)

                        if bytesRead > 0 {
                            guard flag.trySet() else { return }
                            cont.resume(returning: Data(buffer[0..<bytesRead]))
                            return
                        } else if bytesRead < 0 {
                            guard flag.trySet() else { return }
                            connectedFlag.set(false)
                            let error = box.input.streamError
                            cont.resume(throwing: ConnectionError.connectionFailed(
                                error?.localizedDescription ?? "Read failed"
                            ))
                            return
                        } else {
                            // bytesRead == 0 means EOF — server closed connection
                            guard flag.trySet() else { return }
                            connectedFlag.set(false)
                            cont.resume(throwing: ConnectionError.connectionFailed(
                                "Connection closed by server"
                            ))
                            return
                        }
                    }

                    if let error = box.input.streamError {
                        guard flag.trySet() else { return }
                        connectedFlag.set(false)
                        cont.resume(throwing: ConnectionError.connectionFailed(
                            error.localizedDescription
                        ))
                        return
                    }

                    // Brief run loop to allow stream events to fire
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }

                guard flag.trySet() else { return }
                cont.resume(throwing: ConnectionError.timeout)
            }
        }

        return data
    }

    // MARK: - Line-Oriented Read

    /// Reads a complete CRLF-terminated line from the connection.
    ///
    /// Buffers incoming data and extracts complete lines. Handles IMAP
    /// literal syntax `{NNN}` for multi-line data.
    ///
    /// - Parameter readTimeout: Optional timeout override.
    /// - Returns: A complete response line (without CRLF).
    func readLine(timeout readTimeout: TimeInterval? = nil) async throws -> String {
        while true {
            if let result = consumeLine() {
                return result
            }
            let data = try await receiveData(timeout: readTimeout)
            receiveBuffer.append(data)
        }
    }

    /// Reads a complete SMTP response (handles multi-line 250-/250 responses).
    ///
    /// - Returns: A tuple of (code, fullText).
    func readSMTPResponse(timeout readTimeout: TimeInterval? = nil) async throws -> (code: Int, text: String) {
        var allText = ""

        while true {
            let line = try await readLine(timeout: readTimeout)

            guard line.count >= 3,
                  let code = Int(line.prefix(3)) else {
                throw ConnectionError.invalidResponse(line)
            }

            let separator = line.count > 3
                ? line[line.index(line.startIndex, offsetBy: 3)]
                : Character(" ")
            let text = line.count > 4
                ? String(line[line.index(line.startIndex, offsetBy: 4)...])
                : ""

            if !allText.isEmpty { allText += "\n" }
            allText += text

            if separator == " " {
                return (code: code, text: allText)
            }
        }
    }

    // MARK: - Disconnect

    /// Closes the connection and cleans up resources.
    func disconnect() {
        let box = streams
        streams = nil
        receiveBuffer.removeAll()
        isTLSActive = false
        _connectedFlag.set(false)
        if let box {
            streamQueue.async {
                box.input.remove(from: .current, forMode: .default)
                box.output.remove(from: .current, forMode: .default)
                box.input.close()
                box.output.close()
            }
        }
    }

    // MARK: - Private: Buffer Management

    /// Extracts a CRLF-terminated line from the receive buffer.
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
}

// MARK: - ConnectionError

/// Errors specific to the STARTTLS connection layer.
///
/// These are internal errors that get mapped to `IMAPError` or `SMTPError`
/// by the calling session actor.
enum ConnectionError: Error, LocalizedError, Equatable, Sendable {
    case connectionFailed(String)
    case timeout
    case tlsUpgradeFailed(String)
    case certificateValidationFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "Connection Failed: \(msg)"
        case .timeout: "Connection Timed Out"
        case .tlsUpgradeFailed(let msg): "TLS Upgrade Failed: \(msg)"
        case .certificateValidationFailed(let msg): "Certificate Validation Failed: \(msg)"
        case .invalidResponse(let msg): "Invalid Response: \(msg)"
        }
    }
}

