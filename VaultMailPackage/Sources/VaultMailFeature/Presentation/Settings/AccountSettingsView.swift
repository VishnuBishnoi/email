import SwiftUI

/// Per-account settings: sync window, display name, re-authenticate, remove.
///
/// Spec ref: FR-SET-02, FR-ACCT-02, FR-ACCT-04, FR-ACCT-05
struct AccountSettingsView: View {
    let account: Account
    let manageAccounts: ManageAccountsUseCaseProtocol
    let onAccountRemoved: (Bool) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var syncWindowDays: Int
    @State private var showRemoveConfirmation = false
    @State private var showSyncWindowConfirmation = false
    @State private var pendingSyncWindow: Int?
    @State private var isReAuthenticating = false
    @State private var showPasswordUpdate = false
    @State private var newAppPassword = ""
    @State private var reAuthError: String?
    @State private var cacheLimit: Int

    init(
        account: Account,
        manageAccounts: ManageAccountsUseCaseProtocol,
        onAccountRemoved: @escaping (Bool) -> Void
    ) {
        self.account = account
        self.manageAccounts = manageAccounts
        self.onAccountRemoved = onAccountRemoved
        self._displayName = State(initialValue: account.displayName)
        self._syncWindowDays = State(initialValue: account.syncWindowDays)
        // cacheLimit will be properly initialized from SettingsStore in .task
        self._cacheLimit = State(initialValue: AppConstants.maxAttachmentCacheMB)
    }

    var body: some View {
        List {
            // Account info
            Section {
                LabeledContent("Email", value: account.email)

                if let provider = account.provider {
                    LabeledContent("Provider", value: provider.capitalized)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Account inactive. Re-authenticate to restore access.")
                }

                if let error = reAuthError {
                    Text(error)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.destructive)
                }
            }

            // Sync window picker (FR-ACCT-02)
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
                .accessibilityLabel("Sync window")
                .accessibilityValue("\(syncWindowDays) days")
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
            }

            // Display name (FR-ACCT-02)
            Section("Display Name") {
                TextField("Display Name", text: $displayName)
                    .onSubmit {
                        saveDisplayName()
                    }
                    .accessibilityLabel("Display name")
            }

            // Attachment cache limit (FR-SET-03)
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
                .accessibilityLabel("Attachment cache limit")
            }

            // Remove account (FR-ACCT-05)
            Section {
                Button("Remove Account", role: .destructive) {
                    showRemoveConfirmation = true
                }
                .alert("Remove Account", isPresented: $showRemoveConfirmation) {
                    Button("Remove", role: .destructive) {
                        removeAccount()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove \(account.email)? All local emails, drafts, and cached data for this account will be deleted.")
                }
            }
        }
        .navigationTitle(account.email)
        .task {
            cacheLimit = settings.cacheLimit(for: account.id)
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

    // MARK: - Actions

    private func saveSyncWindow() {
        account.syncWindowDays = syncWindowDays
        Task {
            try? await manageAccounts.updateAccount(account)
        }
    }

    private func saveDisplayName() {
        account.displayName = displayName
        Task {
            try? await manageAccounts.updateAccount(account)
        }
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
                    // App-password account — show password update dialog
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

    private func removeAccount() {
        Task {
            do {
                let wasLast = try await manageAccounts.removeAccount(id: account.id)
                dismiss()
                onAccountRemoved(wasLast)
            } catch {
                // Handle error silently for now
            }
        }
    }
}
