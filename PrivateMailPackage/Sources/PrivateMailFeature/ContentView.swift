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
/// Spec ref: FR-OB-01, FR-SET-01
public struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    let manageAccounts: ManageAccountsUseCaseProtocol

    @State private var accounts: [Account] = []
    @State private var hasLoaded = false

    public init(manageAccounts: ManageAccountsUseCaseProtocol) {
        self.manageAccounts = manageAccounts
    }

    public var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
            } else if accounts.isEmpty || !settings.isOnboardingComplete {
                OnboardingView(manageAccounts: manageAccounts)
            } else {
                mainAppView
            }
        }
        .task {
            await loadAccounts()
            hasLoaded = true
        }
        .onChange(of: settings.isOnboardingComplete) {
            Task { await loadAccounts() }
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

    // MARK: - Actions

    private func loadAccounts() async {
        do {
            accounts = try await manageAccounts.getAccounts()
        } catch {
            accounts = []
        }
    }
}
