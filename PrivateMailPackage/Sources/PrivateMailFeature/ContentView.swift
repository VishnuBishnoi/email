import SwiftUI
import SwiftData

/// Root content view — routes between onboarding and main app.
///
/// Routing logic: If no accounts exist OR onboarding isn't complete,
/// show onboarding. Otherwise, show the main inbox placeholder with
/// settings access.
///
/// Per plan decision #3: accounts.isEmpty takes precedence over
/// isOnboardingComplete (handles corruption case).
///
/// Presentation approach: Uses root-level view swap (not fullScreenCover)
/// because SwiftUI's conditional rendering is simpler, avoids dismiss
/// coordination issues, and works identically on iOS and macOS.
/// This is an intentional deviation from the plan's fullScreenCover suggestion.
///
/// App lock enforcement (FR-SET-01): When app lock is enabled, returning
/// from background triggers biometric/passcode authentication via
/// AppLockManager. The lock overlay prevents access until authenticated.
///
/// Spec ref: FR-OB-01, FR-SET-01
public struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    let manageAccounts: ManageAccountsUseCaseProtocol
    let fetchThreads: FetchThreadsUseCaseProtocol
    let manageThreadActions: ManageThreadActionsUseCaseProtocol
    let syncEmails: SyncEmailsUseCaseProtocol
    let fetchEmailDetail: FetchEmailDetailUseCaseProtocol
    let markRead: MarkReadUseCaseProtocol
    let downloadAttachment: DownloadAttachmentUseCaseProtocol
    let composeEmail: ComposeEmailUseCaseProtocol
    let queryContacts: QueryContactsUseCaseProtocol
    let idleMonitor: IDLEMonitorUseCaseProtocol?
    let appLockManager: AppLockManager

    @State private var accounts: [Account] = []
    @State private var hasLoaded = false
    @State private var undoSendManager = UndoSendManager()

    public init(
        manageAccounts: ManageAccountsUseCaseProtocol,
        fetchThreads: FetchThreadsUseCaseProtocol,
        manageThreadActions: ManageThreadActionsUseCaseProtocol,
        syncEmails: SyncEmailsUseCaseProtocol,
        fetchEmailDetail: FetchEmailDetailUseCaseProtocol,
        markRead: MarkReadUseCaseProtocol,
        downloadAttachment: DownloadAttachmentUseCaseProtocol,
        composeEmail: ComposeEmailUseCaseProtocol,
        queryContacts: QueryContactsUseCaseProtocol,
        idleMonitor: IDLEMonitorUseCaseProtocol? = nil,
        appLockManager: AppLockManager
    ) {
        self.manageAccounts = manageAccounts
        self.fetchThreads = fetchThreads
        self.manageThreadActions = manageThreadActions
        self.syncEmails = syncEmails
        self.fetchEmailDetail = fetchEmailDetail
        self.markRead = markRead
        self.downloadAttachment = downloadAttachment
        self.composeEmail = composeEmail
        self.queryContacts = queryContacts
        self.idleMonitor = idleMonitor
        self.appLockManager = appLockManager
    }

    public var body: some View {
        ZStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if accounts.isEmpty || !settings.isOnboardingComplete {
                    OnboardingView(manageAccounts: manageAccounts, syncEmails: syncEmails)
                } else {
                    mainAppView
                }
            }

            // App lock overlay (FR-SET-01)
            if appLockManager.isLocked && settings.appLockEnabled {
                appLockOverlay
            }
        }
        .task {
            await loadAccounts()
            hasLoaded = true
            // Lock on cold launch if enabled
            if settings.appLockEnabled {
                appLockManager.lock()
                await authenticateAppLock()
            }
        }
        .onChange(of: settings.isOnboardingComplete) {
            Task { await loadAccounts() }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if settings.appLockEnabled && oldPhase == .background && newPhase == .active {
                appLockManager.lock()
                Task { await authenticateAppLock() }
            }
            // Undo-send timer pause/resume (FR-COMP-02)
            if newPhase == .background {
                undoSendManager.pause()
            } else if oldPhase == .background && newPhase == .active {
                undoSendManager.resume()
            }
        }
    }

    // MARK: - Main App View

    @ViewBuilder
    private var mainAppView: some View {
        ThreadListView(
            fetchThreads: fetchThreads,
            manageThreadActions: manageThreadActions,
            manageAccounts: manageAccounts,
            syncEmails: syncEmails,
            fetchEmailDetail: fetchEmailDetail,
            markRead: markRead,
            downloadAttachment: downloadAttachment,
            composeEmail: composeEmail,
            queryContacts: queryContacts,
            idleMonitor: idleMonitor
        )
        .environment(undoSendManager)
        .preferredColorScheme(settings.colorScheme)
    }

    // MARK: - App Lock

    @ViewBuilder
    private var appLockOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("PrivateMail is Locked")
                    .font(.title2.bold())
                Button("Unlock") {
                    Task { await authenticateAppLock() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App is locked. Tap unlock to authenticate.")
    }

    private func authenticateAppLock() async {
        let success = await appLockManager.authenticate()
        if !success {
            // Stay locked — user can tap Unlock to retry
        }
    }

    // MARK: - Actions

    private func loadAccounts() async {
        do {
            accounts = try await manageAccounts.getAccounts()
        } catch {
            accounts = []
        }
    }
}
