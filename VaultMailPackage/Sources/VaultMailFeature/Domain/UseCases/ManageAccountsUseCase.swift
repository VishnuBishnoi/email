import Foundation

/// Domain use case for account management operations.
///
/// Per Foundation FR-FOUND-01, views **MUST** call domain use cases only —
/// never repositories directly. This use case orchestrates OAuth authentication,
/// account persistence, and Keychain token storage.
///
/// Spec ref: Settings & Onboarding spec FR-SET-02, FR-OB-01
///           Account Management spec FR-ACCT-01..05
@MainActor
public protocol ManageAccountsUseCaseProtocol {
    /// Authenticate via OAuth 2.0 PKCE, create an account with Gmail defaults,
    /// store the token in Keychain, persist the account in SwiftData, and
    /// validate IMAP connectivity.
    ///
    /// Throws `AccountError.imapValidationFailed` if IMAP connection fails.
    /// Spec ref: FR-ACCT-01, FR-OB-01 step 2
    func addAccountViaOAuth() async throws -> Account

    /// Add an account using an app password (Yahoo, iCloud, custom IMAP).
    ///
    /// Creates the account with provider config, stores the password in Keychain,
    /// persists the account, and optionally validates IMAP connectivity.
    ///
    /// Pass `skipValidation: true` when the caller has already verified the
    /// connection (e.g. the Manual Setup flow runs its own 4-step connection test).
    ///
    /// Spec ref: FR-MPROV-06
    func addAccountViaAppPassword(
        email: String,
        password: String,
        providerConfig: ProviderConfiguration,
        skipValidation: Bool
    ) async throws -> Account

    /// Remove an account and all associated data (cascade delete).
    /// Returns `true` if no accounts remain after removal (signals onboarding re-entry).
    func removeAccount(id: String) async throws -> Bool

    /// Retrieve all configured accounts sorted by email.
    func getAccounts() async throws -> [Account]

    /// Update an existing account's mutable fields (displayName, syncWindowDays, etc.).
    func updateAccount(_ account: Account) async throws

    /// Re-authenticate an inactive account via OAuth, update the token,
    /// and set the account back to active.
    /// For app-password accounts, throws `AccountError.appPasswordReAuthRequired`.
    func reAuthenticateAccount(id: String) async throws

    /// Update the app password for a PLAIN-auth account and re-activate it.
    /// Validates the new password via IMAP before storing.
    func updateAppPassword(for accountId: String, newPassword: String) async throws
}

/// Default `skipValidation = false` so existing call sites don't break.
extension ManageAccountsUseCaseProtocol {
    func addAccountViaAppPassword(
        email: String,
        password: String,
        providerConfig: ProviderConfiguration
    ) async throws -> Account {
        try await addAccountViaAppPassword(
            email: email,
            password: password,
            providerConfig: providerConfig,
            skipValidation: false
        )
    }
}

/// Closure type for resolving the authenticated user's email from an access token.
/// Default implementation calls Google UserInfo API. Tests inject a mock closure.
public typealias EmailResolver = @MainActor @Sendable (String) async throws -> String

/// Default implementation of ManageAccountsUseCaseProtocol.
///
/// Orchestrates AccountRepositoryProtocol, OAuthManagerProtocol, and
/// KeychainManagerProtocol to fulfill account management requirements.
@MainActor
public final class ManageAccountsUseCase: ManageAccountsUseCaseProtocol {

    private let repository: AccountRepositoryProtocol
    private let oauthManager: OAuthManagerProtocol
    private let keychainManager: KeychainManagerProtocol
    private let resolveEmail: EmailResolver
    private let connectionProvider: ConnectionProviding?

    /// Creates a ManageAccountsUseCase.
    /// - Parameters:
    ///   - repository: Account persistence.
    ///   - oauthManager: OAuth 2.0 authentication.
    ///   - keychainManager: Token storage.
    ///   - connectionProvider: Optional IMAP connection provider for validating
    ///     credentials during account creation (FR-ACCT-01). Pass `nil` to skip.
    ///   - resolveEmail: Resolves user email from access token.
    ///     Defaults to Google UserInfo API call.
    public init(
        repository: AccountRepositoryProtocol,
        oauthManager: OAuthManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        connectionProvider: ConnectionProviding? = nil,
        resolveEmail: EmailResolver? = nil
    ) {
        self.repository = repository
        self.oauthManager = oauthManager
        self.keychainManager = keychainManager
        self.connectionProvider = connectionProvider
        self.resolveEmail = resolveEmail ?? Self.defaultEmailResolver
    }

    // MARK: - ManageAccountsUseCaseProtocol

    public func addAccountViaOAuth() async throws -> Account {
        // Step 1: Authenticate via OAuth 2.0 PKCE
        let token = try await oauthManager.authenticate()

        // Step 2: Resolve authenticated user's email from access token
        let email = try await resolveEmail(token.accessToken)

        // Step 3: Create account using provider config from ProviderRegistry.
        // The OAuthManager's `provider` tells us which provider was authenticated,
        // so we look up server settings dynamically instead of hardcoding Gmail.
        let providerConfig = ProviderRegistry.provider(for: oauthManager.provider)
        let account: Account
        if let providerConfig {
            account = Account(
                email: email,
                displayName: email.components(separatedBy: "@").first ?? email,
                providerConfig: providerConfig
            )
        } else {
            // Fallback for unknown OAuth providers (shouldn't happen in practice)
            account = Account(
                email: email,
                displayName: email.components(separatedBy: "@").first ?? email,
                imapHost: AppConstants.gmailImapHost,
                imapPort: AppConstants.gmailImapPort,
                smtpHost: AppConstants.gmailSmtpHost,
                smtpPort: AppConstants.gmailSmtpPort
            )
        }

        // Step 4: Store token in Keychain (never in SwiftData — AC-SEC-02)
        try await keychainManager.store(token, for: account.id)

        // Step 5: Persist account in SwiftData
        do {
            try await repository.addAccount(account)
        } catch {
            // Roll back Keychain on persistence failure
            try? await keychainManager.delete(for: account.id)
            throw error
        }

        // Step 6: Validate IMAP connectivity (FR-ACCT-01, FR-OB-01 step 2).
        // Connect to imap.gmail.com:993 with XOAUTH2 to verify credentials work.
        // If validation fails, roll back both Keychain and SwiftData.
        if let provider = connectionProvider {
            do {
                let client = try await provider.checkoutConnection(
                    accountId: account.id,
                    host: account.imapHost,
                    port: account.imapPort,
                    email: account.email,
                    accessToken: token.accessToken
                )
                // Connection succeeded — return it to pool immediately
                await provider.checkinConnection(client, accountId: account.id)
            } catch {
                // Roll back: remove account from SwiftData and Keychain
                try? await repository.removeAccount(id: account.id)
                try? await keychainManager.delete(for: account.id)
                throw AccountError.imapValidationFailed(error.localizedDescription)
            }
        }

        return account
    }

    public func addAccountViaAppPassword(
        email: String,
        password: String,
        providerConfig: ProviderConfiguration,
        skipValidation: Bool = false
    ) async throws -> Account {
        // Step 1: Create account from provider config
        let displayName = email.components(separatedBy: "@").first ?? email
        let account = Account(
            email: email,
            displayName: displayName,
            providerConfig: providerConfig
        )

        // Step 2: Store password in Keychain (never in SwiftData — AC-SEC-02)
        try await keychainManager.storeCredential(.password(password), for: account.id)

        // Step 3: Persist account in SwiftData
        do {
            try await repository.addAccount(account)
        } catch {
            // Roll back Keychain on persistence failure
            try? await keychainManager.deleteCredential(for: account.id)
            throw error
        }

        // Step 4: Validate IMAP connectivity using PLAIN auth (30-second timeout).
        // Skipped when the caller already ran a connection test (e.g. Manual Setup).
        // If validation fails, roll back both Keychain and SwiftData.
        if !skipValidation, let provider = connectionProvider {
            do {
                let credential: IMAPCredential = .plain(username: email, password: password)
                let accountId = account.id
                let host = account.imapHost
                let port = account.imapPort
                let security = account.resolvedImapSecurity

                let validationTask = Task {
                    let client = try await provider.checkoutConnection(
                        accountId: accountId,
                        host: host,
                        port: port,
                        security: security,
                        credential: credential
                    )
                    await provider.checkinConnection(client, accountId: accountId)
                }

                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(30))
                    validationTask.cancel()
                }

                do {
                    try await validationTask.value
                    timeoutTask.cancel()
                } catch {
                    timeoutTask.cancel()
                    if Task.isCancelled {
                        throw AccountError.imapValidationFailed("Connection timed out after 30 seconds.")
                    }
                    throw error
                }
            } catch {
                // Roll back: remove account from SwiftData and Keychain
                try? await repository.removeAccount(id: account.id)
                try? await keychainManager.deleteCredential(for: account.id)
                throw AccountError.imapValidationFailed(error.localizedDescription)
            }
        }
        return account
    }

    public func removeAccount(id: String) async throws -> Bool {
        // Delete Keychain credential first (security: prevent stale tokens/passwords)
        try? await keychainManager.deleteCredential(for: id)

        try await repository.removeAccount(id: id)

        // Check if any accounts remain
        let remaining = try await repository.getAccounts()
        return remaining.isEmpty
    }

    public func getAccounts() async throws -> [Account] {
        try await repository.getAccounts()
    }

    public func updateAccount(_ account: Account) async throws {
        try await repository.updateAccount(account)
    }

    public func reAuthenticateAccount(id: String) async throws {
        // Fetch account to determine auth method
        let accounts = try await repository.getAccounts()
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw AccountError.notFound(id)
        }

        // Check if this is an app-password provider (PLAIN auth)
        if account.resolvedAuthMethod == .plain {
            throw AccountError.appPasswordReAuthRequired(account.email)
        }

        // OAuth re-authentication flow
        let newToken = try await oauthManager.authenticate()
        try await keychainManager.update(newToken, for: id)

        account.isActive = true
        try await repository.updateAccount(account)
    }

    /// Updates an app-password account's credential and re-activates it.
    ///
    /// Spec ref: FR-MPROV-06
    public func updateAppPassword(for accountId: String, newPassword: String) async throws {
        let accounts = try await repository.getAccounts()
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            throw AccountError.notFound(accountId)
        }

        // Validate new password with IMAP connection
        if let provider = connectionProvider {
            let credential: IMAPCredential = .plain(username: account.email, password: newPassword)
            let client = try await provider.checkoutConnection(
                accountId: account.id,
                host: account.imapHost,
                port: account.imapPort,
                security: account.resolvedImapSecurity,
                credential: credential
            )
            await provider.checkinConnection(client, accountId: account.id)
        }

        // Store updated password
        try await keychainManager.updateCredential(.password(newPassword), for: accountId)

        account.isActive = true
        try await repository.updateAccount(account)
    }

    // MARK: - Private

    /// Default email resolver that calls Google UserInfo API.
    ///
    /// When Outlook OAuth is implemented (OQ-01), this should be replaced with a
    /// provider-aware resolver. Microsoft uses the `id_token` JWT claims from the
    /// OAuth response (not a separate API call) to extract the email.
    private static let defaultEmailResolver: EmailResolver = { accessToken in
        let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            throw OAuthError.invalidResponse
        }

        return email
    }
}
