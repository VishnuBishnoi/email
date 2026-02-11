import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Schedules periodic background email sync using iOS BGAppRefreshTask.
///
/// Registers a background task that performs incremental IMAP sync within
/// iOS's 30-second execution budget. The sync is headers-only (no bodies)
/// to stay within the time limit.
///
/// On macOS, background sync is not scheduled (macOS apps can run in
/// the background natively). IDLE monitoring handles real-time updates.
///
/// Spec ref: FR-SYNC-03 (Background refresh)
@Observable @MainActor
public final class BackgroundSyncScheduler {

    /// Background task identifier — must match Info.plist entry.
    public static let taskIdentifier = "com.vaultmail.app.sync"

    /// Minimum interval between background syncs (15 minutes).
    private static let minimumInterval: TimeInterval = 15 * 60

    private let syncEmails: SyncEmailsUseCaseProtocol
    private let manageAccounts: ManageAccountsUseCaseProtocol

    public init(
        syncEmails: SyncEmailsUseCaseProtocol,
        manageAccounts: ManageAccountsUseCaseProtocol
    ) {
        self.syncEmails = syncEmails
        self.manageAccounts = manageAccounts
    }

    // MARK: - Registration

    /// Registers the background task with the system.
    ///
    /// Must be called from `App.init()` BEFORE the app finishes launching.
    /// On macOS this is a no-op.
    public func registerTasks() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await self.handleBackgroundSync(task: appRefreshTask)
            }
        }
        NSLog("[BackgroundSync] Registered task: \(Self.taskIdentifier)")
        #endif
    }

    // MARK: - Scheduling

    /// Schedules the next background sync.
    ///
    /// Should be called after each foreground sync completion and after
    /// each background sync completion.
    public func scheduleNextSync() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(Self.minimumInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BackgroundSync] Scheduled next sync in \(Int(Self.minimumInterval / 60)) minutes")
        } catch {
            NSLog("[BackgroundSync] Failed to schedule: \(error)")
        }
        #endif
    }

    // MARK: - Execution

    #if os(iOS)
    /// Handles a background sync task within the ~30-second budget.
    ///
    /// Performs incremental sync for all active accounts. The sync engine
    /// uses UID-based incremental fetch which is fast enough for background.
    private func handleBackgroundSync(task: BGAppRefreshTask) async {
        // Schedule the next sync before this one finishes
        scheduleNextSync()

        // Set up expiration handler
        let syncTask = Task { @MainActor in
            do {
                let accounts = try await manageAccounts.getAccounts()
                let activeAccounts = accounts.filter { $0.isActive }

                for account in activeAccounts {
                    guard !Task.isCancelled else { break }
                    try await syncEmails.syncAccount(accountId: account.id)
                    NSLog("[BackgroundSync] Synced account: \(account.email)")
                }

                if Task.isCancelled {
                    NSLog("[BackgroundSync] Cancelled before completing all accounts")
                    task.setTaskCompleted(success: false)
                } else {
                    task.setTaskCompleted(success: true)
                }
            } catch {
                NSLog("[BackgroundSync] Failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // If iOS kills the task (budget exceeded), cancel gracefully
        task.expirationHandler = {
            syncTask.cancel()
            NSLog("[BackgroundSync] Expired — cancelled sync task")
        }

        await syncTask.value
    }
    #endif
}
