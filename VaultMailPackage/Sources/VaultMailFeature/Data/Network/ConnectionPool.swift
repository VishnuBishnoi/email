import Foundation

/// Manages a pool of IMAP connections per account.
///
/// Enforces the maximum concurrent connection limit per account
/// (FR-SYNC-09: max 5 for Gmail) and provides checkout/return
/// semantics for connection reuse.
///
/// When the pool is exhausted, callers are **queued** until a connection
/// becomes available — operations are never rejected simply because
/// all connections are in use (FR-SYNC-09 spec requirement).
///
/// Spec ref: FR-SYNC-09 (Connection Management)
public actor ConnectionPool {

    // MARK: - Types

    /// A pooled connection entry.
    private struct PoolEntry {
        let client: IMAPClient
        var isCheckedOut: Bool
    }

    /// A caller waiting for a connection to become available.
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<IMAPClient, any Error>
    }

    /// Factory closure that creates and connects an `IMAPClient`.
    /// Injected for testability — tests can provide a mock factory
    /// that avoids real network connections.
    public typealias ConnectionFactory = @Sendable (
        _ host: String,
        _ port: Int,
        _ email: String,
        _ accessToken: String
    ) async throws -> IMAPClient

    // MARK: - Properties

    /// Connections indexed by account ID.
    private var pools: [String: [PoolEntry]] = [:]

    /// Callers waiting for a connection, indexed by account ID (FIFO order).
    private var waiters: [String: [Waiter]] = [:]

    /// Maximum connections per account (FR-SYNC-09: 5 for Gmail).
    private let maxConnectionsPerAccount: Int

    /// How long a caller will wait for a connection before timing out.
    private let waitTimeout: TimeInterval

    /// Factory for creating new IMAP connections.
    private let connectionFactory: ConnectionFactory

    // MARK: - Init

    /// Creates a connection pool.
    ///
    /// - Parameters:
    ///   - maxConnectionsPerAccount: Per-account connection cap (FR-SYNC-09: 5).
    ///   - waitTimeout: Seconds to wait when pool is exhausted before timing out.
    ///   - connectionFactory: Optional factory for creating connections.
    ///     Defaults to creating a real `IMAPClient` and calling `connect`.
    public init(
        maxConnectionsPerAccount: Int = AppConstants.imapMaxConnectionsPerAccount,
        waitTimeout: TimeInterval = AppConstants.imapConnectionTimeout,
        connectionFactory: ConnectionFactory? = nil
    ) {
        self.maxConnectionsPerAccount = maxConnectionsPerAccount
        self.waitTimeout = waitTimeout
        self.connectionFactory = connectionFactory ?? { host, port, email, accessToken in
            let client = IMAPClient()
            try await client.connect(host: host, port: port, email: email, accessToken: accessToken)
            return client
        }
    }

    // MARK: - Checkout / Return

    /// Checks out an available connection for the given account.
    ///
    /// Resolution order:
    /// 1. Reuse an idle (checked-in) connection if one exists.
    /// 2. Create a new connection if under the per-account limit.
    /// 3. **Queue** the caller until a connection is returned via `checkin`
    ///    (FR-SYNC-09: "pool exhaustion MUST queue operations").
    ///
    /// - Parameters:
    ///   - accountId: Unique account identifier
    ///   - host: IMAP server hostname
    ///   - port: IMAP server port
    ///   - email: User's email address
    ///   - accessToken: OAuth access token
    /// - Returns: A connected `IMAPClient` ready for use
    /// - Throws: `IMAPError.timeout` if no connection becomes available
    ///   within `waitTimeout` seconds.
    public func checkout(
        accountId: String,
        host: String,
        port: Int,
        email: String,
        accessToken: String
    ) async throws -> IMAPClient {
        // Loop until we find/create a connection or queue (avoids recursive actor re-entrance)
        while true {
            var entries = pools[accountId] ?? []

            // 1. Try to find an idle (checked-in) connection
            var foundDeadConnection = false
            for i in entries.indices.reversed() { // Reverse iteration for safe removal
                if !entries[i].isCheckedOut {
                    let client = entries[i].client
                    let connected = await client.isConnected

                    if connected {
                        entries[i].isCheckedOut = true
                        pools[accountId] = entries
                        return client
                    } else {
                        // Dead connection — remove it and continue loop
                        entries.remove(at: i)
                        pools[accountId] = entries
                        foundDeadConnection = true
                        break // Exit inner loop, continue outer while loop
                    }
                }
            }

            // If we removed a dead connection, retry the search (continue while loop)
            if foundDeadConnection {
                continue
            }

            // 2. Create a new connection if under the limit
            if entries.count < maxConnectionsPerAccount {
                let client = try await connectionFactory(host, port, email, accessToken)
                entries.append(PoolEntry(client: client, isCheckedOut: true))
                pools[accountId] = entries
                return client
            }

            // 3. Pool exhausted — queue until a connection becomes available (FR-SYNC-09)
            let waiterId = UUID()
            let timeout = self.waitTimeout

            return try await withCheckedThrowingContinuation { continuation in
                var accountWaiters = self.waiters[accountId] ?? []
                accountWaiters.append(Waiter(id: waiterId, continuation: continuation))
                self.waiters[accountId] = accountWaiters

                // Schedule a timeout so callers don't wait forever
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    await self?.timeoutWaiter(id: waiterId, accountId: accountId)
                }
            }
        }
    }

    /// Returns a connection to the pool for reuse.
    ///
    /// If callers are queued (waiting for a connection), the first waiter
    /// receives this connection immediately (FIFO). Otherwise the connection
    /// is marked idle in the pool.
    ///
    /// - Parameters:
    ///   - client: The `IMAPClient` to return
    ///   - accountId: The account ID this client belongs to
    public func checkin(_ client: IMAPClient, accountId: String) {
        guard var entries = pools[accountId] else { return }

        for i in entries.indices {
            if entries[i].client === client {
                // Hand off to a waiting caller if one exists (FIFO)
                if var accountWaiters = waiters[accountId], !accountWaiters.isEmpty {
                    let waiter = accountWaiters.removeFirst()
                    waiters[accountId] = accountWaiters.isEmpty ? nil : accountWaiters
                    // Connection stays checked out — ownership transfers to waiter
                    waiter.continuation.resume(returning: client)
                    return
                }

                // No waiters — mark as available
                entries[i].isCheckedOut = false
                pools[accountId] = entries
                return
            }
        }
    }

    // MARK: - Timeout

    /// Cancels a waiter that has exceeded the wait timeout.
    ///
    /// If the waiter was already served by `checkin`, this is a no-op.
    private func timeoutWaiter(id: UUID, accountId: String) {
        guard var accountWaiters = waiters[accountId] else { return }
        if let index = accountWaiters.firstIndex(where: { $0.id == id }) {
            let waiter = accountWaiters.remove(at: index)
            waiters[accountId] = accountWaiters.isEmpty ? nil : accountWaiters
            waiter.continuation.resume(throwing: IMAPError.timeout)
        }
        // If not found, the waiter was already resumed by checkin — safe no-op
    }

    // MARK: - Lifecycle

    /// Disconnects all connections for a specific account.
    ///
    /// Any callers queued for this account are resumed with
    /// `IMAPError.operationCancelled`.
    public func disconnectAll(accountId: String) async {
        // Cancel all waiters for this account
        if let accountWaiters = waiters[accountId] {
            for waiter in accountWaiters {
                waiter.continuation.resume(throwing: IMAPError.operationCancelled)
            }
            waiters.removeValue(forKey: accountId)
        }

        guard let entries = pools[accountId] else { return }

        for entry in entries {
            try? await entry.client.disconnect()
        }

        pools.removeValue(forKey: accountId)
    }

    /// Disconnects all connections across all accounts.
    ///
    /// Any queued callers across all accounts are resumed with
    /// `IMAPError.operationCancelled`.
    public func shutdown() async {
        // Cancel all waiters across all accounts
        for (_, accountWaiters) in waiters {
            for waiter in accountWaiters {
                waiter.continuation.resume(throwing: IMAPError.operationCancelled)
            }
        }
        waiters.removeAll()

        for accountId in pools.keys {
            if let entries = pools[accountId] {
                for entry in entries {
                    try? await entry.client.disconnect()
                }
            }
        }
        pools.removeAll()
    }

    // MARK: - Diagnostics

    /// Returns the current connection count for an account.
    public func connectionCount(for accountId: String) -> Int {
        pools[accountId]?.count ?? 0
    }

    /// Returns the number of active (checked-out) connections for an account.
    public func activeConnectionCount(for accountId: String) -> Int {
        pools[accountId]?.filter { $0.isCheckedOut }.count ?? 0
    }

    /// Returns the number of callers currently waiting for a connection.
    public func waiterCount(for accountId: String) -> Int {
        waiters[accountId]?.count ?? 0
    }
}
