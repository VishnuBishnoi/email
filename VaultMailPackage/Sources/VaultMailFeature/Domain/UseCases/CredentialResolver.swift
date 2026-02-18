import Foundation

/// Shared utility for resolving IMAP and SMTP credentials from Keychain.
///
/// Encapsulates the common pattern of:
/// 1. Retrieving `AccountCredential` from Keychain
/// 2. Optionally refreshing expired OAuth tokens
/// 3. Mapping to `IMAPCredential` or `SMTPCredential`
///
/// Replaces duplicated credential resolution logic across 5 use cases.
///
/// Spec ref: FR-MPROV-06 (Multi-provider credential handling)
@MainActor
public struct CredentialResolver {

    private let keychainManager: KeychainManagerProtocol
    private let accountRepository: AccountRepositoryProtocol?

    /// Creates a credential resolver.
    /// - Parameters:
    ///   - keychainManager: Keychain storage for credentials.
    ///   - accountRepository: Account repository for OAuth token refresh.
    ///     Pass `nil` to skip refresh (e.g. for IDLE connections).
    public init(
        keychainManager: KeychainManagerProtocol,
        accountRepository: AccountRepositoryProtocol? = nil
    ) {
        self.keychainManager = keychainManager
        self.accountRepository = accountRepository
    }

    // MARK: - IMAP Credential Resolution

    /// Resolves IMAP credentials for an account, optionally refreshing OAuth tokens.
    ///
    /// For OAuth accounts with `refreshIfNeeded == true`:
    /// - If the token is expired or near expiry, attempts refresh via `accountRepository`
    /// - Falls back to the existing token if refresh fails and token isn't fully expired
    /// - Throws if the token is expired and refresh fails
    ///
    /// For app-password accounts:
    /// - Returns `.plain` credential directly (no refresh needed)
    ///
    /// - Parameters:
    ///   - account: The account to resolve credentials for.
    ///   - refreshIfNeeded: Whether to refresh expired OAuth tokens. Default `true`.
    /// - Throws: `CredentialResolverError` if no credentials found or refresh fails.
    /// - Returns: An `IMAPCredential` ready for IMAP connection.
    public func resolveIMAPCredential(
        for account: Account,
        refreshIfNeeded: Bool = true
    ) async throws -> IMAPCredential {
        guard let credential = try await keychainManager.retrieveCredential(for: account.id) else {
            throw CredentialResolverError.noCredentials(account.id)
        }

        switch credential {
        case .password(let password):
            return .plain(username: account.email, password: password)

        case .oauth(let token):
            let resolvedToken = try await resolveOAuthToken(
                token,
                accountId: account.id,
                refreshIfNeeded: refreshIfNeeded
            )
            return .xoauth2(email: account.email, accessToken: resolvedToken.accessToken)
        }
    }

    /// Resolves SMTP credentials for an account, optionally refreshing OAuth tokens.
    ///
    /// Same logic as `resolveIMAPCredential` but returns `SMTPCredential`.
    public func resolveSMTPCredential(
        for account: Account,
        refreshIfNeeded: Bool = true
    ) async throws -> SMTPCredential {
        guard let credential = try await keychainManager.retrieveCredential(for: account.id) else {
            throw CredentialResolverError.noCredentials(account.id)
        }

        switch credential {
        case .password(let password):
            return .plain(username: account.email, password: password)

        case .oauth(let token):
            let resolvedToken = try await resolveOAuthToken(
                token,
                accountId: account.id,
                refreshIfNeeded: refreshIfNeeded
            )
            return .xoauth2(email: account.email, accessToken: resolvedToken.accessToken)
        }
    }

    /// Resolves both IMAP and SMTP credentials in a single call.
    ///
    /// More efficient than calling both methods separately when you need both
    /// (e.g. ComposeEmailUseCase sends via SMTP then APPENDs via IMAP).
    public func resolveBothCredentials(
        for account: Account,
        refreshIfNeeded: Bool = true
    ) async throws -> (imap: IMAPCredential, smtp: SMTPCredential) {
        guard let credential = try await keychainManager.retrieveCredential(for: account.id) else {
            throw CredentialResolverError.noCredentials(account.id)
        }

        switch credential {
        case .password(let password):
            return (
                imap: .plain(username: account.email, password: password),
                smtp: .plain(username: account.email, password: password)
            )

        case .oauth(let token):
            let resolvedToken = try await resolveOAuthToken(
                token,
                accountId: account.id,
                refreshIfNeeded: refreshIfNeeded
            )
            return (
                imap: .xoauth2(email: account.email, accessToken: resolvedToken.accessToken),
                smtp: .xoauth2(email: account.email, accessToken: resolvedToken.accessToken)
            )
        }
    }

    // MARK: - Private

    /// Resolves an OAuth token, refreshing if needed and possible.
    private func resolveOAuthToken(
        _ token: OAuthToken,
        accountId: String,
        refreshIfNeeded: Bool
    ) async throws -> OAuthToken {
        guard refreshIfNeeded, token.isExpired || token.isNearExpiry else {
            return token
        }

        guard let repo = accountRepository else {
            // No repository available for refresh — use token as-is if not fully expired
            if !token.isExpired {
                return token
            }
            throw CredentialResolverError.tokenExpired(accountId)
        }

        do {
            return try await repo.refreshToken(for: accountId)
        } catch {
            // If refresh fails but token isn't fully expired, use existing
            if !token.isExpired {
                return token
            }
            throw CredentialResolverError.tokenRefreshFailed(
                accountId: accountId,
                underlying: error
            )
        }
    }
}

/// Errors from credential resolution.
public enum CredentialResolverError: Error, LocalizedError {
    case noCredentials(String)
    case tokenExpired(String)
    case tokenRefreshFailed(accountId: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .noCredentials(let id):
            return "No credentials found for account \(id)."
        case .tokenExpired(let id):
            return "OAuth token expired for account \(id) and refresh is unavailable."
        case .tokenRefreshFailed(let id, let error):
            return "Token refresh failed for account \(id): \(error.localizedDescription)"
        }
    }
}
