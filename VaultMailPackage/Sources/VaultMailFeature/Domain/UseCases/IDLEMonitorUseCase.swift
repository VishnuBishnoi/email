import Foundation

/// Events emitted by the IMAP IDLE monitor.
///
/// Spec ref: FR-SYNC-03 (Real-time push via IDLE)
public enum IDLEEvent: Sendable, Equatable {
    /// New email(s) arrived — trigger incremental sync.
    case newMail
    /// IDLE connection dropped or was stopped. Caller should restart if desired.
    case disconnected
}

/// Domain use case for monitoring an IMAP folder via IDLE.
///
/// Wraps `IMAPClientProtocol.startIDLE()` in an `AsyncStream<IDLEEvent>`
/// for clean integration with SwiftUI's `.task` modifier.
///
/// The monitor acquires a dedicated IMAP connection from the pool,
/// selects the specified folder, and enters IDLE mode. On new mail,
/// it emits `.newMail`. The stream terminates when the task is cancelled
/// or the connection drops.
///
/// Gmail IDLE quirk: connections are dropped after ~29 minutes.
/// The underlying `IMAPClient.runIDLELoop()` handles the 25-minute
/// re-issue automatically.
///
/// Spec ref: FR-SYNC-03, FR-SYNC-05
@MainActor
public protocol IDLEMonitorUseCaseProtocol {
    /// Monitors a folder for new mail via IMAP IDLE.
    ///
    /// Returns an `AsyncStream` that yields `.newMail` events.
    /// Cancel the consuming task to stop monitoring.
    ///
    /// - Parameters:
    ///   - accountId: Account to monitor.
    ///   - folderImapPath: IMAP path of the folder (e.g. "INBOX").
    func monitor(accountId: String, folderImapPath: String) -> AsyncStream<IDLEEvent>
}

@MainActor
public final class IDLEMonitorUseCase: IDLEMonitorUseCaseProtocol {

    private let connectionProvider: ConnectionProviding
    private let accountRepository: AccountRepositoryProtocol
    private let keychainManager: KeychainManagerProtocol

    public init(
        connectionProvider: ConnectionProviding,
        accountRepository: AccountRepositoryProtocol,
        keychainManager: KeychainManagerProtocol
    ) {
        self.connectionProvider = connectionProvider
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
    }

    public func monitor(accountId: String, folderImapPath: String) -> AsyncStream<IDLEEvent> {
        let provider = connectionProvider
        let accountRepo = accountRepository
        let keychain = keychainManager

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var client: (any IMAPClientProtocol)?
                var resolvedAccountId: String?

                defer {
                    // Synchronous defer ensures cleanup runs before the
                    // enclosing scope returns — no race with pool reuse.
                    if let client, let accountId = resolvedAccountId {
                        Task {
                            try? await client.stopIDLE()
                            await provider.checkinConnection(client, accountId: accountId)
                        }
                    }
                    continuation.finish()
                }

                do {
                    // 1. Resolve account credentials
                    let accounts = try await accountRepo.getAccounts()
                    guard let account = accounts.first(where: { $0.id == accountId }) else {
                        NSLog("[IDLE] Account \(accountId) not found")
                        continuation.yield(.disconnected)
                        return
                    }
                    resolvedAccountId = account.id

                    // 2. Resolve IMAP credential via shared CredentialResolver
                    let credentialResolver = CredentialResolver(
                        keychainManager: keychain,
                        accountRepository: accountRepo
                    )
                    let imapCredential: IMAPCredential
                    do {
                        imapCredential = try await credentialResolver.resolveIMAPCredential(
                            for: account,
                            refreshIfNeeded: true
                        )
                    } catch {
                        NSLog("[IDLE] No credentials found for account \(accountId): \(error)")
                        continuation.yield(.disconnected)
                        return
                    }

                    client = try await provider.checkoutConnection(
                        accountId: account.id,
                        host: account.imapHost,
                        port: account.imapPort,
                        security: account.resolvedImapSecurity,
                        credential: imapCredential
                    )

                    guard let c = client else {
                        continuation.yield(.disconnected)
                        return
                    }

                    // 2b. Set provider-specific IDLE refresh interval (MP-13)
                    if let providerConfig = ProviderRegistry.provider(for: account.resolvedProvider) {
                        // idleRefreshInterval uses thread-safe LockedValue storage
                        client?.idleRefreshInterval = providerConfig.idleRefreshInterval
                    }

                    // 3. Select the folder for IDLE
                    _ = try await c.selectFolder(folderImapPath)

                    // 4. Start IDLE — the callback fires on each EXISTS notification
                    try await c.startIDLE {
                        continuation.yield(.newMail)
                    }

                    // Wait until task is cancelled (IDLE runs in background)
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(1))
                    }

                } catch is CancellationError {
                    // Normal cancellation (folder change, view disappear) —
                    // NOT a disconnect. Don't yield .disconnected so the
                    // caller's retry loop doesn't fire unnecessarily.
                    NSLog("[IDLE] Monitor cancelled for \(accountId)")
                } catch {
                    NSLog("[IDLE] Monitor error for \(accountId): \(error)")
                    continuation.yield(.disconnected)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
