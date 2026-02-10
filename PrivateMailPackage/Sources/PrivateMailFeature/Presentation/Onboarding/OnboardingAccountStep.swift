import SwiftUI

/// Onboarding Step 2: Gmail account setup via OAuth.
///
/// Displays "Add your Gmail account" with an Add Account button that invokes
/// the OAuth 2.0 PKCE flow. Shows added accounts with success indicators.
/// The Next button is disabled until at least one account is added.
///
/// Error handling follows the spec error table (FR-OB-01):
/// - OAuth cancelled → return to this screen, allow retry
/// - Network failure → "Network unavailable. Check your connection and try again."
/// - Token exchange failure → "Authentication failed. Please try again."
/// - IMAP/SMTP validation failure → "Couldn't connect to Gmail. Please check account permissions."
///
/// Spec ref: FR-OB-01 step 2, FR-ACCT-01, FR-ACCT-03
struct OnboardingAccountStep: View {
    let manageAccounts: ManageAccountsUseCaseProtocol
    @Binding var addedAccounts: [Account]
    let onNext: () -> Void

    @State private var isAddingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Add your Gmail account")
                .font(.title2.bold())

            Text("Sign in with Google to access your email securely on this device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Added accounts list
            if !addedAccounts.isEmpty {
                VStack(spacing: 12) {
                    ForEach(addedAccounts, id: \.id) { account in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(account.email)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
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
                        .font(.callout)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .accessibilityLabel("Error: \(errorMessage)")
            }

            Spacer()

            // Add Account button
            Button {
                addAccount()
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
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .task {
            await loadExistingAccounts()
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

    // MARK: - Actions

    private func addAccount() {
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
            // User intentionally cancelled — no error message, allow retry
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
