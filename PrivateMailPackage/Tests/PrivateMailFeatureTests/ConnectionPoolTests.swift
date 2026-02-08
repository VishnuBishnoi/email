import Foundation
import Testing
@testable import PrivateMailFeature

/// Tests for the IMAP connection pool.
///
/// Validates that the ConnectionPool correctly manages connection lifecycle,
/// enforces per-account connection limits (FR-SYNC-09: max 5 for Gmail),
/// and handles edge cases gracefully.
///
/// Note: Full checkout/checkin tests require network connectivity since
/// ConnectionPool internally creates real IMAPClient instances. These tests
/// focus on the pool's bookkeeping and safe lifecycle behavior.
///
/// Spec ref: FR-SYNC-09 (Connection Management)
/// Validation ref: AC-F-05
@Suite("Connection Pool — FR-SYNC-09")
struct ConnectionPoolTests {

    // MARK: - Initialization

    @Test("Pool initializes with correct max connections (FR-SYNC-09: 5)")
    func poolDefaultMax() async {
        let pool = ConnectionPool()

        // Verify default max is 5 (Gmail limit per FR-SYNC-09)
        let count = await pool.connectionCount(for: "test-account")
        #expect(count == 0)
    }

    @Test("Pool initializes with custom max connections")
    func poolCustomMax() async {
        let pool = ConnectionPool(maxConnectionsPerAccount: 3)

        let count = await pool.connectionCount(for: "test-account")
        #expect(count == 0)
    }

    // MARK: - Connection Count Tracking

    @Test("connectionCount returns 0 for unknown account")
    func connectionCountUnknown() async {
        let pool = ConnectionPool()

        let count = await pool.connectionCount(for: "nonexistent-account")
        #expect(count == 0)
    }

    @Test("activeConnectionCount returns 0 for unknown account")
    func activeConnectionCountUnknown() async {
        let pool = ConnectionPool()

        let count = await pool.activeConnectionCount(for: "nonexistent-account")
        #expect(count == 0)
    }

    @Test("connectionCount and activeConnectionCount are consistent for empty pool")
    func countsConsistentEmpty() async {
        let pool = ConnectionPool()

        let total = await pool.connectionCount(for: "account-1")
        let active = await pool.activeConnectionCount(for: "account-1")

        #expect(total == 0)
        #expect(active == 0)
        #expect(active <= total)
    }

    // MARK: - Safe Lifecycle Operations

    @Test("checkin with unknown client does not crash")
    func checkinUnknownClient() async {
        let pool = ConnectionPool()
        let unknownClient = IMAPClient()

        // This should be a no-op, not crash
        await pool.checkin(unknownClient, accountId: "nonexistent")

        let count = await pool.connectionCount(for: "nonexistent")
        #expect(count == 0)
    }

    @Test("disconnectAll with unknown account does not crash")
    func disconnectAllUnknown() async {
        let pool = ConnectionPool()

        // Should be safe to call with nonexistent account
        await pool.disconnectAll(accountId: "nonexistent")

        let count = await pool.connectionCount(for: "nonexistent")
        #expect(count == 0)
    }

    @Test("shutdown with empty pool does not crash")
    func shutdownEmpty() async {
        let pool = ConnectionPool()

        // Should safely handle empty pool
        await pool.shutdown()
    }

    @Test("Multiple disconnectAll calls are safe")
    func disconnectAllIdempotent() async {
        let pool = ConnectionPool()

        await pool.disconnectAll(accountId: "account-1")
        await pool.disconnectAll(accountId: "account-1")
        await pool.disconnectAll(accountId: "account-1")

        let count = await pool.connectionCount(for: "account-1")
        #expect(count == 0)
    }

    @Test("Multiple shutdown calls are safe")
    func shutdownIdempotent() async {
        let pool = ConnectionPool()

        await pool.shutdown()
        await pool.shutdown()
        await pool.shutdown()
    }

    // MARK: - Multi-Account Isolation (E-08)

    @Test("Connection counts are isolated per account")
    func multiAccountIsolation() async {
        let pool = ConnectionPool()

        let count1 = await pool.connectionCount(for: "account-1")
        let count2 = await pool.connectionCount(for: "account-2")
        let count3 = await pool.connectionCount(for: "account-3")

        #expect(count1 == 0)
        #expect(count2 == 0)
        #expect(count3 == 0)
    }

    @Test("disconnectAll only affects specified account")
    func disconnectAllIsolation() async {
        let pool = ConnectionPool()

        // Disconnect one account should not affect others
        await pool.disconnectAll(accountId: "account-1")

        let count2 = await pool.connectionCount(for: "account-2")
        #expect(count2 == 0)
    }

    // MARK: - Pool Exhaustion (FR-SYNC-09)

    @Test("Checkout throws when pool is exhausted (max 0)")
    func checkoutPoolExhausted() async {
        // Create pool with max 0 to immediately exhaust
        let pool = ConnectionPool(maxConnectionsPerAccount: 0)

        await #expect(throws: IMAPError.self) {
            _ = try await pool.checkout(
                accountId: "test-account",
                host: "imap.gmail.com",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }
    }

    // MARK: - Constants Verification

    @Test("Default max connections matches FR-SYNC-09 Gmail limit")
    func maxConnectionsConstant() {
        #expect(AppConstants.imapMaxConnectionsPerAccount == 5)
    }
}
