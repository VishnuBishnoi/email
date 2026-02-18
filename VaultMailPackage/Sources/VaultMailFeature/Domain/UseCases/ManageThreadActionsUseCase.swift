import Foundation

/// Write-side use case for single and batch thread actions.
///
/// Per Foundation FR-FOUND-01, views **MUST** call domain use cases only —
/// never repositories directly. This use case delegates to
/// EmailRepositoryProtocol for thread mutations and wraps errors
/// as ThreadListError.actionFailed.
///
/// After local SwiftData changes, pushes to IMAP server (optimistic UI).
/// IMAP failures are logged but don't undo local changes; next sync reconciles.
///
/// Spec ref: FR-TL-03
@MainActor
public protocol ManageThreadActionsUseCaseProtocol {
    /// Archive a single thread (move to Archive folder).
    func archiveThread(id: String) async throws
    /// Delete a single thread (move to Trash folder).
    func deleteThread(id: String) async throws
    /// Toggle read/unread status for a thread.
    func toggleReadStatus(threadId: String) async throws
    /// Toggle star status for a thread.
    func toggleStarStatus(threadId: String) async throws
    /// Move a thread to a different folder.
    func moveThread(id: String, toFolderId: String) async throws
    /// Toggle star status for a single email (message-level).
    func toggleEmailStarStatus(emailId: String) async throws

    // MARK: - Batch Actions

    /// Archive multiple threads.
    func archiveThreads(ids: [String]) async throws
    /// Delete multiple threads.
    func deleteThreads(ids: [String]) async throws
    /// Mark multiple threads as read.
    func markThreadsRead(ids: [String]) async throws
    /// Mark multiple threads as unread.
    func markThreadsUnread(ids: [String]) async throws
    /// Star multiple threads.
    func starThreads(ids: [String]) async throws
    /// Move multiple threads to a folder.
    func moveThreads(ids: [String], toFolderId: String) async throws
}

/// Default implementation of ManageThreadActionsUseCaseProtocol.
///
/// Each method:
/// 1. Performs the local SwiftData mutation via EmailRepositoryProtocol
/// 2. Pushes the change to IMAP (best-effort, failures logged)
///
/// IMAP sync uses optimistic UI — local state persists even if server push fails.
/// The next sync pull will reconcile any inconsistencies.
@MainActor
public final class ManageThreadActionsUseCase: ManageThreadActionsUseCaseProtocol {

    private let repository: EmailRepositoryProtocol
    private let connectionProvider: ConnectionProviding
    private let accountRepository: AccountRepositoryProtocol
    private let keychainManager: KeychainManagerProtocol

    /// Creates a ManageThreadActionsUseCase.
    ///
    /// - Parameters:
    ///   - repository: Email data access layer.
    ///   - connectionProvider: IMAP connection pool for server sync.
    ///   - accountRepository: Account lookup for IMAP credentials.
    ///   - keychainManager: OAuth token storage.
    public init(
        repository: EmailRepositoryProtocol,
        connectionProvider: ConnectionProviding,
        accountRepository: AccountRepositoryProtocol,
        keychainManager: KeychainManagerProtocol
    ) {
        self.repository = repository
        self.connectionProvider = connectionProvider
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
    }

    // MARK: - Single Actions

    public func archiveThread(id: String) async throws {
        // Capture folder info BEFORE local change
        let imapOps = await captureEmailFolderInfo(threadId: id)

        // Perform local change
        do {
            try await repository.archiveThread(id: id)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Resolve archive behavior based on provider (FR-MPROV-12).
        // Gmail uses label semantics (remove from INBOX = archive).
        // Other providers need COPY to Archive + EXPUNGE from source.
        let archivePath = await resolveArchivePath(for: imapOps)
        if let archivePath {
            await syncMoveToServer(
                operations: imapOps,
                destinationImapPath: archivePath
            )
        } else {
            // Gmail label behavior: just EXPUNGE from INBOX (the "remove label" approach)
            await syncExpungeFromInbox(operations: imapOps)
        }
    }

    public func deleteThread(id: String) async throws {
        // Capture folder info BEFORE local change
        let imapOps = await captureEmailFolderInfo(threadId: id)

        // Perform local change
        do {
            try await repository.deleteThread(id: id)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Resolve trash folder path based on provider
        let trashPath = await resolveTrashPath(for: imapOps)
        await syncMoveToServer(
            operations: imapOps,
            destinationImapPath: trashPath
        )
    }

    public func toggleReadStatus(threadId: String) async throws {
        // Determine current state before toggling
        let wasUnread: Bool
        do {
            let thread = try await repository.getThread(id: threadId)
            wasUnread = (thread?.unreadCount ?? 0) > 0
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Perform local change
        do {
            try await repository.toggleReadStatus(threadId: threadId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Push to IMAP: add or remove \Seen flag
        await syncFlagChange(
            threadId: threadId,
            addFlags: wasUnread ? ["\\Seen"] : [],
            removeFlags: wasUnread ? [] : ["\\Seen"]
        )
    }

    public func toggleStarStatus(threadId: String) async throws {
        // Determine current state before toggling
        let wasStarred: Bool
        do {
            let thread = try await repository.getThread(id: threadId)
            wasStarred = thread?.isStarred ?? false
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Perform local change
        do {
            try await repository.toggleStarStatus(threadId: threadId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Push to IMAP: add or remove \Flagged
        await syncFlagChange(
            threadId: threadId,
            addFlags: wasStarred ? [] : ["\\Flagged"],
            removeFlags: wasStarred ? ["\\Flagged"] : []
        )
    }

    public func moveThread(id: String, toFolderId: String) async throws {
        // Capture folder info BEFORE local change
        let imapOps = await captureEmailFolderInfo(threadId: id)

        // Resolve destination folder imapPath
        let destImapPath: String?
        do {
            let accountId = imapOps.first?.accountId ?? ""
            let folders = try await repository.getFolders(accountId: accountId)
            destImapPath = folders.first(where: { $0.id == toFolderId })?.imapPath
        } catch {
            destImapPath = nil
        }

        // Perform local change
        do {
            try await repository.moveThread(id: id, toFolderId: toFolderId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Push to IMAP: COPY to destination, EXPUNGE from source
        if let destImapPath {
            await syncMoveToServer(
                operations: imapOps,
                destinationImapPath: destImapPath
            )
        }
    }

    public func toggleEmailStarStatus(emailId: String) async throws {
        // Capture current state before toggle
        let wasStarred: Bool
        do {
            let email = try await repository.getEmail(id: emailId)
            wasStarred = email?.isStarred ?? false
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Perform local change
        do {
            try await repository.toggleEmailStarStatus(emailId: emailId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Push to IMAP: add or remove \Flagged for this single email
        await syncEmailFlagChange(
            emailId: emailId,
            addFlags: wasStarred ? [] : ["\\Flagged"],
            removeFlags: wasStarred ? ["\\Flagged"] : []
        )
    }

    // MARK: - Batch Actions

    public func archiveThreads(ids: [String]) async throws {
        // Capture IMAP info for all threads before local change
        var allOps: [String: [IMAPOperation]] = [:]
        for id in ids {
            allOps[id] = await captureEmailFolderInfo(threadId: id)
        }

        do {
            try await repository.archiveThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        // Push each thread to IMAP using provider-aware archive path
        for id in ids {
            let ops = allOps[id] ?? []
            let archivePath = await resolveArchivePath(for: ops)
            if let archivePath {
                await syncMoveToServer(operations: ops, destinationImapPath: archivePath)
            } else {
                await syncExpungeFromInbox(operations: ops)
            }
        }
    }

    public func deleteThreads(ids: [String]) async throws {
        var allOps: [String: [IMAPOperation]] = [:]
        for id in ids {
            allOps[id] = await captureEmailFolderInfo(threadId: id)
        }

        do {
            try await repository.deleteThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        for id in ids {
            let ops = allOps[id] ?? []
            let trashPath = await resolveTrashPath(for: ops)
            await syncMoveToServer(operations: ops, destinationImapPath: trashPath)
        }
    }

    public func markThreadsRead(ids: [String]) async throws {
        do {
            try await repository.markThreadsRead(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        for id in ids {
            await syncFlagChange(threadId: id, addFlags: ["\\Seen"], removeFlags: [])
        }
    }

    public func markThreadsUnread(ids: [String]) async throws {
        do {
            try await repository.markThreadsUnread(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        for id in ids {
            await syncFlagChange(threadId: id, addFlags: [], removeFlags: ["\\Seen"])
        }
    }

    public func starThreads(ids: [String]) async throws {
        do {
            try await repository.starThreads(ids: ids)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        for id in ids {
            await syncFlagChange(threadId: id, addFlags: ["\\Flagged"], removeFlags: [])
        }
    }

    public func moveThreads(ids: [String], toFolderId: String) async throws {
        // Capture IMAP info and resolve destination before local change
        var allOps: [String: [IMAPOperation]] = [:]
        var destImapPath: String?
        for id in ids {
            let ops = await captureEmailFolderInfo(threadId: id)
            allOps[id] = ops
            // Resolve destination once from first thread's account
            if destImapPath == nil, let accountId = ops.first?.accountId {
                destImapPath = try? await repository.getFolders(accountId: accountId)
                    .first(where: { $0.id == toFolderId })?.imapPath
            }
        }

        do {
            try await repository.moveThreads(ids: ids, toFolderId: toFolderId)
        } catch {
            throw ThreadListError.actionFailed(error.localizedDescription)
        }

        if let destImapPath {
            for id in ids {
                await syncMoveToServer(
                    operations: allOps[id] ?? [],
                    destinationImapPath: destImapPath
                )
            }
        }
    }

    // MARK: - IMAP Sync Helpers

    /// Info needed for IMAP operations on a single email in a folder.
    private struct IMAPOperation {
        let accountId: String
        let imapUID: UInt32
        let sourceFolderImapPath: String
    }

    /// Captures the IMAP UIDs and folder paths for all emails in a thread.
    ///
    /// Must be called BEFORE the local change since local mutations may
    /// remove or reassign folder associations.
    private func captureEmailFolderInfo(threadId: String) async -> [IMAPOperation] {
        guard let thread = try? await repository.getThread(id: threadId) else { return [] }

        var ops: [IMAPOperation] = []
        for email in thread.emails {
            for ef in email.emailFolders {
                // Skip locally-created emails (imapUID == 0) — no server record to update
                guard ef.imapUID > 0,
                      let folderPath = ef.folder?.imapPath,
                      !folderPath.isEmpty else { continue }
                ops.append(IMAPOperation(
                    accountId: email.accountId,
                    imapUID: UInt32(ef.imapUID),
                    sourceFolderImapPath: folderPath
                ))
            }
        }
        return ops
    }

    /// Pushes a flag change to IMAP for all emails in a thread.
    ///
    /// Iterates each email's folder associations and calls `storeFlags`.
    /// Errors are logged but not thrown (optimistic UI).
    private func syncFlagChange(
        threadId: String,
        addFlags: [String],
        removeFlags: [String]
    ) async {
        guard !addFlags.isEmpty || !removeFlags.isEmpty else { return }
        guard let thread = try? await repository.getThread(id: threadId) else { return }

        for email in thread.emails {
            for ef in email.emailFolders {
                // Skip locally-created emails
                guard ef.imapUID > 0,
                      let folderPath = ef.folder?.imapPath,
                      !folderPath.isEmpty else { continue }

                let uid = UInt32(ef.imapUID)
                let accountId = email.accountId

                do {
                    let client = try await getIMAPClient(accountId: accountId)
                    defer { Task { await self.connectionProvider.checkinConnection(client, accountId: accountId) } }

                    _ = try await client.selectFolder(folderPath)
                    try await client.storeFlags(uid: uid, add: addFlags, remove: removeFlags)
                } catch {
                    NSLog("[ThreadActions] IMAP flag sync failed for UID \(uid) in \(folderPath): \(error)")
                }
            }
        }
    }

    /// Pushes a flag change to IMAP for a single email.
    ///
    /// Similar to `syncFlagChange` but operates on one email instead of a whole thread.
    /// Used for single-email operations like toggling star status.
    /// Errors are logged but not thrown (optimistic UI).
    private func syncEmailFlagChange(
        emailId: String,
        addFlags: [String],
        removeFlags: [String]
    ) async {
        guard !addFlags.isEmpty || !removeFlags.isEmpty else { return }
        guard let email = try? await repository.getEmail(id: emailId) else { return }

        for ef in email.emailFolders {
            guard ef.imapUID > 0,
                  let folderPath = ef.folder?.imapPath,
                  !folderPath.isEmpty else { continue }

            let uid = UInt32(ef.imapUID)
            let accountId = email.accountId

            do {
                let client = try await getIMAPClient(accountId: accountId)
                defer { Task { await self.connectionProvider.checkinConnection(client, accountId: accountId) } }

                _ = try await client.selectFolder(folderPath)
                try await client.storeFlags(uid: uid, add: addFlags, remove: removeFlags)
            } catch {
                NSLog("[ThreadActions] IMAP email flag sync failed for UID \(uid) in \(folderPath): \(error)")
            }
        }
    }

    /// Pushes a move (COPY + EXPUNGE) to IMAP for the given operations.
    ///
    /// Groups operations by (account, source folder) for efficiency,
    /// then performs COPY to destination followed by EXPUNGE from source.
    /// Errors are logged but not thrown (optimistic UI).
    private func syncMoveToServer(
        operations: [IMAPOperation],
        destinationImapPath: String
    ) async {
        guard !operations.isEmpty else { return }

        // Group operations by (accountId, sourceFolder) for efficiency
        var grouped: [String: [(accountId: String, uid: UInt32)]] = [:]
        for op in operations {
            let key = "\(op.accountId)|\(op.sourceFolderImapPath)"
            grouped[key, default: []].append((op.accountId, op.imapUID))
        }

        for (key, entries) in grouped {
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let accountId = String(parts[0])
            let sourcePath = String(parts[1])
            let uids = entries.map(\.uid)

            // Skip if source and destination are the same
            guard sourcePath != destinationImapPath else { continue }

            do {
                let client = try await getIMAPClient(accountId: accountId)
                defer { Task { await self.connectionProvider.checkinConnection(client, accountId: accountId) } }

                _ = try await client.selectFolder(sourcePath)
                try await client.copyMessages(uids: uids, to: destinationImapPath)
                try await client.expungeMessages(uids: uids)
            } catch {
                NSLog("[ThreadActions] IMAP move sync failed from \(sourcePath) to \(destinationImapPath): \(error)")
            }
        }
    }

    /// Resolves the archive IMAP path for the given operations' account.
    ///
    /// Returns `nil` for Gmail (which uses label semantics — no COPY needed).
    /// Returns the Archive folder path for other providers.
    private func resolveArchivePath(for operations: [IMAPOperation]) async -> String? {
        guard let accountId = operations.first?.accountId else { return nil }
        guard let account = try? await findAccount(id: accountId) else { return nil }

        let providerConfig = ProviderRegistry.provider(for: account.resolvedProvider)

        // Gmail uses label semantics — archiving = removing from INBOX label.
        // No COPY to Archive needed.
        if providerConfig?.archiveBehavior == .gmailLabel {
            return nil
        }

        // For other providers, find the Archive folder
        guard let folders = try? await repository.getFolders(accountId: accountId) else {
            return "Archive" // Reasonable default
        }
        return folders.first(where: { $0.folderType == FolderType.archive.rawValue })?.imapPath ?? "Archive"
    }

    /// Resolves the Trash folder IMAP path for the given operations' account.
    private func resolveTrashPath(for operations: [IMAPOperation]) async -> String {
        guard let accountId = operations.first?.accountId else { return "Trash" }

        guard let folders = try? await repository.getFolders(accountId: accountId) else {
            return "Trash" // Provider-agnostic fallback
        }
        return folders.first(where: { $0.folderType == FolderType.trash.rawValue })?.imapPath ?? "Trash"
    }

    /// Expunges emails from INBOX without copying (Gmail label semantics).
    ///
    /// On Gmail, "archive" means removing the INBOX label. The email stays in All Mail.
    /// We just need to mark as \Deleted + EXPUNGE from INBOX.
    private func syncExpungeFromInbox(operations: [IMAPOperation]) async {
        let inboxOps = operations.filter { $0.sourceFolderImapPath.uppercased() == "INBOX" }
        guard !inboxOps.isEmpty else { return }

        var grouped: [String: [UInt32]] = [:]
        for op in inboxOps {
            grouped[op.accountId, default: []].append(op.imapUID)
        }

        for (accountId, uids) in grouped {
            do {
                let client = try await getIMAPClient(accountId: accountId)
                defer { Task { await self.connectionProvider.checkinConnection(client, accountId: accountId) } }

                _ = try await client.selectFolder("INBOX")
                try await client.expungeMessages(uids: uids)
            } catch {
                NSLog("[ThreadActions] IMAP expunge from INBOX failed: \(error)")
            }
        }
    }

    private func findAccount(id: String) async throws -> Account {
        let accounts = try await accountRepository.getAccounts()
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw ThreadListError.actionFailed("Account not found: \(id)")
        }
        return account
    }

    /// Gets an authenticated IMAP client from the connection pool.
    ///
    /// Resolves credentials (OAuth or app password) from Keychain and uses
    /// provider-aware security settings from the account model.
    private func getIMAPClient(accountId: String) async throws -> any IMAPClientProtocol {
        let account = try await findAccount(id: accountId)
        let credential = try await resolveIMAPCredential(for: account)

        return try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: credential
        )
    }

    /// Resolves IMAP credential from Keychain based on account auth type.
    private func resolveIMAPCredential(for account: Account) async throws -> IMAPCredential {
        let resolver = CredentialResolver(
            keychainManager: keychainManager,
            accountRepository: accountRepository
        )
        do {
            return try await resolver.resolveIMAPCredential(for: account, refreshIfNeeded: true)
        } catch {
            throw ThreadListError.actionFailed("Credential resolution failed: \(error.localizedDescription)")
        }
    }
}
