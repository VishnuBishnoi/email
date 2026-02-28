import SwiftUI

/// Onboarding Step 2: Email account setup.
///
/// Multi-provider mode: Shows added accounts and an "Add Account" button that
/// presents ProviderSelectionView as a sheet (email-first flow with auto-discovery).
///
/// Legacy mode (no ProviderDiscovery): Falls back to Gmail-only OAuth flow.
///
/// The Next button is disabled until at least one account is added.
///
/// Error handling follows the spec error table (FR-OB-01):
/// - OAuth cancelled → return to this screen, allow retry
/// - Network failure → "Network unavailable. Check your connection and try again."
/// - Token exchange failure → "Authentication failed. Please try again."
/// - IMAP/SMTP validation failure → "Couldn't connect. Please check account settings."
///
/// Spec ref: FR-OB-01 step 2, FR-ACCT-01, FR-ACCT-03, FR-MPROV-10
struct OnboardingAccountStep: View {
    @Environment(ThemeProvider.self) private var theme
    let manageAccounts: ManageAccountsUseCaseProtocol
    @Binding var addedAccounts: [Account]
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?
    let onNext: () -> Void

    @State private var isAddingAccount = false
    @State private var showProviderSelection = false
    @State private var errorMessage: String?

    /// Whether multi-provider support is available.
    private var hasMultiProvider: Bool {
        providerDiscovery != nil && connectionTestUseCase != nil
    }

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            Text(hasMultiProvider ? "Add Email Account" : "Add your Gmail account")
                .font(theme.typography.displaySmall)

            Text(hasMultiProvider
                ? "Add one or more email accounts to get started."
                : "Sign in with Google to access your email securely on this device.")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)

            // Added accounts list
            if !addedAccounts.isEmpty {
                VStack(spacing: theme.spacing.md) {
                    ForEach(addedAccounts, id: \.id) { account in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.colors.success)
                            Text(account.email)
                                .font(theme.typography.bodyLarge)
                            Spacer()
                        }
                        .padding(.horizontal, theme.spacing.lg)
                        .padding(.vertical, theme.spacing.listRowSpacing)
                        .background(theme.colors.surfaceElevated, in: theme.shapes.smallRect)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(account.email), added successfully")
                    }
                }
                .padding(.horizontal)
            }

            // Error display
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

            Spacer()

            // Add Account button
            Button {
                if hasMultiProvider {
                    showProviderSelection = true
                } else {
                    addGmailAccount()
                }
            } label: {
                Label("Add Account", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isAddingAccount)

            if isAddingAccount {
                ProgressView("Signing in...")
            }

            // Next button — disabled until at least one account added
            Button("Next") {
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(addedAccounts.isEmpty)
        }
        .padding(.horizontal, theme.spacing.xxxl)
        .padding(.bottom, 40)
        .task {
            await loadExistingAccounts()
        }
        .sheet(isPresented: $showProviderSelection) {
            if let discovery = providerDiscovery, let connTest = connectionTestUseCase {
                ProviderSelectionView(
                    manageAccounts: manageAccounts,
                    connectionTestUseCase: connTest,
                    providerDiscovery: discovery,
                    onAccountAdded: { account in
                        showProviderSelection = false
                        if !addedAccounts.contains(where: { $0.id == account.id }) {
                            addedAccounts.append(account)
                        }
                    },
                    onCancel: { showProviderSelection = false }
                )
            }
        }
    }

    /// Load any accounts already persisted in SwiftData so they appear in the list.
    ///
    /// This handles the case where the user previously added an account (e.g., before
    /// a simulator restart or app re-launch) — without this, the account exists in
    /// persistence but doesn't show in the onboarding list, blocking the user from
    /// proceeding since `addedAccounts` is empty and re-adding throws `.duplicateAccount`.
    private func loadExistingAccounts() async {
        do {
            let existing = try await manageAccounts.getAccounts()
            for account in existing where !addedAccounts.contains(where: { $0.id == account.id }) {
                addedAccounts.append(account)
            }
        } catch {
            // Non-fatal — user can still add accounts manually
        }
    }

    // MARK: - Legacy Gmail-only flow

    private func addGmailAccount() {
        isAddingAccount = true
        errorMessage = nil
        Task {
            defer { isAddingAccount = false }
            do {
                let account = try await manageAccounts.addAccountViaOAuth()
                addedAccounts.append(account)
            } catch let error as OAuthError {
                errorMessage = mapOAuthError(error)
            } catch let error as AccountError {
                errorMessage = mapAccountError(error)
            } catch {
                errorMessage = "An unexpected error occurred. Please try again."
            }
        }
    }

    /// Maps OAuth errors to user-facing messages per FR-OB-01 error table.
    private func mapOAuthError(_ error: OAuthError) -> String? {
        switch error {
        case .authenticationCancelled:
            return nil
        case .networkError:
            return "Network unavailable. Check your connection and try again."
        case .tokenExchangeFailed:
            return "Authentication failed. Please try again."
        case .invalidAuthorizationCode, .invalidResponse:
            return "Authentication failed. Please try again."
        case .tokenRefreshFailed:
            return "Authentication failed. Please try again."
        case .maxRetriesExceeded:
            return "Authentication failed after multiple attempts. Please try again later."
        case .noRefreshToken:
            return "Authentication failed. Please try again."
        }
    }

    /// Maps Account errors to user-facing messages.
    private func mapAccountError(_ error: AccountError) -> String {
        switch error {
        case .duplicateAccount(let email):
            return "\(email) is already added."
        case .persistenceFailed:
            return "Couldn't save the account. Please try again."
        default:
            return "An error occurred. Please try again."
        }
    }
}
