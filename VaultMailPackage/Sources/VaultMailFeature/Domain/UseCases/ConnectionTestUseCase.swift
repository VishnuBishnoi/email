import Foundation

/// Status of an individual connection test step.
///
/// Used by the Manual Account Setup UI to show a live 4-step checklist.
///
/// Spec ref: FR-MPROV-09 (Manual Account Setup)
public enum ConnectionTestStep: Sendable, Equatable {
    case imapConnect
    case imapAuth
    case smtpConnect
    case smtpAuth
}

/// Result of an individual connection test step.
public enum ConnectionTestStepResult: Sendable, Equatable {
    case pending
    case testing
    case success
    case failure(String)
}

/// Overall result of a connection test.
public struct ConnectionTestResult: Sendable, Equatable {
    public var imapConnect: ConnectionTestStepResult = .pending
    public var imapAuth: ConnectionTestStepResult = .pending
    public var smtpConnect: ConnectionTestStepResult = .pending
    public var smtpAuth: ConnectionTestStepResult = .pending

    /// Whether all steps succeeded.
    public var allPassed: Bool {
        imapConnect == .success && imapAuth == .success &&
        smtpConnect == .success && smtpAuth == .success
    }

    /// Whether any step failed.
    public var hasFailed: Bool {
        [imapConnect, imapAuth, smtpConnect, smtpAuth].contains(where: {
            if case .failure = $0 { return true }
            return false
        })
    }
}

/// Domain use case for testing IMAP/SMTP connection settings.
///
/// Runs a 4-step checklist (IMAP connect → IMAP auth → SMTP connect → SMTP auth)
/// with live status updates via an AsyncStream. Used by the Manual Account Setup UI
/// to validate user-entered settings before saving.
///
/// Spec ref: FR-MPROV-09 (Manual Account Setup)
@MainActor
public protocol ConnectionTestUseCaseProtocol {
    /// Tests IMAP and SMTP connections with the given settings.
    ///
    /// Returns an AsyncStream of `ConnectionTestResult` that emits updates
    /// as each step is tested. The stream completes after all steps finish.
    func testConnection(
        imapHost: String,
        imapPort: Int,
        imapSecurity: ConnectionSecurity,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: ConnectionSecurity,
        email: String,
        password: String
    ) -> AsyncStream<ConnectionTestResult>
}

@MainActor
public final class ConnectionTestUseCase: ConnectionTestUseCaseProtocol {

    private let imapClientFactory: @Sendable () -> any IMAPClientProtocol
    private let smtpClientFactory: @Sendable () -> any SMTPClientProtocol

    public init(
        imapClientFactory: @escaping @Sendable () -> any IMAPClientProtocol = { IMAPClient() },
        smtpClientFactory: @escaping @Sendable () -> any SMTPClientProtocol = { SMTPClient() }
    ) {
        self.imapClientFactory = imapClientFactory
        self.smtpClientFactory = smtpClientFactory
    }

    public func testConnection(
        imapHost: String,
        imapPort: Int,
        imapSecurity: ConnectionSecurity,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: ConnectionSecurity,
        email: String,
        password: String
    ) -> AsyncStream<ConnectionTestResult> {
        let imapFactory = imapClientFactory
        let smtpFactory = smtpClientFactory

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var result = ConnectionTestResult()

                // Step 1: IMAP Connect
                result.imapConnect = .testing
                continuation.yield(result)

                let imapClient = imapFactory()
                do {
                    try await imapClient.connect(
                        host: imapHost,
                        port: imapPort,
                        security: imapSecurity,
                        credential: .plain(username: email, password: password)
                    )
                    result.imapConnect = .success
                    result.imapAuth = .success
                    continuation.yield(result)
                } catch {
                    // Distinguish connect vs auth failure
                    let errorMsg = error.localizedDescription
                    if errorMsg.lowercased().contains("auth") || errorMsg.lowercased().contains("login") {
                        result.imapConnect = .success
                        result.imapAuth = .failure(errorMsg)
                    } else {
                        result.imapConnect = .failure(errorMsg)
                        result.imapAuth = .failure("Skipped — connection failed")
                    }
                    continuation.yield(result)

                    // Skip SMTP if IMAP auth failed
                    result.smtpConnect = .failure("Skipped")
                    result.smtpAuth = .failure("Skipped")
                    continuation.yield(result)
                    continuation.finish()

                    // Disconnect in background — don't block stream consumers
                    Task { try? await imapClient.disconnect() }
                    return
                }

                // Step 3: SMTP Connect + Auth
                result.smtpConnect = .testing
                continuation.yield(result)

                let smtpClient = smtpFactory()
                do {
                    try await smtpClient.connect(
                        host: smtpHost,
                        port: smtpPort,
                        security: smtpSecurity,
                        credential: .plain(username: email, password: password)
                    )
                    result.smtpConnect = .success
                    result.smtpAuth = .success
                    continuation.yield(result)
                } catch {
                    let errorMsg = error.localizedDescription
                    if errorMsg.lowercased().contains("auth") {
                        result.smtpConnect = .success
                        result.smtpAuth = .failure(errorMsg)
                    } else {
                        result.smtpConnect = .failure(errorMsg)
                        result.smtpAuth = .failure("Skipped — connection failed")
                    }
                    continuation.yield(result)
                }

                // Finish the stream BEFORE disconnecting so consumers
                // (the `for await` loop in the UI) complete immediately.
                continuation.finish()

                // Disconnect in background — don't block the @MainActor
                Task {
                    try? await imapClient.disconnect()
                    try? await smtpClient.disconnect()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
