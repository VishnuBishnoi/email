#if os(macOS)
import SwiftUI
import SwiftData

/// Native macOS settings window using TabView for a System Settings–like appearance.
///
/// Each tab corresponds to a settings section: Accounts, Composition,
/// Appearance, AI Features, Notifications, Security, Data, About.
///
/// Replaces the iOS-style SettingsView when running on macOS.
///
/// Spec ref: FR-SET-01, FR-SET-02, FR-SET-03, FR-SET-04, FR-SET-05, FR-MAC-08
@MainActor
public struct MacSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.modelContext) private var modelContext

    let manageAccounts: ManageAccountsUseCaseProtocol
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

    @State private var accounts: [Account] = []

    /// Whether multi-provider support is available.
    private var hasMultiProvider: Bool {
        providerDiscovery != nil && connectionTestUseCase != nil
    }

    public init(
        manageAccounts: ManageAccountsUseCaseProtocol,
        modelManager: ModelManager = ModelManager(),
        aiEngineResolver: AIEngineResolver? = nil,
        providerDiscovery: ProviderDiscovery? = nil,
        connectionTestUseCase: ConnectionTestUseCaseProtocol? = nil
    ) {
        self.manageAccounts = manageAccounts
        self.modelManager = modelManager
        self.aiEngineResolver = aiEngineResolver
        self.providerDiscovery = providerDiscovery
        self.connectionTestUseCase = connectionTestUseCase
    }

    public var body: some View {
        TabView {
            // Accounts Tab
            MacAccountsSettingsTab(
                accounts: $accounts,
                manageAccounts: manageAccounts,
                providerDiscovery: providerDiscovery,
                connectionTestUseCase: connectionTestUseCase
            )
            .tabItem {
                Label("Accounts", systemImage: "person.crop.circle")
            }

            // General Tab (Composition + Appearance)
            MacGeneralSettingsTab(accounts: accounts, modelManager: modelManager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            // AI Features Tab
            MacAISettingsTab(modelManager: modelManager, aiEngineResolver: aiEngineResolver)
                .tabItem {
                    Label("AI Features", systemImage: "brain")
                }

            // Notifications Tab
            NotificationSettingsContent(accounts: accounts)
                .tabItem {
                    Label("Notifications", systemImage: "bell.badge")
                }

            // Security Tab
            MacSecuritySettingsTab()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }

            // Storage Tab
            MacStorageSettingsTab(
                manageAccounts: manageAccounts,
                accounts: accounts
            )
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }

            // About Tab
            MacAboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 420)
        .task { await loadAccounts() }
    }

    private func loadAccounts() async {
        do {
            accounts = try await manageAccounts.getAccounts()
        } catch {
            // Silently handle
        }
    }
}

// MARK: - Accounts Tab

/// Accounts settings tab with inline account management.
///
/// Lists all accounts with expand/collapse details, add account button,
/// and remove account with confirmation — all within the tab (no navigation push).
struct MacAccountsSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Binding var accounts: [Account]
    let manageAccounts: ManageAccountsUseCaseProtocol
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

    @State private var selectedAccountID: String?
    @State private var isAddingAccount = false
    @State private var showRemoveConfirmation = false
    @State private var accountToRemove: Account?
    @State private var showProviderSelection = false

    /// Whether multi-provider support is available.
    private var hasMultiProvider: Bool {
        providerDiscovery != nil && connectionTestUseCase != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Account list with detail on selection
            HSplitView {
                // Left: account list
                List(selection: $selectedAccountID) {
                    ForEach(accounts, id: \.id) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                                Text(account.email)
                                    .font(theme.typography.bodyLarge)
                                    .lineLimit(1)
                                if !account.isActive {
                                    Text("Needs Re-authentication")
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.warning)
                                }
                            }
                            Spacer()
                            if !account.isActive {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(theme.colors.warning)
                                    .font(theme.typography.caption)
                            }
                        }
                        .tag(account.id)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minWidth: 180, maxWidth: 220)

                // Right: account detail or placeholder
                if let selectedID = selectedAccountID,
                   let account = accounts.first(where: { $0.id == selectedID }) {
                    MacAccountDetailView(
                        account: account,
                        manageAccounts: manageAccounts,
                        onRemove: {
                            accountToRemove = account
                            showRemoveConfirmation = true
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Spacer()
                        Text("Select an account to view settings")
                            .foregroundStyle(theme.colors.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Bottom bar with add/remove buttons
            HStack {
                Button {
                    if hasMultiProvider {
                        showProviderSelection = true
                    } else {
                        addAccount()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isAddingAccount)
                .help("Add Account")

                Button {
                    if let selectedID = selectedAccountID,
                       let account = accounts.first(where: { $0.id == selectedID }) {
                        accountToRemove = account
                        showRemoveConfirmation = true
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedAccountID == nil)
                .help("Remove Account")

                Spacer()
            }
            .padding(theme.spacing.sm)
            .background(.bar)
        }
        .alert("Remove Account", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
        } message: {
            if let account = accountToRemove {
                Text("Remove \(account.email)? All local emails, drafts, and cached data for this account will be deleted.")
            }
        }
        .sheet(isPresented: $showProviderSelection) {
            if let discovery = providerDiscovery, let connTest = connectionTestUseCase {
                MacAddAccountView(
                    manageAccounts: manageAccounts,
                    connectionTestUseCase: connTest,
                    providerDiscovery: discovery,
                    onAccountAdded: { _ in
                        showProviderSelection = false
                        Task { await loadAccounts() }
                        NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
                    },
                    onCancel: { showProviderSelection = false }
                )
            }
        }
        .task { await loadAccounts() }
    }

    private func loadAccounts() async {
        do {
            accounts = try await manageAccounts.getAccounts()
            if selectedAccountID == nil, let first = accounts.first {
                selectedAccountID = first.id
            }
        } catch {
            // Silently handle
        }
    }

    private func addAccount() {
        isAddingAccount = true
        Task {
            defer { isAddingAccount = false }
            do {
                _ = try await manageAccounts.addAccountViaOAuth()
                await loadAccounts()
                // Notify the main window to refresh its account list
                NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
            } catch {
                // OAuth cancelled or failed
            }
        }
    }

    private func removeAccount(_ account: Account) {
        Task {
            do {
                let wasLast = try await manageAccounts.removeAccount(id: account.id)
                if wasLast {
                    settings.isOnboardingComplete = false
                }
                accountToRemove = nil
                selectedAccountID = nil
                await loadAccounts()
                // Notify the main window to refresh its account list
                NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
            } catch {
                // Handle error silently
            }
        }
    }
}

// MARK: - Account Detail (inline, no navigation)

/// Inline detail view for a selected account in the Accounts tab.
struct MacAccountDetailView: View {
    let account: Account
    let manageAccounts: ManageAccountsUseCaseProtocol
    let onRemove: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme

    @State private var displayName: String = ""
    @State private var syncWindowDays: Int = 30
    @State private var cacheLimit: Int = 500
    @State private var isReAuthenticating = false
    @State private var showPasswordUpdate = false
    @State private var newAppPassword = ""
    @State private var reAuthError: String?
    @State private var showSyncWindowConfirmation = false
    @State private var pendingSyncWindow: Int?

    var body: some View {
        Form {
            // Account Info
            Section {
                LabeledContent("Email", value: account.email)
                if let provider = account.provider {
                    LabeledContent("Provider", value: provider.capitalized)
                }
                if let authType = account.authType == "plain" ? "App Password" : account.authType == "xoauth2" ? "OAuth" : nil {
                    LabeledContent("Authentication", value: authType)
                }
                if !account.isActive {
                    HStack {
                        Label("Account Inactive", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.warning)
                        Spacer()
                        Button("Re-authenticate") {
                            reAuthenticate()
                        }
                        .disabled(isReAuthenticating)
                    }
                }
                if let error = reAuthError {
                    Label(error, systemImage: "xmark.circle")
                        .foregroundStyle(theme.colors.destructive)
                        .font(theme.typography.bodyMedium)
                }
                // Manual app-password update for PLAIN-auth accounts
                if account.authType == "plain" && account.isActive {
                    Button("Update App Password…") {
                        showPasswordUpdate = true
                    }
                }
            }

            // Display Name
            Section("Display Name") {
                TextField("Display Name", text: $displayName)
                    .onSubmit { saveDisplayName() }
            }

            // Sync Settings
            Section("Sync") {
                Picker("Sync Window", selection: Binding(
                    get: { syncWindowDays },
                    set: { newValue in
                        if newValue < syncWindowDays {
                            pendingSyncWindow = newValue
                            showSyncWindowConfirmation = true
                        } else {
                            syncWindowDays = newValue
                            saveSyncWindow()
                        }
                    }
                )) {
                    ForEach(AppConstants.syncWindowOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            }

            // Cache
            Section("Cache") {
                Picker("Attachment Cache Limit", selection: $cacheLimit) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1000 MB").tag(1000)
                }
                .onChange(of: cacheLimit) { _, newValue in
                    settings.setCacheLimit(newValue, for: account.id)
                }
            }

            // Remove
            Section {
                Button("Remove Account…", role: .destructive) {
                    onRemove()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            displayName = account.displayName
            syncWindowDays = account.syncWindowDays
            cacheLimit = settings.cacheLimit(for: account.id)
        }
        .onChange(of: account.id) {
            displayName = account.displayName
            syncWindowDays = account.syncWindowDays
            cacheLimit = settings.cacheLimit(for: account.id)
        }
        .alert("Reduce Sync Window", isPresented: $showSyncWindowConfirmation) {
            Button("Reduce") {
                if let pending = pendingSyncWindow {
                    syncWindowDays = pending
                    saveSyncWindow()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSyncWindow = nil
            }
        } message: {
            Text("Reducing the sync window will remove local copies of older emails. Server emails are not affected.")
        }
        .alert("Update App Password", isPresented: $showPasswordUpdate) {
            SecureField("New App Password", text: $newAppPassword)
            Button("Update") {
                updatePassword()
            }
            Button("Cancel", role: .cancel) {
                newAppPassword = ""
            }
        } message: {
            Text("Enter the new app password for \(account.email).")
        }
    }

    private func saveSyncWindow() {
        account.syncWindowDays = syncWindowDays
        Task { try? await manageAccounts.updateAccount(account) }
    }

    private func saveDisplayName() {
        account.displayName = displayName
        Task { try? await manageAccounts.updateAccount(account) }
    }

    private func reAuthenticate() {
        isReAuthenticating = true
        reAuthError = nil
        Task {
            defer { isReAuthenticating = false }
            do {
                try await manageAccounts.reAuthenticateAccount(id: account.id)
            } catch let accountError as AccountError {
                if case .appPasswordReAuthRequired = accountError {
                    showPasswordUpdate = true
                } else {
                    reAuthError = accountError.localizedDescription
                }
            } catch {
                reAuthError = error.localizedDescription
            }
        }
    }

    private func updatePassword() {
        guard !newAppPassword.isEmpty else { return }
        isReAuthenticating = true
        reAuthError = nil
        Task {
            defer {
                isReAuthenticating = false
                newAppPassword = ""
            }
            do {
                try await manageAccounts.updateAppPassword(for: account.id, newPassword: newAppPassword)
            } catch {
                reAuthError = error.localizedDescription
            }
        }
    }
}

// MARK: - General Tab (Composition + Appearance)

struct MacGeneralSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    let accounts: [Account]
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
        Form {
            // Composition
            Section("Composition") {
                if accounts.count > 1 {
                    Picker("Default Account", selection: $settings.defaultSendingAccountId) {
                        ForEach(accounts.filter(\.isActive), id: \.id) { account in
                            Text(account.email).tag(Optional(account.id))
                        }
                    }
                }

                Picker("Undo Send Delay", selection: $settings.undoSendDelay) {
                    ForEach(UndoSendDelay.allCases, id: \.self) { delay in
                        Text(delay.displayLabel).tag(delay)
                    }
                }
            }

            // Appearance
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { appTheme in
                        Text(appTheme.displayLabel).tag(appTheme)
                    }
                }

                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    Text("Color Theme")
                        .font(theme.typography.labelMedium)
                        .foregroundStyle(theme.colors.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: theme.spacing.lg)], spacing: theme.spacing.lg) {
                        ForEach(ThemeRegistry.allThemes, id: \.id) { availableTheme in
                            ThemePickerCell(
                                theme: availableTheme,
                                isSelected: settings.selectedThemeId == availableTheme.id,
                                onSelect: {
                                    settings.selectedThemeId = availableTheme.id
                                    theme.apply(availableTheme.id)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, theme.spacing.xs)
            }

            // Category Tabs
            Section("Category Tabs") {
                if !isAIAvailable {
                    Label(
                        "Download the AI model to enable smart categories.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
                }

                ForEach(toggleableCategories, id: \.0) { key, label in
                    Toggle(label, isOn: Binding(
                        get: { settings.categoryTabVisibility[key] ?? true },
                        set: { settings.categoryTabVisibility[key] = $0 }
                    ))
                    .disabled(!isAIAvailable)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let fmEngine = FoundationModelEngine()
            if await fmEngine.isAvailable() {
                isAIAvailable = true
                return
            }
            isAIAvailable = await modelManager.isAnyModelDownloaded()
        }
    }
}

// MARK: - AI Features Tab

struct MacAISettingsTab: View {
    @Environment(ThemeProvider.self) private var theme
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?

    @State private var models: [ModelManager.ModelState] = []
    @State private var downloadingModelID: String?
    @State private var downloadProgress: Double = 0
    @State private var storageUsage: UInt64 = 0
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: String?

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("AI Models", value: formattedStorageUsage)
            }

            ForEach(models) { model in
                Section(model.info.name) {
                    LabeledContent("Size", value: model.info.formattedSize)
                    LabeledContent("License", value: model.info.license)
                    LabeledContent("Source", value: model.info.downloadURL.host ?? "Unknown")
                    LabeledContent("Min RAM", value: "\(model.info.minRAMGB) GB")

                    modelActionView(for: model)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadModels() }
    }

    @ViewBuilder
    private func modelActionView(for model: ModelManager.ModelState) -> some View {
        switch model.status {
        case .notDownloaded:
            if downloadingModelID == model.id {
                downloadProgressView
            } else {
                Button("Download") {
                    startDownload(modelID: model.id)
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ProgressView(value: progress)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        cancelDownload(modelID: model.id)
                    }
                    .font(theme.typography.caption)
                }
            }

        case .verifying:
            HStack {
                ProgressView().controlSize(.small)
                Text("Verifying integrity…")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
            }

        case .downloaded:
            Button("Delete", role: .destructive) {
                modelToDelete = model.id
                showDeleteConfirmation = true
            }
            .alert("Delete \(model.info.name)?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let id = modelToDelete { deleteModel(modelID: id) }
                }
                Button("Cancel", role: .cancel) { modelToDelete = nil }
            } message: {
                Text("Deleting this model will disable AI features that require it. You can re-download it later.")
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.destructive)
                    .font(theme.typography.bodyMedium)
                Button("Retry") {
                    startDownload(modelID: model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ProgressView(value: downloadProgress)
            HStack {
                Text("Downloading… \(Int(downloadProgress * 100))%")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    if let id = downloadingModelID { cancelDownload(modelID: id) }
                }
                .font(theme.typography.caption)
            }
        }
    }

    private var formattedStorageUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(storageUsage), countStyle: .file)
    }

    private func loadModels() async {
        models = await modelManager.availableModels()
        storageUsage = await modelManager.storageUsage()
    }

    private func startDownload(modelID: String) {
        downloadingModelID = modelID
        downloadProgress = 0
        Task {
            do {
                try await modelManager.downloadModel(id: modelID) { progress in
                    Task { @MainActor in self.downloadProgress = progress }
                }
                downloadingModelID = nil
                await aiEngineResolver?.invalidateCache()
                await loadModels()
            } catch {
                downloadingModelID = nil
                await loadModels()
            }
        }
    }

    private func cancelDownload(modelID: String) {
        Task {
            await modelManager.cancelDownload(id: modelID)
            downloadingModelID = nil
            await loadModels()
        }
    }

    private func deleteModel(modelID: String) {
        Task {
            try? await modelManager.deleteModel(id: modelID)
            modelToDelete = nil
            await aiEngineResolver?.invalidateCache()
            await loadModels()
        }
    }
}

// MARK: - Notifications Tab

struct MacNotificationsSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    let accounts: [Account]

    @State private var notificationPermissionDenied = false

    var body: some View {
        Form {
            Section("Per-Account Notifications") {
                if accounts.isEmpty {
                    Text("No accounts configured.")
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    ForEach(accounts, id: \.id) { account in
                        Toggle(account.email, isOn: Binding(
                            get: { settings.notificationsEnabled(for: account.id) },
                            set: { enabled in
                                settings.notificationPreferences[account.id] = enabled
                                if enabled { requestNotificationPermissionIfNeeded() }
                            }
                        ))
                    }
                }
            }

            if notificationPermissionDenied {
                Section {
                    Label("Notifications are disabled in system Settings.", systemImage: "bell.slash")
                        .foregroundStyle(theme.colors.warning)
                    Text("Enable notifications in System Settings → Notifications.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await checkNotificationPermission() }
    }

    private func requestNotificationPermissionIfNeeded() {
        #if canImport(UserNotifications)
        Task {
            let center = UNUserNotificationCenter.current()
            let currentSettings = await center.notificationSettings()
            if currentSettings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            }
            await checkNotificationPermission()
        }
        #endif
    }

    private func checkNotificationPermission() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let currentSettings = await center.notificationSettings()
        notificationPermissionDenied = currentSettings.authorizationStatus == .denied
        #endif
    }
}

// MARK: - Security Tab

struct MacSecuritySettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("App Lock") {
                Toggle("Require authentication to open VaultMail", isOn: $settings.appLockEnabled)
                Text("Uses Touch ID or your system password to protect access to VaultMail.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Section("Privacy") {
                Toggle("Block Remote Images", isOn: $settings.blockRemoteImages)
                Text("Prevents senders from knowing when you read an email.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                Toggle("Block Tracking Pixels", isOn: $settings.blockTrackingPixels)
                Text("Removes invisible tracking images from emails.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage Tab

struct MacStorageSettingsTab: View {
    let manageAccounts: ManageAccountsUseCaseProtocol
    let accounts: [Account]

    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var storageInfo: AppStorageInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showClearCacheConfirmation = false
    @State private var showWipeConfirmation = false
    @State private var estimatedCacheSize: String = "…"

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Calculating storage…")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.colors.destructive)
                    Button("Retry") {
                        Task { await loadStorage() }
                    }
                }
            } else if let info = storageInfo {
                Section("Total") {
                    LabeledContent("Total Storage", value: info.totalBytes.formattedBytes)
                    if info.aiModelSizeBytes > 0 {
                        LabeledContent("AI Model", value: info.aiModelSizeBytes.formattedBytes)
                    }
                    if info.exceedsWarningThreshold {
                        Label("Total storage exceeds 5 GB", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.warning)
                            .font(theme.typography.bodyMedium)
                    }
                }

                ForEach(info.accounts) { accountInfo in
                    Section(accountInfo.email) {
                        LabeledContent("Emails (\(accountInfo.emailCount))", value: accountInfo.estimatedEmailSizeBytes.formattedBytes)
                        LabeledContent("Attachments", value: accountInfo.attachmentCacheSizeBytes.formattedBytes)
                        LabeledContent("Search Index", value: accountInfo.searchIndexSizeBytes.formattedBytes)
                        LabeledContent("Total", value: accountInfo.totalBytes.formattedBytes)
                            .fontWeight(.medium)
                        if accountInfo.exceedsWarningThreshold {
                            Label("Account storage exceeds 2 GB", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.colors.warning)
                                .font(theme.typography.bodyMedium)
                        }
                    }
                }
            }

            Section("Actions") {
                Button("Clear Cache…") {
                    Task { await estimateCacheSizeValue() }
                    showClearCacheConfirmation = true
                }
                .alert("Clear Cache", isPresented: $showClearCacheConfirmation) {
                    Button("Clear (\(estimatedCacheSize))", role: .destructive) { }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove cached attachments and regenerable data (\(estimatedCacheSize)). Emails and accounts will not be affected.")
                }

                Button("Wipe All Data…", role: .destructive) {
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
        .formStyle(.grouped)
        .task { await loadStorage() }
    }

    private func loadStorage() async {
        isLoading = true
        errorMessage = nil
        do {
            let container = modelContext.container
            let calculator = StorageCalculator(modelContainer: container)
            storageInfo = try await calculator.calculateStorage()
        } catch {
            errorMessage = "Unable to calculate storage"
        }
        isLoading = false
    }

    private func estimateCacheSizeValue() async {
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

    private func wipeAllData() {
        Task {
            for account in accounts {
                _ = try? await manageAccounts.removeAccount(id: account.id)
            }
            settings.resetAll()
        }
    }
}

// MARK: - About Tab

struct MacAboutSettingsTab: View {
    @Environment(ThemeProvider.self) private var theme
    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()

            Image(systemName: "envelope.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.colors.accent)

            Text("VaultMail")
                .font(theme.typography.displaySmall)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: theme.spacing.sm) {
                if let url = URL(string: "https://appripe.com/vaultmail/privacy.html") {
                    Link("Privacy Policy", destination: url)
                        .font(theme.typography.bodyMedium)
                }

                Text("All email data is stored locally on your device.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                Text("AI features run entirely on-device.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#if canImport(UserNotifications)
import UserNotifications
#endif

#endif
