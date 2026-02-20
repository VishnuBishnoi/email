import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let manageAccounts: ManageAccountsUseCaseProtocol
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

    @State private var accounts: [Account] = []
    @State private var isAddingAccount = false
    @State private var showProviderSelection = false
    @State private var showClearCacheConfirmation = false
    @State private var showWipeConfirmation = false
    @State private var estimatedCacheSize: String = "…"
    @State private var errorMessage: String?
    @State private var notificationPermissionDenied = false

    /// Whether multi-provider support is available.
    private var hasMultiProvider: Bool {
        providerDiscovery != nil && connectionTestUseCase != nil
    }

    public init(manageAccounts: ManageAccountsUseCaseProtocol, modelManager: ModelManager = ModelManager(), aiEngineResolver: AIEngineResolver? = nil, providerDiscovery: ProviderDiscovery? = nil, connectionTestUseCase: ConnectionTestUseCaseProtocol? = nil) {
        self.manageAccounts = manageAccounts
        self.modelManager = modelManager
        self.aiEngineResolver = aiEngineResolver
        self.providerDiscovery = providerDiscovery
        self.connectionTestUseCase = connectionTestUseCase
    }

    public var body: some View {
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

            // PRIVACY
            privacySection

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
        .sheet(isPresented: $showProviderSelection) {
            if let discovery = providerDiscovery, let connTest = connectionTestUseCase {
                ProviderSelectionView(
                    manageAccounts: manageAccounts,
                    connectionTestUseCase: connTest,
                    providerDiscovery: discovery,
                    onAccountAdded: { _ in
                        showProviderSelection = false
                        Task { await loadAccounts() }
                    },
                    onCancel: { showProviderSelection = false }
                )
            }
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
                if hasMultiProvider {
                    showProviderSelection = true
                } else {
                    addAccount()
                }
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
                CategoryTabsSettingsView(modelManager: modelManager)
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        Section("AI Features") {
            NavigationLink("AI Model") {
                AIModelSettingsView(modelManager: modelManager, aiEngineResolver: aiEngineResolver)
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            NavigationLink {
                NotificationSettingsView(accounts: accounts)
            } label: {
                Label("Notification Settings", systemImage: "bell.badge")
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
    private var privacySection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Block Remote Images", isOn: $settings.blockRemoteImages)
                .accessibilityLabel("Block remote images")
                .accessibilityHint("When enabled, remote images in emails are blocked until you choose to load them")
                .accessibilityValue(settings.blockRemoteImages ? "On" : "Off")

            Toggle("Block Tracking Pixels", isOn: $settings.blockTrackingPixels)
                .accessibilityLabel("Block tracking pixels")
                .accessibilityHint("When enabled, invisible tracking images are detected and removed from emails")
                .accessibilityValue(settings.blockTrackingPixels ? "On" : "Off")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Blocking remote images prevents senders from knowing when you read an email. Blocking tracking pixels removes invisible tracking images.")
        }
    }

    @ViewBuilder
    private var dataManagementSection: some View {
        Section("Data Management") {
            NavigationLink("Storage Usage") {
                StorageSettingsView(manageAccounts: manageAccounts)
            }

            Button("Clear Cache") {
                Task { await estimateCacheSize() }
                showClearCacheConfirmation = true
            }
            .alert("Clear Cache", isPresented: $showClearCacheConfirmation) {
                Button("Clear (\(estimatedCacheSize))", role: .destructive) { clearCache() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove cached attachments and regenerable data (\(estimatedCacheSize)). Emails and accounts will not be affected.")
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

    /// Estimate cache size using StorageCalculator to show the user how much will be freed.
    /// V1: Returns attachment + search index estimates. Real implementation will use
    /// actual disk size when cache layers exist.
    private func estimateCacheSize() async {
        do {
            let container = modelContext.container
            let calculator = StorageCalculator(modelContainer: container)
            let info = try await calculator.calculateStorage()
            let cacheBytes = info.accounts.reduce(into: Int64(0)) {
                $0 += $1.attachmentCacheSizeBytes + $1.searchIndexSizeBytes
            }
            estimatedCacheSize = cacheBytes.formattedBytes
        } catch {
            estimatedCacheSize = "unknown"
        }
    }

    /// PARTIAL SCOPE — V1 STUB: Clears cached data.
    /// Blocked on attachment download cache (IOS-F-07) and search index (IOS-F-08).
    /// Real implementation MUST:
    /// - Delete downloaded attachment files from disk
    /// - Clear search embeddings / AI category cache
    /// - NOT delete emails, accounts, or AI models
    /// - Report actual bytes freed
    private func clearCache() {
        // V1: No-op — no persistent caches exist yet.
        // When cache layers are built, call their clear methods here.
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
            // Re-check after requesting — update denied state for UX
            await checkNotificationPermission()
        }
        #endif
    }

    /// Check OS notification permission status and update denied-state flag.
    private func checkNotificationPermission() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let currentSettings = await center.notificationSettings()
        notificationPermissionDenied = currentSettings.authorizationStatus == .denied
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
/// If no AI engine is available, toggles are disabled with a note.
///
/// Checks effective engine availability: Foundation Models (iOS 26+),
/// ANY downloaded GGUF model (not just the recommended one).
///
/// Spec ref: FR-SET-01 Appearance section
struct CategoryTabsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    let modelManager: ModelManager

    @State private var isAIAvailable = false

    private let toggleableCategories: [(String, String)] = [
        (AICategory.primary.rawValue, "Primary"),
        (AICategory.social.rawValue, "Social"),
        (AICategory.promotions.rawValue, "Promotions"),
        (AICategory.updates.rawValue, "Updates"),
    ]

    var body: some View {
        @Bindable var settings = settings
        List {
            if !isAIAvailable {
                Section {
                    Label(
                        "Download the AI model to enable smart categories.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(toggleableCategories, id: \.0) { key, label in
                    Toggle(label, isOn: Binding(
                        get: { settings.categoryTabVisibility[key] ?? true },
                        set: { settings.categoryTabVisibility[key] = $0 }
                    ))
                    .disabled(!isAIAvailable)
                }
            }
        }
        .navigationTitle("Category Tabs")
        .task {
            // Check Foundation Models first (iOS 26+ — zero download needed)
            let fmEngine = FoundationModelEngine()
            if await fmEngine.isAvailable() {
                isAIAvailable = true
                return
            }
            // Then check if ANY GGUF model is downloaded (not just the recommended one)
            isAIAvailable = await modelManager.isAnyModelDownloaded()
        }
    }
}

#if canImport(UserNotifications)
import UserNotifications
#endif
