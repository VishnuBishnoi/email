#if os(macOS)
import SwiftUI

/// Native macOS account setup flow replacing the iOS-designed ProviderSelectionView.
///
/// Provides a multi-step wizard: email entry → provider discovery → auth flow.
/// Uses native macOS Form + grouped style for a System Preferences–like appearance.
///
/// Spec ref: FR-MPROV-10 (Onboarding & Provider Selection), macOS adaptation
@MainActor
struct MacAddAccountView: View {
    @Environment(ThemeProvider.self) private var theme

    let manageAccounts: ManageAccountsUseCaseProtocol
    let connectionTestUseCase: ConnectionTestUseCaseProtocol
    let providerDiscovery: ProviderDiscovery
    let onAccountAdded: (Account) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var currentStep: Step = .providerChoice
    @State private var email = ""
    @State private var isDiscovering = false
    @State private var errorMessage: String?

    // App password flow
    @State private var selectedProvider: ProviderConfiguration?
    @State private var password = ""
    @State private var isAddingAccount = false

    // Manual setup flow
    @State private var discoveredConfig: DiscoveredConfig?
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var imapSecurity: ConnectionSecurity = .tls
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var smtpSecurity: ConnectionSecurity = .starttls
    @State private var manualPassword = ""
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testTask: Task<Void, Never>?

    enum Step {
        case providerChoice
        case appPassword
        case manualSetup
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case .providerChoice:
                providerChoiceContent
            case .appPassword:
                appPasswordContent
            case .manualSetup:
                manualSetupContent
            }
        }
        .frame(width: 480, height: stepHeight)
        .background(.background)
    }

    private var stepHeight: CGFloat {
        switch currentStep {
        case .providerChoice: return 420
        case .appPassword: return 380
        case .manualSetup: return 560
        }
    }

    // MARK: - Step 1: Provider Choice

    private var providerChoiceContent: some View {
        VStack(spacing: 0) {
            // Header
            macHeader(
                icon: "envelope.badge.person.crop",
                title: "Add Email Account",
                subtitle: "Enter your email to auto-detect settings, or choose a provider."
            )

            Divider()

            // Content
            Form {
                Section("Email Address") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Email address")
                        .onSubmit { discoverAndRoute() }
                }

                Section("Quick Add") {
                    providerButton(
                        label: "Google (Gmail)",
                        icon: "envelope.fill",
                        color: .red
                    ) {
                        addGmailAccount()
                    }

                    providerButton(
                        label: "iCloud Mail",
                        icon: "icloud.fill",
                        color: .blue
                    ) {
                        email = ""
                        selectedProvider = ProviderRegistry.icloud
                        currentStep = .appPassword
                    }

                    providerButton(
                        label: "Yahoo Mail",
                        icon: "envelope.fill",
                        color: .purple
                    ) {
                        email = ""
                        selectedProvider = ProviderRegistry.yahoo
                        currentStep = .appPassword
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                errorBanner(errorMessage)
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, theme.spacing.sm)
                }
                Button("Continue") { discoverAndRoute() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(email.isEmpty || isDiscovering)
            }
            .padding()
        }
    }

    // MARK: - Step 2a: App Password

    private var appPasswordContent: some View {
        VStack(spacing: 0) {
            if let provider = selectedProvider {
                macHeader(
                    icon: providerIcon(for: provider),
                    title: "Sign in to \(provider.displayName)",
                    subtitle: "Enter your email and app-specific password."
                )
            }

            Divider()

            Form {
                Section {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Email address")

                    SecureField("App Password", text: $password)
                        .textContentType(.password)
                        .accessibilityLabel("App password")
                }

                if let provider = selectedProvider, let helpURL = provider.appPasswordHelpURL {
                    Section {
                        Link(destination: helpURL) {
                            Label("How to create an app password", systemImage: "questionmark.circle")
                                .font(theme.typography.bodyMedium)
                        }
                        .accessibilityLabel("Open \(provider.displayName) app password instructions")
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                errorBanner(errorMessage)
            }

            Divider()

            HStack {
                Button("Back") {
                    currentStep = .providerChoice
                    password = ""
                    errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if isAddingAccount {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, theme.spacing.sm)
                }
                Button("Sign In") { addAppPasswordAccount() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(email.isEmpty || password.isEmpty || isAddingAccount)
            }
            .padding()
        }
    }

    // MARK: - Step 2b: Manual Setup

    private var manualSetupContent: some View {
        VStack(spacing: 0) {
            macHeader(
                icon: "server.rack",
                title: "Manual Setup",
                subtitle: email
            )

            Divider()

            Form {
                Section("IMAP Server") {
                    TextField("Host", text: $imapHost)
                        .autocorrectionDisabled()
                        .accessibilityLabel("IMAP server hostname")

                    TextField("Port", text: $imapPort)
                        .accessibilityLabel("IMAP server port")

                    Picker("Security", selection: $imapSecurity) {
                        Text("TLS/SSL").tag(ConnectionSecurity.tls)
                        Text("STARTTLS").tag(ConnectionSecurity.starttls)
                    }
                    .accessibilityLabel("IMAP security mode")
                }

                Section("SMTP Server") {
                    TextField("Host", text: $smtpHost)
                        .autocorrectionDisabled()
                        .accessibilityLabel("SMTP server hostname")

                    TextField("Port", text: $smtpPort)
                        .accessibilityLabel("SMTP server port")

                    Picker("Security", selection: $smtpSecurity) {
                        Text("TLS/SSL").tag(ConnectionSecurity.tls)
                        Text("STARTTLS").tag(ConnectionSecurity.starttls)
                    }
                    .accessibilityLabel("SMTP security mode")
                }

                Section("Authentication") {
                    SecureField("App Password", text: $manualPassword)
                        .textContentType(.password)
                        .accessibilityLabel("App password")
                }

                Section("Connection Test") {
                    if let result = testResult {
                        testStepRow("IMAP Connect", result: result.imapConnect)
                        testStepRow("IMAP Auth", result: result.imapAuth)
                        testStepRow("SMTP Connect", result: result.smtpConnect)
                        testStepRow("SMTP Auth", result: result.smtpAuth)
                    }

                    Button {
                        runConnectionTest()
                    } label: {
                        if isTesting {
                            HStack(spacing: theme.spacing.chipVertical) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                    }
                    .disabled(isTesting || !isManualFormValid)
                    .accessibilityLabel(isTesting ? "Testing connection" : "Test connection")
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                errorBanner(errorMessage)
            }

            Divider()

            HStack {
                Button("Back") {
                    currentStep = .providerChoice
                    testTask?.cancel()
                    testResult = nil
                    errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, theme.spacing.sm)
                }
                Button("Add Account") { saveManualAccount() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(testResult?.allPassed != true || isSaving)
            }
            .padding()
        }
    }

    // MARK: - Shared Components

    private func macHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: theme.spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            Text(title)
                .font(theme.typography.titleMedium)

            Text(subtitle)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, theme.spacing.lg)
        .padding(.horizontal, theme.spacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: theme.spacing.chipVertical) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.destructive)
            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.destructive)
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.vertical, theme.spacing.sm)
        .accessibilityLabel("Error: \(message)")
    }

    private func providerButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: theme.spacing.iconSize)
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func testStepRow(_ label: String, result: ConnectionTestStepResult) -> some View {
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
    }

    private func providerIcon(for provider: ProviderConfiguration) -> String {
        switch provider.identifier {
        case .icloud: return "icloud.fill"
        case .yahoo: return "envelope.fill"
        case .gmail: return "envelope.fill"
        default: return "envelope.badge.shield.half.filled.fill"
        }
    }

    // MARK: - Validation

    private var isManualFormValid: Bool {
        !imapHost.isEmpty && !smtpHost.isEmpty && !manualPassword.isEmpty &&
        Int(imapPort) != nil && Int(smtpPort) != nil
    }

    // MARK: - Actions

    private func discoverAndRoute() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Basic email format validation
        guard trimmed.contains("@"),
              let atIndex = trimmed.lastIndex(of: "@"),
              atIndex > trimmed.startIndex,
              trimmed.index(after: atIndex) < trimmed.endIndex,
              trimmed[trimmed.index(after: atIndex)...].contains(".") else {
            errorMessage = "Please enter a valid email address."
            return
        }

        email = trimmed
        isDiscovering = true
        errorMessage = nil

        Task {
            defer { isDiscovering = false }

            // Check static registry first
            if let knownProvider = ProviderRegistry.provider(for: email) {
                switch knownProvider.authMethod {
                case .xoauth2:
                    if knownProvider.identifier == .gmail {
                        addGmailAccount()
                    } else {
                        errorMessage = String(
                            localized: "Outlook sign-in is coming soon.",
                            comment: "Provider selection: Outlook not yet supported"
                        )
                    }
                case .plain:
                    selectedProvider = knownProvider
                    currentStep = .appPassword
                }
                return
            }

            // Auto-discover
            let config = await providerDiscovery.discover(for: email)
            discoveredConfig = config
            prefillFromDiscovery(config)
            currentStep = .manualSetup
        }
    }

    private func prefillFromDiscovery(_ config: DiscoveredConfig?) {
        guard let config else { return }
        imapHost = config.imapHost
        imapPort = String(config.imapPort)
        imapSecurity = config.imapSecurity
        smtpHost = config.smtpHost
        smtpPort = String(config.smtpPort)
        smtpSecurity = config.smtpSecurity
    }

    private func addGmailAccount() {
        isDiscovering = true
        errorMessage = nil

        Task {
            defer { isDiscovering = false }
            do {
                let account = try await manageAccounts.addAccountViaOAuth()
                onAccountAdded(account)
                dismiss()
            } catch let error as OAuthError {
                if case .authenticationCancelled = error { return }
                errorMessage = "Authentication failed. Please try again."
            } catch let error as AccountError {
                if case .duplicateAccount(let email) = error {
                    errorMessage = "\(email) is already added."
                } else {
                    errorMessage = "Failed to add account. Please try again."
                }
            } catch {
                errorMessage = "An unexpected error occurred."
            }
        }
    }

    private func addAppPasswordAccount() {
        guard let provider = selectedProvider else { return }
        isAddingAccount = true
        errorMessage = nil

        Task {
            defer { isAddingAccount = false }

            // Step 1: Run 4-step connection test (IMAP + SMTP)
            let stream = connectionTestUseCase.testConnection(
                imapHost: provider.imapHost,
                imapPort: provider.imapPort,
                imapSecurity: provider.imapSecurity,
                smtpHost: provider.smtpHost,
                smtpPort: provider.smtpPort,
                smtpSecurity: provider.smtpSecurity,
                email: email,
                password: password
            )

            var finalResult = ConnectionTestResult()
            for await update in stream {
                finalResult = update
            }

            guard finalResult.allPassed else {
                if case .failure = finalResult.imapConnect {
                    errorMessage = "IMAP connection failed. Check server settings."
                } else if case .failure = finalResult.imapAuth {
                    errorMessage = "IMAP authentication failed. Check your app password."
                } else if case .failure = finalResult.smtpConnect {
                    errorMessage = "SMTP connection failed. Check server settings."
                } else if case .failure = finalResult.smtpAuth {
                    errorMessage = "SMTP authentication failed. Check your app password."
                } else {
                    errorMessage = "Connection test did not complete. Please try again."
                }
                return
            }

            // Step 2: Save the account (skip re-validation — already tested)
            do {
                let account = try await manageAccounts.addAccountViaAppPassword(
                    email: email,
                    password: password,
                    providerConfig: provider,
                    skipValidation: true
                )
                onAccountAdded(account)
                dismiss()
            } catch let error as AccountError {
                switch error {
                case .duplicateAccount(let email):
                    errorMessage = "\(email) is already added."
                default:
                    errorMessage = "Failed to add account. Please try again."
                }
            } catch {
                errorMessage = "An unexpected error occurred. Please try again."
            }
        }
    }

    private func runConnectionTest() {
        isTesting = true
        testResult = ConnectionTestResult()
        errorMessage = nil

        testTask?.cancel()
        testTask = Task {
            defer { isTesting = false }

            let stream = connectionTestUseCase.testConnection(
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                imapSecurity: imapSecurity,
                smtpHost: smtpHost,
                smtpPort: Int(smtpPort) ?? 587,
                smtpSecurity: smtpSecurity,
                email: email,
                password: manualPassword
            )

            for await result in stream {
                testResult = result
            }
        }
    }

    private func saveManualAccount() {
        isSaving = true
        errorMessage = nil

        // Cancel the connection test task if still running, so its
        // disconnect operations don't compete for the @MainActor.
        testTask?.cancel()
        testTask = nil

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
                    password: manualPassword,
                    providerConfig: providerConfig,
                    skipValidation: true  // Connection already tested above
                )
                onAccountAdded(account)
                dismiss()
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

// MARK: - Previews

#Preview("Provider Choice") {
    MacAddAccountView(
        manageAccounts: PreviewManageAccounts(),
        connectionTestUseCase: ConnectionTestUseCase(),
        providerDiscovery: ProviderDiscovery(),
        onAccountAdded: { _ in },
        onCancel: {}
    )
    .environment(ThemeProvider())
}

/// Minimal mock for macOS previews.
@MainActor
private final class PreviewManageAccounts: ManageAccountsUseCaseProtocol {
    func addAccountViaOAuth() async throws -> Account { Account(email: "test@gmail.com", displayName: "Test") }
    func addAccountViaAppPassword(email: String, password: String, providerConfig: ProviderConfiguration, skipValidation: Bool = false) async throws -> Account {
        Account(email: email, displayName: email.components(separatedBy: "@").first ?? email)
    }
    func removeAccount(id: String) async throws -> Bool { false }
    func getAccounts() async throws -> [Account] { [] }
    func updateAccount(_ account: Account) async throws {}
    func reAuthenticateAccount(id: String) async throws {}
    func updateAppPassword(for id: String, newPassword: String) async throws {}
}
#endif
