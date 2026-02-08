import SwiftUI

/// Main settings screen with all V1 sections.
///
/// iOS: NavigationStack with .listStyle(.insetGrouped)
/// macOS: Wrapped in Settings scene, opened via ⌘,
///
/// Sections: Accounts, Composition, Appearance, AI Features,
/// Notifications, Security, Data Management, About.
///
/// Spec ref: FR-SET-01, FR-SET-02, FR-SET-03, FR-SET-04, FR-SET-05
public struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let manageAccounts: ManageAccountsUseCaseProtocol

    @State private var accounts: [Account] = []
    @State private var isAddingAccount = false
    @State private var showClearCacheConfirmation = false
    @State private var showWipeConfirmation = false
    @State private var errorMessage: String?

    public init(manageAccounts: ManageAccountsUseCaseProtocol) {
        self.manageAccounts = manageAccounts
    }

    public var body: some View {
        NavigationStack {
            List {
                // ACCOUNTS (FR-SET-02)
                accountsSection

                // COMPOSITION (FR-SET-01)
                compositionSection

                // APPEARANCE (FR-SET-01)
                appearanceSection

                // AI FEATURES (FR-SET-04)
                aiSection

                // NOTIFICATIONS (FR-SET-01)
                notificationsSection

                // SECURITY (FR-SET-01)
                securitySection

                // DATA MANAGEMENT (FR-SET-03)
                dataManagementSection

                // ABOUT (FR-SET-05)
                aboutSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Settings")
            .task { await loadAccounts() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountsSection: some View {
        Section("Accounts") {
            ForEach(accounts, id: \.id) { account in
                NavigationLink {
                    AccountSettingsView(
                        account: account,
                        manageAccounts: manageAccounts,
                        onAccountRemoved: { wasLast in
                            if wasLast {
                                settings.isOnboardingComplete = false
                            }
                            Task { await loadAccounts() }
                        }
                    )
                } label: {
                    AccountRowView(account: account)
                }
            }

            Button {
                addAccount()
            } label: {
                Label("Add Account", systemImage: "plus.circle")
            }
            .disabled(isAddingAccount)
        }
    }

    @ViewBuilder
    private var compositionSection: some View {
        @Bindable var settings = settings
        Section("Composition") {
            // Default account picker — hidden if only one account (FR-SET-01)
            if accounts.count > 1 {
                Picker("Default Account", selection: $settings.defaultSendingAccountId) {
                    ForEach(accounts.filter(\.isActive), id: \.id) { account in
                        Text(account.email).tag(Optional(account.id))
                    }
                }
                .accessibilityLabel("Default sending account")
            }

            // Undo send delay picker (FR-SET-01, FR-COMP-02)
            Picker("Undo Send Delay", selection: $settings.undoSendDelay) {
                ForEach(UndoSendDelay.allCases, id: \.self) { delay in
                    Text(delay.displayLabel).tag(delay)
                }
            }
            .accessibilityLabel("Undo send delay")
            .accessibilityValue(settings.undoSendDelay.displayLabel)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var settings = settings
        Section("Appearance") {
            // Theme picker (FR-SET-01)
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.displayLabel).tag(theme)
                }
            }
            .accessibilityLabel("App theme")
            .accessibilityValue(settings.theme.displayLabel)

            // Category tab toggles (FR-SET-01, Thread List FR-TL-02)
            NavigationLink("Category Tabs") {
                CategoryTabsSettingsView()
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        Section("AI Features") {
            NavigationLink("AI Model") {
                AIModelSettingsView()
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            ForEach(accounts, id: \.id) { account in
                NotificationToggleRow(
                    account: account,
                    isEnabled: settings.notificationsEnabled(for: account.id)
                ) { enabled in
                    settings.notificationPreferences[account.id] = enabled
                    if enabled {
                        requestNotificationPermissionIfNeeded()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        @Bindable var settings = settings
        Section("Security") {
            Toggle("App Lock", isOn: $settings.appLockEnabled)
                .accessibilityLabel("App lock")
                .accessibilityHint("Requires Face ID, Touch ID, or device passcode to open the app")
                .accessibilityValue(settings.appLockEnabled ? "On" : "Off")
        }
    }

    @ViewBuilder
    private var dataManagementSection: some View {
        Section("Data Management") {
            NavigationLink("Storage Usage") {
                StorageSettingsView(manageAccounts: manageAccounts)
            }

            Button("Clear Cache") {
                showClearCacheConfirmation = true
            }
            .alert("Clear Cache", isPresented: $showClearCacheConfirmation) {
                Button("Clear", role: .destructive) { clearCache() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove cached attachments and data. Emails and accounts will not be affected.")
            }

            Button("Wipe All Data", role: .destructive) {
                showWipeConfirmation = true
            }
            .alert("Wipe All Data", isPresented: $showWipeConfirmation) {
                Button("Delete Everything", role: .destructive) { wipeAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete ALL local data including emails, accounts, and AI models. This cannot be undone. You will need to set up the app again.")
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            NavigationLink("About") {
                AboutView()
            }
        }
    }

    // MARK: - Actions

    private func loadAccounts() async {
        do {
            accounts = try await manageAccounts.getAccounts()
        } catch {
            errorMessage = "Failed to load accounts."
        }
    }

    private func addAccount() {
        isAddingAccount = true
        Task {
            defer { isAddingAccount = false }
            do {
                _ = try await manageAccounts.addAccountViaOAuth()
                await loadAccounts()
            } catch {
                // OAuth cancelled or failed — handled silently
            }
        }
    }

    private func clearCache() {
        // TODO: Implement cache clearing when attachment/search cache layers are built.
        // Should remove downloaded attachments and regenerable caches
        // (search embeddings, AI category cache) without deleting emails/accounts/AI models.
    }

    private func wipeAllData() {
        // Remove all accounts
        Task {
            for account in accounts {
                _ = try? await manageAccounts.removeAccount(id: account.id)
            }
            // Reset all settings (UserDefaults)
            settings.resetAll()
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        // Request notification permission when user first enables a toggle
        #if canImport(UserNotifications)
        Task {
            let center = UNUserNotificationCenter.current()
            let currentSettings = await center.notificationSettings()
            if currentSettings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            }
        }
        #endif
    }
}

// MARK: - Account Row

/// Displays an account in the accounts list with active/inactive status.
struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.body)
                if !account.isActive {
                    Label("Re-authenticate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if !account.isActive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true) // Announced via label above
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.isActive
            ? account.email
            : "\(account.email), inactive, re-authentication required")
    }
}

// MARK: - Notification Toggle Row

/// Per-account notification toggle with denied-state handling.
struct NotificationToggleRow: View {
    let account: Account
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(account.email, isOn: Binding(
            get: { isEnabled },
            set: { onToggle($0) }
        ))
        .accessibilityLabel("Notifications for \(account.email)")
        .accessibilityValue(isEnabled ? "On" : "Off")
    }
}

// MARK: - Category Tabs Settings

/// Category tab visibility toggles.
/// If AI model is not downloaded, toggles are disabled with a note.
///
/// Spec ref: FR-SET-01 Appearance section
struct CategoryTabsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private let toggleableCategories: [(String, String)] = [
        (AICategory.primary.rawValue, "Primary"),
        (AICategory.social.rawValue, "Social"),
        (AICategory.promotions.rawValue, "Promotions"),
        (AICategory.updates.rawValue, "Updates"),
    ]

    var body: some View {
        @Bindable var settings = settings
        List {
            // TODO: Check AI model availability when Data/AI/ is implemented.
            // For now, always show toggles as enabled.
            ForEach(toggleableCategories, id: \.0) { key, label in
                Toggle(label, isOn: Binding(
                    get: { settings.categoryTabVisibility[key] ?? true },
                    set: { settings.categoryTabVisibility[key] = $0 }
                ))
            }
        }
        .navigationTitle("Category Tabs")
    }
}

#if canImport(UserNotifications)
import UserNotifications
#endif
