import Foundation

/// Use case for fetching a thread with its emails for the detail view.
///
/// When an email's body is `nil` (headers-only sync for non-inbox folders),
/// this use case lazily fetches the body from IMAP on demand.
///
/// Per FR-FOUND-01, views MUST call use cases, not repositories.
///
/// Spec ref: Email Detail FR-ED-01
@MainActor
public protocol FetchEmailDetailUseCaseProtocol {
    /// Fetch a thread by ID with all emails.
    func fetchThread(threadId: String) async throws -> Thread

    /// Fetch missing email bodies from IMAP for emails that were synced headers-only.
    /// Updates the Email models in SwiftData and returns the count of bodies fetched.
    @discardableResult
    func fetchBodiesIfNeeded(for emails: [Email]) async throws -> Int

    // MARK: - Trusted Senders (FR-ED-04)

    /// Get all trusted sender email addresses.
    func getAllTrustedSenderEmails() async throws -> Set<String>
    /// Save a sender as trusted (always load remote images).
    func saveTrustedSender(email: String) async throws
}

@MainActor
public final class FetchEmailDetailUseCase: FetchEmailDetailUseCaseProtocol {
    private let repository: EmailRepositoryProtocol
    private let connectionProvider: ConnectionProviding?
    private let accountRepository: AccountRepositoryProtocol?
    private let keychainManager: KeychainManagerProtocol?

    public init(
        repository: EmailRepositoryProtocol,
        connectionProvider: ConnectionProviding? = nil,
        accountRepository: AccountRepositoryProtocol? = nil,
        keychainManager: KeychainManagerProtocol? = nil
    ) {
        self.repository = repository
        self.connectionProvider = connectionProvider
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
    }

    public func fetchThread(threadId: String) async throws -> Thread {
        do {
            guard let thread = try await repository.getThread(id: threadId) else {
                throw EmailDetailError.threadNotFound(id: threadId)
            }
            return thread
        } catch let error as EmailDetailError {
            throw error
        } catch {
            throw EmailDetailError.loadFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func fetchBodiesIfNeeded(for emails: [Email]) async throws -> Int {
        // Find emails with no body content
        let needsBodies = emails.filter { $0.bodyPlain == nil && $0.bodyHTML == nil }
        guard !needsBodies.isEmpty else { return 0 }

        guard let connectionProvider, let accountRepository, let keychainManager else {
            return 0
        }

        let credentialResolver = CredentialResolver(
            keychainManager: keychainManager,
            accountRepository: accountRepository
        )

        // Group emails by account for efficient connection reuse
        let emailsByAccount = Dictionary(grouping: needsBodies) { $0.accountId }
        var fetchedCount = 0

        for (accountId, accountEmails) in emailsByAccount {
            let accounts = try await accountRepository.getAccounts()
            guard let account = accounts.first(where: { $0.id == accountId }) else { continue }

            let imapCredential: IMAPCredential
            do {
                imapCredential = try await credentialResolver.resolveIMAPCredential(
                    for: account,
                    refreshIfNeeded: true
                )
            } catch {
                NSLog("[FetchDetail] Credential resolution failed for \(accountId): \(error)")
                continue
            }

            let client = try await connectionProvider.checkoutConnection(
                accountId: account.id,
                host: account.imapHost,
                port: account.imapPort,
                security: account.resolvedImapSecurity,
                credential: imapCredential
            )

            defer {
                Task {
                    await connectionProvider.checkinConnection(client, accountId: account.id)
                }
            }

            // Group by folder so we can SELECT once per folder
            let emailsByFolder = groupEmailsByFolder(accountEmails)

            for (folderPath, emailFolderPairs) in emailsByFolder {
                do {
                    _ = try await client.selectFolder(folderPath)

                    let uids = emailFolderPairs.map { UInt32($0.imapUID) }
                    let bodies = try await client.fetchBodies(uids: uids)
                    let bodyMap = Dictionary(uniqueKeysWithValues: bodies.map { ($0.uid, $0) })

                    for (email, imapUID) in emailFolderPairs {
                        guard let body = bodyMap[UInt32(imapUID)] else { continue }
                        email.bodyPlain = body.plainText
                        email.bodyHTML = body.htmlText

                        // Update snippet if missing
                        if email.snippet == nil, let plainText = body.plainText, !plainText.isEmpty {
                            let cleaned = plainText
                                .replacingOccurrences(of: "\r\n", with: " ")
                                .replacingOccurrences(of: "\n", with: " ")
                                .trimmingCharacters(in: .whitespaces)
                            email.snippet = String(cleaned.prefix(150))
                        }
                        fetchedCount += 1
                    }
                } catch {
                    NSLog("[FetchDetail] Failed to fetch bodies from \(folderPath): \(error)")
                    continue
                }
            }
        }

        if fetchedCount > 0 {
            try await repository.flushChanges()
        }

        return fetchedCount
    }

    public func getAllTrustedSenderEmails() async throws -> Set<String> {
        let senders = try await repository.getAllTrustedSenders()
        return Set(senders.map(\.senderEmail))
    }

    public func saveTrustedSender(email senderEmail: String) async throws {
        let sender = TrustedSender(senderEmail: senderEmail)
        try await repository.saveTrustedSender(sender)
    }

    // MARK: - Private

    /// Groups emails by their folder IMAP path, returning (email, imapUID) pairs.
    private func groupEmailsByFolder(_ emails: [Email]) -> [String: [(email: Email, imapUID: Int)]] {
        var result: [String: [(email: Email, imapUID: Int)]] = [:]
        for email in emails {
            // Find the first EmailFolder with a valid folder path
            guard let emailFolder = email.emailFolders.first(where: { $0.folder != nil }),
                  let folder = emailFolder.folder else { continue }
            result[folder.imapPath, default: []].append((email: email, imapUID: emailFolder.imapUID))
        }
        return result
    }
}
