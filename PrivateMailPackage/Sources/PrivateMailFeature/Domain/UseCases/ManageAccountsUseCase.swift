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
    /// store the token in Keychain, and persist the account in SwiftData.
    /// Returns the newly created Account.
    ///
    /// IMAP/SMTP validation is stubbed until the sync layer is built (FR-ACCT-01).
    func addAccountViaOAuth() async throws -> Account

    /// Remove an account and all associated data (cascade delete).
    /// Returns `true` if no accounts remain after removal (signals onboarding re-entry).
    func removeAccount(id: String) async throws -> Bool

    /// Retrieve all configured accounts sorted by email.
    func getAccounts() async throws -> [Account]

    /// Update an existing account's mutable fields (displayName, syncWindowDays, etc.).
    func updateAccount(_ account: Account) async throws

    /// Re-authenticate an inactive account via OAuth, update the token,
    /// and set the account back to active.
    func reAuthenticateAccount(id: String) async throws
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

    /// Creates a ManageAccountsUseCase.
    /// - Parameters:
    ///   - repository: Account persistence.
    ///   - oauthManager: OAuth 2.0 authentication.
    ///   - keychainManager: Token storage.
    ///   - resolveEmail: Resolves user email from access token.
    ///     Defaults to Google UserInfo API call.
    public init(
        repository: AccountRepositoryProtocol,
        oauthManager: OAuthManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        resolveEmail: EmailResolver? = nil
    ) {
        self.repository = repository
        self.oauthManager = oauthManager
        self.keychainManager = keychainManager
        self.resolveEmail = resolveEmail ?? Self.defaultEmailResolver
    }

    // MARK: - ManageAccountsUseCaseProtocol

    public func addAccountViaOAuth() async throws -> Account {
        // Step 1: Authenticate via OAuth 2.0 PKCE
        let token = try await oauthManager.authenticate()

        // Step 2: Resolve authenticated user's email from access token
        let email = try await resolveEmail(token.accessToken)

        // Step 3: Create account with Gmail defaults from AppConstants
        let account = Account(
            email: email,
            displayName: email.components(separatedBy: "@").first ?? email,
            imapHost: AppConstants.gmailImapHost,
            imapPort: AppConstants.gmailImapPort,
            smtpHost: AppConstants.gmailSmtpHost,
            smtpPort: AppConstants.gmailSmtpPort
        )

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

        // PARTIAL SCOPE: IMAP/SMTP validation deferred (FR-ACCT-01, FR-OB-01 step 2).
        // Blocked on Data/Network/IMAPClient (not yet built — IOS-F-05).
        // Real implementation MUST: connect to imap.gmail.com:993 with XOAUTH2,
        // send LOGIN + NOOP, and fail account creation if unreachable.
        // For V1, this step succeeds unconditionally.

        return account
    }

    public func removeAccount(id: String) async throws -> Bool {
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
        // Step 1: Re-authenticate via OAuth
        let newToken = try await oauthManager.authenticate()

        // Step 2: Update Keychain with new token
        try await keychainManager.update(newToken, for: id)

        // Step 3: Fetch and re-activate account
        let accounts = try await repository.getAccounts()
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw AccountError.notFound(id)
        }

        account.isActive = true
        try await repository.updateAccount(account)
    }

    // MARK: - Private

    /// Default email resolver that calls Google UserInfo API.
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
