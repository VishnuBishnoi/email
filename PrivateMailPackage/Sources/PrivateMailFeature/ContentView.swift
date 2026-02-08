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
    let appLockManager: AppLockManager

    @State private var accounts: [Account] = []
    @State private var hasLoaded = false

    public init(manageAccounts: ManageAccountsUseCaseProtocol, appLockManager: AppLockManager) {
        self.manageAccounts = manageAccounts
        self.appLockManager = appLockManager
    }

    public var body: some View {
        ZStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if accounts.isEmpty || !settings.isOnboardingComplete {
                    OnboardingView(manageAccounts: manageAccounts)
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
        }
    }

    // MARK: - Main App View

    @ViewBuilder
    private var mainAppView: some View {
        NavigationStack {
            // TODO: Replace with ThreadListView when thread list is implemented.
            Text("Inbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .navigationTitle("PrivateMail")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        NavigationLink {
                            SettingsView(manageAccounts: manageAccounts)
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
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
