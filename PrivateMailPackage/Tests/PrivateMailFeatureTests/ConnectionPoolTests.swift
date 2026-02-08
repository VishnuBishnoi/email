import Foundation
import Testing
@testable import PrivateMailFeature

/// Tests for the IMAP connection pool.
///
/// Validates that the ConnectionPool correctly manages connection lifecycle,
/// enforces per-account connection limits (FR-SYNC-09: max 5 for Gmail),
/// queues operations when exhausted (not throw), and handles edge cases.
///
/// A `ConnectionFactory` is injected so tests can run without real
/// IMAP servers — each factory call returns a real `IMAPClient` instance
/// but skips the network connect step.
///
/// Spec ref: FR-SYNC-09 (Connection Management)
/// Validation ref: AC-F-05
@Suite("Connection Pool — FR-SYNC-09")
struct ConnectionPoolTests {

    // MARK: - Helpers

    /// Factory that returns an `IMAPClient` without connecting to a server.
    /// Suitable for unit tests that only exercise pool bookkeeping.
    private static let testFactory: ConnectionPool.ConnectionFactory = { _, _, _, _ in
        IMAPClient()
    }

    /// Creates a pool pre-configured for unit tests (no network).
    private func makePool(
        max: Int = AppConstants.imapMaxConnectionsPerAccount,
        waitTimeout: TimeInterval = 30
    ) -> ConnectionPool {
        ConnectionPool(
            maxConnectionsPerAccount: max,
            waitTimeout: waitTimeout,
            connectionFactory: Self.testFactory
        )
    }

    // MARK: - Initialization

    @Test("Pool initializes with correct max connections (FR-SYNC-09: 5)")
    func poolDefaultMax() async {
        let pool = makePool()

        // Verify starts empty
        let count = await pool.connectionCount(for: "test-account")
        #expect(count == 0)
    }

    @Test("Pool initializes with custom max connections")
    func poolCustomMax() async {
        let pool = makePool(max: 3)

        let count = await pool.connectionCount(for: "test-account")
        #expect(count == 0)
    }

    // MARK: - Checkout Creates Connections

    @Test("Checkout creates a connection when pool is empty")
    func checkoutCreatesConnection() async throws {
        let pool = makePool(max: 2)

        let client = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Pool now has 1 connection, checked out
        let total = await pool.connectionCount(for: "acct-1")
        let active = await pool.activeConnectionCount(for: "acct-1")
        #expect(total == 1)
        #expect(active == 1)

        // Clean up
        await pool.checkin(client, accountId: "acct-1")
    }

    @Test("Checkout creates up to max connections")
    func checkoutUpToMax() async throws {
        let pool = makePool(max: 3)

        var clients: [IMAPClient] = []
        for _ in 0..<3 {
            let client = try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
            clients.append(client)
        }

        let total = await pool.connectionCount(for: "acct-1")
        let active = await pool.activeConnectionCount(for: "acct-1")
        #expect(total == 3)
        #expect(active == 3)

        // Clean up
        for client in clients {
            await pool.checkin(client, accountId: "acct-1")
        }
    }

    // MARK: - Checkin / Reuse

    @Test("Checkin makes connection available for reuse")
    func checkinReuse() async throws {
        let pool = makePool(max: 1)

        let client1 = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        await pool.checkin(client1, accountId: "acct-1")

        let active = await pool.activeConnectionCount(for: "acct-1")
        #expect(active == 0)

        // Pool still has 1 connection (idle)
        let total = await pool.connectionCount(for: "acct-1")
        #expect(total == 1)
    }

    // MARK: - Connection Count Tracking

    @Test("connectionCount returns 0 for unknown account")
    func connectionCountUnknown() async {
        let pool = makePool()

        let count = await pool.connectionCount(for: "nonexistent-account")
        #expect(count == 0)
    }

    @Test("activeConnectionCount returns 0 for unknown account")
    func activeConnectionCountUnknown() async {
        let pool = makePool()

        let count = await pool.activeConnectionCount(for: "nonexistent-account")
        #expect(count == 0)
    }

    @Test("connectionCount and activeConnectionCount are consistent for empty pool")
    func countsConsistentEmpty() async {
        let pool = makePool()

        let total = await pool.connectionCount(for: "account-1")
        let active = await pool.activeConnectionCount(for: "account-1")

        #expect(total == 0)
        #expect(active == 0)
        #expect(active <= total)
    }

    @Test("waiterCount returns 0 for unknown account")
    func waiterCountUnknown() async {
        let pool = makePool()

        let count = await pool.waiterCount(for: "nonexistent")
        #expect(count == 0)
    }

    // MARK: - Pool Exhaustion Queuing (FR-SYNC-09)

    @Test("Checkout queues when pool is exhausted, resumes on checkin")
    func checkoutQueuesAndResumesOnCheckin() async throws {
        let pool = makePool(max: 1, waitTimeout: 5)

        // Checkout the only connection
        let client1 = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Second checkout should queue (not throw)
        let waiterTask = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }

        // Give the waiter task time to enqueue
        try await Task.sleep(for: .milliseconds(50))

        // Verify there is a waiter queued
        let waiters = await pool.waiterCount(for: "acct-1")
        #expect(waiters == 1)

        // Return the connection — should wake the waiter
        await pool.checkin(client1, accountId: "acct-1")

        // Waiter should now resolve with the same client
        let client2 = try await waiterTask.value

        #expect(client1 === client2, "Waiter should receive the same connection that was checked in")

        // No more waiters
        let waitersAfter = await pool.waiterCount(for: "acct-1")
        #expect(waitersAfter == 0)

        // Clean up
        await pool.checkin(client2, accountId: "acct-1")
    }

    @Test("Multiple waiters are served in FIFO order")
    func checkoutFIFOOrder() async throws {
        let pool = makePool(max: 1, waitTimeout: 5)

        let client = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Queue two waiters
        let arrivedFirst = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }

        // Small delay to ensure ordering
        try await Task.sleep(for: .milliseconds(30))

        let arrivedSecond = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }

        try await Task.sleep(for: .milliseconds(30))

        let waiters = await pool.waiterCount(for: "acct-1")
        #expect(waiters == 2)

        // Return the connection — first waiter gets it
        await pool.checkin(client, accountId: "acct-1")
        let firstResult = try await arrivedFirst.value
        #expect(firstResult === client, "First waiter should be served first (FIFO)")

        // Return again — second waiter gets it
        await pool.checkin(firstResult, accountId: "acct-1")
        let secondResult = try await arrivedSecond.value
        #expect(secondResult === client, "Second waiter should get the same connection")

        await pool.checkin(secondResult, accountId: "acct-1")
    }

    @Test("Checkout times out when pool stays exhausted")
    func checkoutTimesOut() async throws {
        // Very short timeout for test speed
        let pool = makePool(max: 1, waitTimeout: 0.1)

        // Exhaust the pool
        let client = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Second checkout should queue and then timeout
        await #expect(throws: IMAPError.self) {
            _ = try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }

        // Waiters should be cleared after timeout
        let waiters = await pool.waiterCount(for: "acct-1")
        #expect(waiters == 0)

        await pool.checkin(client, accountId: "acct-1")
    }

    @Test("Checkout with max 0 times out (not throw immediately)")
    func checkoutMaxZeroTimesOut() async throws {
        let pool = makePool(max: 0, waitTimeout: 0.1)

        await #expect(throws: IMAPError.self) {
            _ = try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }
    }

    // MARK: - Shutdown Cancels Waiters

    @Test("Shutdown cancels all queued waiters with operationCancelled")
    func shutdownCancelsWaiters() async throws {
        let pool = makePool(max: 1, waitTimeout: 30)

        let client = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Queue a waiter
        let waiterTask = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }

        try await Task.sleep(for: .milliseconds(50))

        // Shutdown should cancel the waiter
        await pool.shutdown()

        // Waiter should receive operationCancelled
        do {
            _ = try await waiterTask.value
            Issue.record("Waiter should have thrown after shutdown")
        } catch let error as IMAPError {
            #expect(error == .operationCancelled)
        }

        // Return client (pool is already shut down, this is a no-op)
        await pool.checkin(client, accountId: "acct-1")
    }

    @Test("disconnectAll cancels waiters for that account only")
    func disconnectAllCancelsAccountWaiters() async throws {
        let pool = makePool(max: 1, waitTimeout: 30)

        // Exhaust account-1
        let client1 = try await pool.checkout(
            accountId: "acct-1",
            host: "imap.gmail.com",
            port: 993,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Exhaust account-2
        let client2 = try await pool.checkout(
            accountId: "acct-2",
            host: "imap.gmail.com",
            port: 993,
            email: "other@gmail.com",
            accessToken: "token2"
        )

        // Queue waiters for both accounts
        let waiter1 = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-1",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }
        let waiter2 = Task<IMAPClient, Error> {
            try await pool.checkout(
                accountId: "acct-2",
                host: "imap.gmail.com",
                port: 993,
                email: "other@gmail.com",
                accessToken: "token2"
            )
        }

        try await Task.sleep(for: .milliseconds(50))

        // Disconnect only account-1
        await pool.disconnectAll(accountId: "acct-1")

        // Waiter 1 should be cancelled
        do {
            _ = try await waiter1.value
            Issue.record("Waiter 1 should have thrown after disconnectAll")
        } catch let error as IMAPError {
            #expect(error == .operationCancelled)
        }

        // Waiter 2 should still be waiting (not cancelled)
        let waiters2 = await pool.waiterCount(for: "acct-2")
        #expect(waiters2 == 1)

        // Clean up: checkin client2 so waiter2 resolves, then shutdown
        await pool.checkin(client2, accountId: "acct-2")
        _ = try? await waiter2.value

        // client1's pool is already disconnected
        _ = client1  // suppress unused warning
        await pool.shutdown()
    }

    // MARK: - Safe Lifecycle Operations

    @Test("checkin with unknown client does not crash")
    func checkinUnknownClient() async {
        let pool = makePool()
        let unknownClient = IMAPClient()

        // This should be a no-op, not crash
        await pool.checkin(unknownClient, accountId: "nonexistent")

        let count = await pool.connectionCount(for: "nonexistent")
        #expect(count == 0)
    }

    @Test("disconnectAll with unknown account does not crash")
    func disconnectAllUnknown() async {
        let pool = makePool()

        // Should be safe to call with nonexistent account
        await pool.disconnectAll(accountId: "nonexistent")

        let count = await pool.connectionCount(for: "nonexistent")
        #expect(count == 0)
    }

    @Test("shutdown with empty pool does not crash")
    func shutdownEmpty() async {
        let pool = makePool()

        // Should safely handle empty pool
        await pool.shutdown()
    }

    @Test("Multiple disconnectAll calls are safe")
    func disconnectAllIdempotent() async {
        let pool = makePool()

        await pool.disconnectAll(accountId: "account-1")
        await pool.disconnectAll(accountId: "account-1")
        await pool.disconnectAll(accountId: "account-1")

        let count = await pool.connectionCount(for: "account-1")
        #expect(count == 0)
    }

    @Test("Multiple shutdown calls are safe")
    func shutdownIdempotent() async {
        let pool = makePool()

        await pool.shutdown()
        await pool.shutdown()
        await pool.shutdown()
    }

    // MARK: - Multi-Account Isolation (E-08)

    @Test("Connection counts are isolated per account")
    func multiAccountIsolation() async throws {
        let pool = makePool(max: 5)

        let clientA = try await pool.checkout(
            accountId: "acct-A",
            host: "imap.gmail.com",
            port: 993,
            email: "a@gmail.com",
            accessToken: "tokenA"
        )

        let countA = await pool.connectionCount(for: "acct-A")
        let countB = await pool.connectionCount(for: "acct-B")

        #expect(countA == 1)
        #expect(countB == 0)

        await pool.checkin(clientA, accountId: "acct-A")
    }

    @Test("disconnectAll only affects specified account")
    func disconnectAllIsolation() async throws {
        let pool = makePool(max: 5)

        let clientA = try await pool.checkout(
            accountId: "acct-A",
            host: "imap.gmail.com",
            port: 993,
            email: "a@gmail.com",
            accessToken: "tokenA"
        )
        let clientB = try await pool.checkout(
            accountId: "acct-B",
            host: "imap.gmail.com",
            port: 993,
            email: "b@gmail.com",
            accessToken: "tokenB"
        )

        // Disconnect account A only
        await pool.disconnectAll(accountId: "acct-A")

        let countA = await pool.connectionCount(for: "acct-A")
        let countB = await pool.connectionCount(for: "acct-B")

        #expect(countA == 0)
        #expect(countB == 1)

        _ = clientA
        await pool.checkin(clientB, accountId: "acct-B")
        await pool.shutdown()
    }

    // MARK: - Constants Verification

    @Test("Default max connections matches FR-SYNC-09 Gmail limit")
    func maxConnectionsConstant() {
        #expect(AppConstants.imapMaxConnectionsPerAccount == 5)
    }
}
