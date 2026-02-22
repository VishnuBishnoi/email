import SwiftUI

/// Manual Account Setup form for custom IMAP/SMTP servers.
///
/// Displays IMAP/SMTP host, port, and security pickers with a
/// "Test Connection" button that runs a 4-step checklist.
/// Pre-filled from auto-discovery results when available.
///
/// Spec ref: FR-MPROV-09 (Manual Account Setup)
struct ManualAccountSetupView: View {
    @Environment(ThemeProvider.self) private var theme

    let email: String
    let discoveredConfig: DiscoveredConfig?
    let connectionTestUseCase: ConnectionTestUseCaseProtocol
    let manageAccounts: ManageAccountsUseCaseProtocol
    let onAccountAdded: (Account) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var imapHost: String = ""
    @State private var imapPort: String = "993"
    @State private var imapSecurity: ConnectionSecurity = .tls
    @State private var smtpHost: String = ""
    @State private var smtpPort: String = "587"
    @State private var smtpSecurity: ConnectionSecurity = .starttls
    @State private var password: String = ""
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                imapSection
                smtpSection
                passwordSection
                connectionTestSection

                if testResult?.allPassed == true {
                    saveSection
                }
            }
            .navigationTitle("Manual Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .task {
                prefillFromDiscovery()
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            LabeledContent("Email", value: email)
                .accessibilityLabel("Email address: \(email)")
        }
    }

    private var imapSection: some View {
        Section("IMAP Server") {
            TextField("Host", text: $imapHost)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .accessibilityLabel("IMAP server hostname")

            TextField("Port", text: $imapPort)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("IMAP server port")

            Picker("Security", selection: $imapSecurity) {
                Text("TLS/SSL").tag(ConnectionSecurity.tls)
                Text("STARTTLS").tag(ConnectionSecurity.starttls)
            }
            .accessibilityLabel("IMAP security mode")
        }
    }

    private var smtpSection: some View {
        Section("SMTP Server") {
            TextField("Host", text: $smtpHost)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .accessibilityLabel("SMTP server hostname")

            TextField("Port", text: $smtpPort)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("SMTP server port")

            Picker("Security", selection: $smtpSecurity) {
                Text("TLS/SSL").tag(ConnectionSecurity.tls)
                Text("STARTTLS").tag(ConnectionSecurity.starttls)
            }
            .accessibilityLabel("SMTP security mode")
        }
    }

    private var passwordSection: some View {
        Section("Authentication") {
            SecureField("App Password", text: $password)
                .textContentType(.password)
                .accessibilityLabel("App password")
        }
    }

    @ViewBuilder
    private var connectionTestSection: some View {
        Section("Connection Test") {
            if let result = testResult {
                connectionStepRow("IMAP Connect", result: result.imapConnect)
                connectionStepRow("IMAP Auth", result: result.imapAuth)
                connectionStepRow("SMTP Connect", result: result.smtpConnect)
                connectionStepRow("SMTP Auth", result: result.smtpAuth)
            }

            Button {
                testConnection()
            } label: {
                if isTesting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing...")
                    }
                } else {
                    Label("Test Connection", systemImage: "network")
                }
            }
            .disabled(isTesting || !isFormValid)
            .accessibilityLabel(isTesting ? "Testing connection" : "Test connection")
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        Section {
            if let errorMessage {
                Label {
                    Text(errorMessage)
                        .font(theme.typography.bodyMedium)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(theme.colors.destructive)
                .accessibilityLabel("Error: \(errorMessage)")
            }

            Button {
                saveAccount()
            } label: {
                if isSaving {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving...")
                    }
                } else {
                    Label("Add Account", systemImage: "checkmark.circle")
                }
            }
            .disabled(isSaving)
            .accessibilityLabel(isSaving ? "Saving account" : "Add account")
        }
    }

    // MARK: - Connection Step Row

    private func connectionStepRow(_ label: String, result: ConnectionTestStepResult) -> some View {
        HStack {
            Text(label)
            Spacer()
            switch result {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(theme.colors.textSecondary)
            case .testing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.colors.success)
            case .failure(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.colors.destructive)
                    .help(msg)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(stepAccessibilityLabel(result))")
    }

    private func stepAccessibilityLabel(_ result: ConnectionTestStepResult) -> String {
        switch result {
        case .pending: return "pending"
        case .testing: return "testing"
        case .success: return "success"
        case .failure(let msg): return "failed, \(msg)"
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !imapHost.isEmpty && !smtpHost.isEmpty && !password.isEmpty &&
        Int(imapPort) != nil && Int(smtpPort) != nil
    }

    // MARK: - Actions

    private func prefillFromDiscovery() {
        guard let config = discoveredConfig else { return }
        imapHost = config.imapHost
        imapPort = String(config.imapPort)
        imapSecurity = config.imapSecurity
        smtpHost = config.smtpHost
        smtpPort = String(config.smtpPort)
        smtpSecurity = config.smtpSecurity
    }

    private func testConnection() {
        isTesting = true
        testResult = ConnectionTestResult()

        Task {
            defer { isTesting = false }

            let stream = connectionTestUseCase.testConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                imapSecurity: imapSecurity,
                smtpHost: smtpHost,
                smtpPort: Int(smtpPort) ?? 587,
                smtpSecurity: smtpSecurity,
                email: email,
                password: password
            )

            for await result in stream {
                testResult = result
            }
        }
    }

    private func saveAccount() {
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                let providerConfig = ProviderRegistry.customProvider(
                    imapHost: imapHost,
                    imapPort: Int(imapPort) ?? 993,
                    imapSecurity: imapSecurity,
                    smtpHost: smtpHost,
                    smtpPort: Int(smtpPort) ?? 587,
                    smtpSecurity: smtpSecurity
                )
                let account = try await manageAccounts.addAccountViaAppPassword(
                    email: email,
                    password: password,
                    providerConfig: providerConfig,
                    skipValidation: true  // Connection already tested above
                )
                onAccountAdded(account)
            } catch let error as AccountError {
                switch error {
                case .duplicateAccount(let email):
                    errorMessage = "\(email) is already added."
                default:
                    errorMessage = "Failed to save account. Please try again."
                }
            } catch {
                errorMessage = "An unexpected error occurred. Please try again."
            }
        }
    }
}
