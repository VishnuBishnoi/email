import Foundation
import Testing
@testable import VaultMailFeature

@Suite("BackgroundSyncScheduler Tests")
@MainActor
struct BackgroundSyncSchedulerTests {

    // MARK: - Mock SyncEmails

    /// Lightweight mock of SyncEmailsUseCaseProtocol for testing BackgroundSyncScheduler.
    private final class MockSyncEmails: SyncEmailsUseCaseProtocol, @unchecked Sendable {
        var syncAccountCallCount = 0
        var syncFolderCallCount = 0
        var lastSyncedAccountId: String?
        var shouldThrow = false

        @discardableResult
        func syncAccount(accountId: String) async throws -> [Email] {
            syncAccountCallCount += 1
            lastSyncedAccountId = accountId
            if shouldThrow {
                throw AccountError.notFound(accountId)
            }
            return []
        }

        @discardableResult
        func syncAccountInboxFirst(
            accountId: String,
            onInboxSynced: @MainActor (_ inboxEmails: [Email]) async -> Void
        ) async throws -> [Email] {
            // Delegates to syncAccount for tests — inbox-first is a UI optimization
            try await syncAccount(accountId: accountId)
        }

        @discardableResult
        func syncFolder(accountId: String, folderId: String) async throws -> [Email] {
            syncFolderCallCount += 1
            if shouldThrow {
                throw AccountError.notFound(accountId)
            }
            return []
        }
    }

    // MARK: - Mock ManageAccounts

    /// Lightweight mock that returns configurable accounts for the scheduler.
    private final class MockManageAccounts: ManageAccountsUseCaseProtocol, @unchecked Sendable {
        var accounts: [Account] = []
        var getAccountsCallCount = 0

        func addAccountViaOAuth() async throws -> Account {
            fatalError("Not used in scheduler tests")
        }

        func removeAccount(id: String) async throws -> Bool {
            fatalError("Not used in scheduler tests")
        }

        func getAccounts() async throws -> [Account] {
            getAccountsCallCount += 1
            return accounts
        }

        func updateAccount(_ account: Account) async throws {
            fatalError("Not used in scheduler tests")
        }

        func reAuthenticateAccount(id: String) async throws {
            fatalError("Not used in scheduler tests")
        }
    }

    // MARK: - Tests

    @Test("Task identifier matches Info.plist value")
    func taskIdentifier() {
        #expect(BackgroundSyncScheduler.taskIdentifier == "com.vaultmail.app.sync")
    }

    @Test("Scheduler initializes with provided dependencies")
    func initialization() {
        let syncEmails = MockSyncEmails()
        let manageAccounts = MockManageAccounts()

        let scheduler = BackgroundSyncScheduler(
            syncEmails: syncEmails,
            manageAccounts: manageAccounts
        )

        // Scheduler should be created without errors
        _ = scheduler
    }

    @Test("registerTasks completes without error")
    func registerTasks() {
        let syncEmails = MockSyncEmails()
        let manageAccounts = MockManageAccounts()

        let scheduler = BackgroundSyncScheduler(
            syncEmails: syncEmails,
            manageAccounts: manageAccounts
        )

        // On macOS this is a no-op, on iOS it registers with BGTaskScheduler.
        // Either way, it should not throw.
        scheduler.registerTasks()
    }

    @Test("scheduleNextSync completes without error")
    func scheduleNextSync() {
        let syncEmails = MockSyncEmails()
        let manageAccounts = MockManageAccounts()

        let scheduler = BackgroundSyncScheduler(
            syncEmails: syncEmails,
            manageAccounts: manageAccounts
        )

        // On macOS this is a no-op, on iOS it submits a BGAppRefreshTaskRequest.
        // Should not throw or crash.
        scheduler.scheduleNextSync()
    }
}
