import SwiftUI

/// Email-first provider selection for onboarding and "Add Account" flow.
///
/// Flow: Enter email → auto-discover → route to appropriate auth:
/// - OAuth provider (Gmail/Outlook) → OAuth flow
/// - App password provider (Yahoo/iCloud) → AppPasswordEntryView
/// - Unknown → ManualAccountSetupView (pre-filled from ISPDB/DNS if found)
///
/// Also provides quick-add buttons for known providers.
///
/// Spec ref: FR-MPROV-10 (Onboarding & Provider Selection)
struct ProviderSelectionView: View {
    @Environment(ThemeProvider.self) private var theme

    let manageAccounts: ManageAccountsUseCaseProtocol
    let connectionTestUseCase: ConnectionTestUseCaseProtocol
    let providerDiscovery: ProviderDiscovery
    let onAccountAdded: (Account) -> Void
    let onCancel: () -> Void

    @State private var email = ""
    @State private var isDiscovering = false
    @State private var errorMessage: String?
    @State private var navigationDestination: NavigationDestinationType?

    enum NavigationDestinationType: Identifiable {
        case appPassword(ProviderConfiguration)
        case manualSetup(DiscoveredConfig?)

        var id: String {
            switch self {
            case .appPassword(let config): return "appPassword-\(config.identifier.rawValue)"
            case .manualSetup: return "manualSetup"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.xxl) {
                Spacer()

                Image(systemName: "envelope.badge.person.crop")
                    .font(.system(size: 60))
                    .foregroundStyle(theme.colors.accent)
                    .accessibilityHidden(true)

                Text("Add Email Account")
                    .font(theme.typography.displaySmall)

                Text("Enter your email address to get started, or choose a provider below.")
                    .font(theme.typography.bodyLarge)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Email input
                VStack(spacing: theme.spacing.md) {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .padding(theme.spacing.md)
                        .background(theme.colors.surfaceElevated, in: theme.shapes.smallRect)
                        .accessibilityLabel("Email address")

                    Button {
                        discoverAndRoute()
                    } label: {
                        if isDiscovering {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Discovering settings...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(email.isEmpty || isDiscovering)
                    .accessibilityLabel(isDiscovering ? "Discovering email settings" : "Continue with email")
                }
                .padding(.horizontal)

                if let errorMessage {
                    Label {
                        Text(errorMessage)
                            .font(theme.typography.bodyMedium)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(theme.colors.destructive)
                    .padding(.horizontal)
                    .accessibilityLabel("Error: \(errorMessage)")
                }

                // Divider
                HStack {
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 1)
                    Text("or")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 1)
                }
                .padding(.horizontal, theme.spacing.xxxl)

                // Quick-add provider buttons
                quickAddButtons

                Spacer()
            }
            .navigationTitle("Add Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .sheet(item: $navigationDestination) { destination in
                destinationView(for: destination)
            }
        }
    }

    // MARK: - Quick Add Buttons

    private var quickAddButtons: some View {
        VStack(spacing: theme.spacing.listRowSpacing) {
            quickAddButton(
                label: "Sign in with Google",
                icon: "envelope.fill",
                color: .red
            ) {
                addGmailAccount()
            }

            quickAddButton(
                label: "Sign in with iCloud",
                icon: "icloud.fill",
                color: .blue
            ) {
                email = ""
                navigationDestination = .appPassword(ProviderRegistry.icloud)
            }

            quickAddButton(
                label: "Sign in with Yahoo",
                icon: "envelope.fill",
                color: .purple
            ) {
                email = ""
                navigationDestination = .appPassword(ProviderRegistry.yahoo)
            }
        }
        .padding(.horizontal)
    }

    private func quickAddButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.md)
            .background(theme.colors.surfaceElevated, in: theme.shapes.smallRect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Destination View

    @ViewBuilder
    private func destinationView(for destination: NavigationDestinationType) -> some View {
        switch destination {
        case .appPassword(let providerConfig):
            AppPasswordEntryView(
                email: email,
                providerConfig: providerConfig,
                connectionTestUseCase: connectionTestUseCase,
                manageAccounts: manageAccounts,
                onAccountAdded: { account in
                    navigationDestination = nil
                    onAccountAdded(account)
                },
                onCancel: { navigationDestination = nil }
            )
        case .manualSetup(let discoveredConfig):
            ManualAccountSetupView(
                email: email,
                discoveredConfig: discoveredConfig,
                connectionTestUseCase: connectionTestUseCase,
                manageAccounts: manageAccounts,
                onAccountAdded: { account in
                    navigationDestination = nil
                    onAccountAdded(account)
                },
                onCancel: { navigationDestination = nil }
            )
        }
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

            // Check static registry first (sync)
            if let knownProvider = ProviderRegistry.provider(for: email) {
                switch knownProvider.authMethod {
                case .xoauth2:
                    if knownProvider.identifier == .gmail {
                        addGmailAccount()
                    } else {
                        // Outlook (blocked) — show informative error
                        errorMessage = String(
                            localized: "Outlook sign-in is coming soon.",
                            comment: "Provider selection: Outlook not yet supported"
                        )
                    }
                case .plain:
                    navigationDestination = .appPassword(knownProvider)
                }
                return
            }

            // Auto-discover
            let config = await providerDiscovery.discover(for: email)
            if let config {
                navigationDestination = .manualSetup(config)
            } else {
                // No discovery result — go to manual setup
                navigationDestination = .manualSetup(nil)
            }
        }
    }

    private func addGmailAccount() {
        isDiscovering = true
        errorMessage = nil

        Task {
            defer { isDiscovering = false }
            do {
                let account = try await manageAccounts.addAccountViaOAuth()
                onAccountAdded(account)
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
}

