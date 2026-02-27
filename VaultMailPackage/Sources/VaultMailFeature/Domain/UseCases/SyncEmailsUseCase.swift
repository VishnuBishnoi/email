import Foundation
import CryptoKit

/// Account-level sync entrypoint options (v1.3.0 contract).
public enum SyncAccountOptions: Sendable, Equatable {
    /// Legacy full-account sync behavior.
    case full
    /// Initial fast bootstrap sync (Inbox-first render path).
    case initialFast
    /// Forward incremental sync across all syncable folders.
    case incremental
}

/// Folder-level sync direction/options (v1.3.0 contract).
public enum SyncFolderOptions: Sendable, Equatable {
    /// Forward incremental sync for new arrivals.
    case incremental
    /// Backward catch-up sync for historical messages.
    case catchUp
}

/// Structured sync result for v1.3.0 API migration.
public struct SyncResult {
    /// Newly persisted emails for this invocation.
    public let newEmails: [Email]
    /// Inbox emails persisted during initial-fast stage.
    public let inboxEmails: [Email]
    /// Account-level mode used to produce this result.
    public let accountOptions: SyncAccountOptions?
    /// Folder-level mode used to produce this result.
    public let folderOptions: SyncFolderOptions?

    public init(
        newEmails: [Email],
        inboxEmails: [Email] = [],
        accountOptions: SyncAccountOptions? = nil,
        folderOptions: SyncFolderOptions? = nil
    ) {
        self.newEmails = newEmails
        self.inboxEmails = inboxEmails
        self.accountOptions = accountOptions
        self.folderOptions = folderOptions
    }
}

/// Domain use case for syncing emails from IMAP to SwiftData.
///
/// On-demand sync triggered by view load and pull-to-refresh.
/// Orchestrates: OAuth token refresh → IMAP connection → fetch → persist.
///
/// Spec ref: Email Sync spec FR-SYNC-01, FR-SYNC-09
@MainActor
public protocol SyncEmailsUseCaseProtocol {
    /// Unified account sync contract (v1.3.0).
    @discardableResult
    func syncAccount(accountId: String, options: SyncAccountOptions) async throws -> SyncResult

    /// Unified folder sync contract (v1.3.0).
    @discardableResult
    func syncFolder(accountId: String, folderId: String, options: SyncFolderOptions) async throws -> SyncResult

    /// Pause historical catch-up for account folders.
    func pauseCatchUp(accountId: String) async

    /// Resume historical catch-up for account folders.
    func resumeCatchUp(accountId: String) async

    /// Full sync for an account: folders + emails for all syncable folders.
    /// Returns all newly synced emails so callers can enqueue them for AI processing.
    @discardableResult
    func syncAccount(accountId: String) async throws -> [Email]

    /// Full sync with inbox-first priority for fast initial load.
    ///
    /// Syncs folders first, then inbox, then calls `onInboxSynced` so the UI
    /// can refresh immediately. Remaining folders sync after.
    /// Returns all newly synced emails (inbox + remaining).
    @discardableResult
    func syncAccountInboxFirst(
        accountId: String,
        onInboxSynced: @MainActor (_ inboxEmails: [Email]) async -> Void
    ) async throws -> [Email]

    /// Incremental sync for a single folder.
    /// Returns newly synced emails so callers can enqueue them for AI processing.
    @discardableResult
    func syncFolder(accountId: String, folderId: String) async throws -> [Email]
}

extension SyncEmailsUseCaseProtocol {
    public func pauseCatchUp(accountId: String) async {}

    public func resumeCatchUp(accountId: String) async {}

    @discardableResult
    public func syncAccount(accountId: String) async throws -> [Email] {
        let result = try await syncAccount(accountId: accountId, options: .full)
        return result.newEmails
    }

    @discardableResult
    public func syncAccountInboxFirst(
        accountId: String,
        onInboxSynced: @MainActor (_ inboxEmails: [Email]) async -> Void
    ) async throws -> [Email] {
        let result = try await syncAccount(accountId: accountId, options: .initialFast)
        await onInboxSynced(result.inboxEmails)
        return result.newEmails
    }

    @discardableResult
    public func syncFolder(accountId: String, folderId: String) async throws -> [Email] {
        let result = try await syncFolder(
            accountId: accountId,
            folderId: folderId,
            options: .incremental
        )
        return result.newEmails
    }
}

/// Abstraction for obtaining IMAP connections. ConnectionPool conforms
/// in production; tests inject a mock that returns MockIMAPClient.
///
/// Supports two checkout signatures:
/// - **Multi-provider** (`security:` + `credential:`): Used by code that has
///   already resolved the account's provider config.
/// - **Legacy** (`email:` + `accessToken:`): Backward-compatible convenience
///   that defaults to TLS + XOAUTH2. Existing call sites can migrate gradually.
public protocol ConnectionProviding: Sendable {

    /// Checks out a connection with explicit security mode and credential.
    ///
    /// Spec ref: FR-MPROV-05 (STARTTLS), FR-MPROV-03 (SASL PLAIN)
    func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        security: ConnectionSecurity,
        credential: IMAPCredential
    ) async throws -> any IMAPClientProtocol

    /// Checks out a connection using implicit TLS + XOAUTH2 (backward compat).
    func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        email: String,
        accessToken: String
    ) async throws -> any IMAPClientProtocol

    func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async
}

/// Default implementation: legacy convenience delegates to multi-provider method.
extension ConnectionProviding {
    public func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        email: String,
        accessToken: String
    ) async throws -> any IMAPClientProtocol {
        try await checkoutConnection(
            accountId: accountId,
            host: host,
            port: port,
            security: .tls,
            credential: .xoauth2(email: email, accessToken: accessToken)
        )
    }
}

/// Make ConnectionPool conform to ConnectionProviding.
extension ConnectionPool: ConnectionProviding {
    public func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        security: ConnectionSecurity,
        credential: IMAPCredential
    ) async throws -> any IMAPClientProtocol {
        try await self.checkout(
            accountId: accountId,
            host: host,
            port: port,
            security: security,
            credential: credential
        )
    }

    public func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async {
        if let imapClient = client as? IMAPClient {
            self.checkin(imapClient, accountId: accountId)
        }
    }
}

/// Default implementation that bridges IMAP client and SwiftData persistence.
@MainActor
public final class SyncEmailsUseCase: SyncEmailsUseCaseProtocol {
    private struct StageCAllocation {
        let folder: Folder
        let direction: SyncDirection
        let maxHeaders: Int
    }

    private enum SyncDirection {
        case full
        case forward
        case backward
    }

    private let accountRepository: AccountRepositoryProtocol
    private let emailRepository: EmailRepositoryProtocol
    private let keychainManager: KeychainManagerProtocol
    private let connectionProvider: ConnectionProviding
    private let folderSyncCoordinator: FolderSyncCoordinator
    private var catchUpTasks: [String: Task<Void, Never>] = [:]

    /// Batch size for IMAP FETCH commands to avoid oversized responses.
    private let fetchBatchSize = 50

    public init(
        accountRepository: AccountRepositoryProtocol,
        emailRepository: EmailRepositoryProtocol,
        keychainManager: KeychainManagerProtocol,
        connectionPool: ConnectionProviding,
        folderSyncCoordinator: FolderSyncCoordinator = FolderSyncCoordinator()
    ) {
        self.accountRepository = accountRepository
        self.emailRepository = emailRepository
        self.keychainManager = keychainManager
        self.connectionProvider = connectionPool
        self.folderSyncCoordinator = folderSyncCoordinator
    }

    // MARK: - Public API

    @discardableResult
    public func syncAccount(accountId: String, options: SyncAccountOptions) async throws -> SyncResult {
        switch options {
        case .full:
            let emails = try await syncAccount(accountId: accountId)
            return SyncResult(
                newEmails: emails,
                accountOptions: options
            )
        case .incremental:
            let emails = try await syncAccountIncremental(accountId: accountId)
            return SyncResult(
                newEmails: emails,
                accountOptions: options
            )
        case .initialFast:
            var inboxEmails: [Email] = []
            let emails = try await syncAccountInboxFirst(accountId: accountId) { syncedInbox in
                inboxEmails = syncedInbox
            }
            return SyncResult(
                newEmails: emails,
                inboxEmails: inboxEmails,
                accountOptions: .initialFast
            )
        }
    }

    @discardableResult
    public func syncFolder(
        accountId: String,
        folderId: String,
        options: SyncFolderOptions
    ) async throws -> SyncResult {
        let emails = try await syncFolderWithOptions(
            accountId: accountId,
            folderId: folderId,
            options: options
        )
        return SyncResult(
            newEmails: emails,
            folderOptions: options
        )
    }

    @discardableResult
    public func syncAccount(accountId: String) async throws -> [Email] {
        NSLog("[Sync] syncAccount started for \(accountId)")
        let account = try await findAccount(id: accountId)
        NSLog("[Sync] Found account: \(account.email), host: \(account.imapHost):\(account.imapPort)")

        NSLog("[Sync] Resolving credentials...")
        let imapCredential = try await resolveIMAPCredential(for: account)
        NSLog("[Sync] Credentials resolved")

        NSLog("[Sync] Checking out IMAP connection...")
        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: imapCredential
        )
        NSLog("[Sync] IMAP connection established")

        do {
            // 1. Sync folders
            NSLog("[Sync] Listing IMAP folders...")
            let imapFolders = try await client.listFolders()
            NSLog("[Sync] Found \(imapFolders.count) IMAP folders")
            let syncableFolders = try await syncFolders(
                imapFolders: imapFolders,
                account: account
            )
            NSLog("[Sync] \(syncableFolders.count) syncable folders")

            // 2. Sync emails for each folder
            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            var emailLookup = buildMessageIdLookup(from: existingEmails)
            var canonicalLookup = buildCanonicalLookup(from: existingEmails)
            var allSyncedEmails: [Email] = []
            NSLog("[Sync] Existing emails in DB: \(existingEmails.count)")

            for folder in syncableFolders {
                NSLog("[Sync] Syncing folder: \(folder.name) (\(folder.imapPath))")
                let newEmails = try await withFolderSyncLock(accountId: account.id, folderId: folder.id) {
                    try await syncFolderEmails(
                        client: client,
                        account: account,
                        folder: folder,
                        emailLookup: emailLookup,
                        canonicalLookup: canonicalLookup
                    )
                }
                NSLog("[Sync] Synced \(newEmails.count) new emails from \(folder.name)")
                for email in newEmails {
                    emailLookup[email.messageId] = email
                    let key = canonicalDedupKey(
                        subject: email.subject,
                        fromAddress: email.fromAddress,
                        date: email.dateReceived,
                        sizeBytes: email.sizeBytes
                    )
                    canonicalLookup[key] = email
                }
                allSyncedEmails.append(contentsOf: newEmails)
            }

            // 3. Update account sync date
            account.lastSyncDate = Date()
            try await accountRepository.updateAccount(account)
            NSLog("[Sync] syncAccount completed successfully (\(allSyncedEmails.count) new emails)")

            await connectionProvider.checkinConnection(client, accountId: account.id)
            return allSyncedEmails
        } catch {
            NSLog("[Sync] syncAccount ERROR: \(error)")
            await connectionProvider.checkinConnection(client, accountId: account.id)
            throw error
        }
    }

    @discardableResult
    public func syncAccountInboxFirst(
        accountId: String,
        onInboxSynced: @MainActor (_ inboxEmails: [Email]) async -> Void
    ) async throws -> [Email] {
        NSLog("[Sync] syncAccountInboxFirst started for \(accountId)")
        let account = try await findAccount(id: accountId)
        let imapCredential = try await resolveIMAPCredential(for: account)

        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: imapCredential
        )
        NSLog("[Sync] IMAP connection established")

        do {
            // 1. Sync folder list (single LIST command — fast)
            let imapFolders = try await client.listFolders()
            NSLog("[Sync] LIST returned \(imapFolders.count) folders, provider=\(account.resolvedProvider.rawValue)")
            for f in imapFolders {
                NSLog("[Sync]   folder: \(f.imapPath) attrs=\(f.attributes)")
            }
            let syncableFolders = try await syncFolders(
                imapFolders: imapFolders,
                account: account
            )
            NSLog("[Sync] \(syncableFolders.count) syncable folders discovered")

            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            var emailLookup = buildMessageIdLookup(from: existingEmails)
            var canonicalLookup = buildCanonicalLookup(from: existingEmails)
            var allSyncedEmails: [Email] = []

            // 2. Sync INBOX first for fast initial load
            let inboxType = FolderType.inbox.rawValue
            let inboxFolder = syncableFolders.first { $0.folderType == inboxType }

            if let inbox = inboxFolder {
                NSLog("[Sync] Priority: syncing Inbox first (\(inbox.imapPath))")
                let inboxEmails = try await withFolderSyncLock(accountId: account.id, folderId: inbox.id) {
                    try await syncFolderEmails(
                        client: client,
                        account: account,
                        folder: inbox,
                        emailLookup: emailLookup,
                        canonicalLookup: canonicalLookup,
                        headersOnly: true,
                        direction: .forward,
                        maxUIDs: 30
                    )
                }
                NSLog("[Sync] Inbox synced: \(inboxEmails.count) new emails")
                inbox.initialFastCompleted = true
                try await emailRepository.saveFolder(inbox)
                for email in inboxEmails {
                    emailLookup[email.messageId] = email
                    let key = canonicalDedupKey(
                        subject: email.subject,
                        fromAddress: email.fromAddress,
                        date: email.dateReceived,
                        sizeBytes: email.sizeBytes
                    )
                    canonicalLookup[key] = email
                }
                allSyncedEmails.append(contentsOf: inboxEmails)

                // Notify UI immediately — inbox is ready to display
                await onInboxSynced(inboxEmails)
            }

            // 3. Stage-C bootstrap budget allocator (non-blocking for UI).
            guard !Task.isCancelled else {
                await connectionProvider.checkinConnection(client, accountId: account.id)
                return allSyncedEmails
            }

            let stageCAllocations = buildStageCAllocations(
                syncableFolders: syncableFolders,
                inboxFolder: inboxFolder
            )
            for allocation in stageCAllocations {
                guard !Task.isCancelled else { break }
                NSLog("[Sync] Stage-C sync: \(allocation.folder.name) (\(allocation.folder.imapPath)) [headers-only]")
                let newEmails = try await withFolderSyncLock(accountId: account.id, folderId: allocation.folder.id) {
                    try await syncFolderEmails(
                        client: client,
                        account: account,
                        folder: allocation.folder,
                        emailLookup: emailLookup,
                        canonicalLookup: canonicalLookup,
                        headersOnly: true,
                        direction: allocation.direction,
                        maxUIDs: allocation.maxHeaders
                    )
                }
                NSLog("[Sync] Synced \(newEmails.count) new emails from \(allocation.folder.name)")
                for email in newEmails {
                    emailLookup[email.messageId] = email
                    let key = canonicalDedupKey(
                        subject: email.subject,
                        fromAddress: email.fromAddress,
                        date: email.dateReceived,
                        sizeBytes: email.sizeBytes
                    )
                    canonicalLookup[key] = email
                }
                allSyncedEmails.append(contentsOf: newEmails)
            }

            // 4. Stage-D catch-up continues in background.
            let orderedFolderIds = prioritizedFolderOrder(from: syncableFolders).map(\.id)
            startBackgroundCatchUpIfNeeded(accountId: account.id, folderIds: orderedFolderIds)

            // 5. Update account sync date
            account.lastSyncDate = Date()
            try await accountRepository.updateAccount(account)
            NSLog("[Sync] syncAccountInboxFirst completed (\(allSyncedEmails.count) total new emails)")

            await connectionProvider.checkinConnection(client, accountId: account.id)
            return allSyncedEmails
        } catch {
            NSLog("[Sync] syncAccountInboxFirst ERROR: \(error)")
            await connectionProvider.checkinConnection(client, accountId: account.id)
            throw error
        }
    }

    @discardableResult
    public func syncFolder(accountId: String, folderId: String) async throws -> [Email] {
        try await syncFolderWithOptions(
            accountId: accountId,
            folderId: folderId,
            options: .incremental
        )
    }

    public func pauseCatchUp(accountId: String) async {
        catchUpTasks[accountId]?.cancel()
        catchUpTasks[accountId] = nil
        guard let folders = try? await emailRepository.getFolders(accountId: accountId) else { return }
        for folder in folders {
            folder.catchUpStatus = SyncCatchUpStatus.paused.rawValue
            try? await emailRepository.saveFolder(folder)
        }
    }

    public func resumeCatchUp(accountId: String) async {
        guard let folders = try? await emailRepository.getFolders(accountId: accountId) else { return }
        var resumed: [Folder] = []
        for folder in folders where folder.catchUpStatus == SyncCatchUpStatus.paused.rawValue {
            folder.catchUpStatus = SyncCatchUpStatus.idle.rawValue
            try? await emailRepository.saveFolder(folder)
            resumed.append(folder)
        }
        let orderedFolderIds = prioritizedFolderOrder(from: resumed).map(\.id)
        startBackgroundCatchUpIfNeeded(accountId: accountId, folderIds: orderedFolderIds)
    }

    private func syncAccountIncremental(accountId: String) async throws -> [Email] {
        let account = try await findAccount(id: accountId)
        let imapCredential = try await resolveIMAPCredential(for: account)
        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: imapCredential
        )

        do {
            let imapFolders = try await client.listFolders()
            let syncableFolders = try await syncFolders(imapFolders: imapFolders, account: account)
            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            var messageLookup = buildMessageIdLookup(from: existingEmails)
            var canonicalLookup = buildCanonicalLookup(from: existingEmails)
            var allNew: [Email] = []

            for folder in syncableFolders {
                let newEmails = try await withFolderSyncLock(accountId: account.id, folderId: folder.id) {
                    try await syncFolderEmails(
                        client: client,
                        account: account,
                        folder: folder,
                        emailLookup: messageLookup,
                        canonicalLookup: canonicalLookup,
                        headersOnly: true,
                        direction: .forward
                    )
                }
                for email in newEmails {
                    messageLookup[email.messageId] = email
                    let key = canonicalDedupKey(
                        subject: email.subject,
                        fromAddress: email.fromAddress,
                        date: email.dateReceived,
                        sizeBytes: email.sizeBytes
                    )
                    canonicalLookup[key] = email
                }
                allNew.append(contentsOf: newEmails)
            }

            account.lastSyncDate = Date()
            try await accountRepository.updateAccount(account)
            await connectionProvider.checkinConnection(client, accountId: account.id)
            return allNew
        } catch {
            await connectionProvider.checkinConnection(client, accountId: account.id)
            throw error
        }
    }

    private func syncFolderWithOptions(
        accountId: String,
        folderId: String,
        options: SyncFolderOptions
    ) async throws -> [Email] {
        let account = try await findAccount(id: accountId)
        let imapCredential = try await resolveIMAPCredential(for: account)
        let folders = try await emailRepository.getFolders(accountId: account.id)
        guard let folder = folders.first(where: { $0.id == folderId }) else {
            throw SyncError.folderNotFound(folderId)
        }

        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: imapCredential
        )

        do {
            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            let messageLookup = buildMessageIdLookup(from: existingEmails)
            let canonicalLookup = buildCanonicalLookup(from: existingEmails)
            let direction: SyncDirection = (options == .catchUp) ? .backward : .forward
            let headersOnly = options == .incremental
            let maxHeaders = options == .catchUp ? fetchBatchSize : nil
            if options == .catchUp {
                guard folder.catchUpStatus != SyncCatchUpStatus.paused.rawValue else {
                    await connectionProvider.checkinConnection(client, accountId: account.id)
                    return []
                }
                folder.catchUpStatus = SyncCatchUpStatus.running.rawValue
                try await emailRepository.saveFolder(folder)
            }

            let newEmails = try await withFolderSyncLock(accountId: account.id, folderId: folder.id) {
                try await syncFolderEmails(
                    client: client,
                    account: account,
                    folder: folder,
                    emailLookup: messageLookup,
                    canonicalLookup: canonicalLookup,
                    headersOnly: headersOnly,
                    direction: direction,
                    maxUIDs: maxHeaders
                )
            }
            if options == .catchUp {
                folder.catchUpStatus = newEmails.isEmpty ? SyncCatchUpStatus.completed.rawValue : SyncCatchUpStatus.idle.rawValue
                try await emailRepository.saveFolder(folder)
            }

            await connectionProvider.checkinConnection(client, accountId: account.id)
            return newEmails
        } catch {
            if options == .catchUp {
                folder.catchUpStatus = SyncCatchUpStatus.error.rawValue
                try? await emailRepository.saveFolder(folder)
            }
            await connectionProvider.checkinConnection(client, accountId: account.id)
            throw error
        }
    }

    // MARK: - Account & Token

    private func findAccount(id: String) async throws -> Account {
        let accounts = try await accountRepository.getAccounts()
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw SyncError.accountNotFound(id)
        }
        guard account.isActive else {
            throw SyncError.accountInactive(id)
        }
        return account
    }

    /// Resolves account credentials and returns the appropriate IMAP credential.
    ///
    /// Delegates to `CredentialResolver` which handles OAuth token refresh
    /// with fallback to existing token, and direct password credential mapping.
    private func resolveIMAPCredential(for account: Account) async throws -> IMAPCredential {
        let resolver = CredentialResolver(
            keychainManager: keychainManager,
            accountRepository: accountRepository
        )
        do {
            return try await resolver.resolveIMAPCredential(for: account, refreshIfNeeded: true)
        } catch {
            NSLog("[Sync] Credential resolution failed for \(account.id): \(error)")
            throw SyncError.tokenRefreshFailed(error.localizedDescription)
        }
    }

    // MARK: - Folder Sync

    /// Syncs IMAP folders to SwiftData, returns the list of syncable folders.
    private func syncFolders(
        imapFolders: [IMAPFolderInfo],
        account: Account
    ) async throws -> [Folder] {
        var syncableFolders: [Folder] = []
        let provider = account.resolvedProvider

        for imapFolder in imapFolders {
            let shouldSync = ProviderFolderMapper.shouldSync(
                imapPath: imapFolder.imapPath,
                attributes: imapFolder.attributes,
                provider: provider
            )

            let folderType = ProviderFolderMapper.folderType(
                imapPath: imapFolder.imapPath,
                attributes: imapFolder.attributes,
                provider: provider
            )

            NSLog("[Sync] Folder '\(imapFolder.imapPath)' shouldSync=\(shouldSync) type=\(folderType.rawValue) (provider=\(provider.rawValue), attrs=\(imapFolder.attributes))")

            // For non-syncable folders that have a special type (e.g. archive/All Mail),
            // create the folder record so actions like archive can reference it,
            // but don't add to syncableFolders (skip email sync).
            let isReferenceOnly = !shouldSync && folderType != .custom

            guard shouldSync || isReferenceOnly else { continue }

            // Find existing or create new
            let folder: Folder
            if let existing = try await emailRepository.getFolderByImapPath(
                imapFolder.imapPath,
                accountId: account.id
            ) {
                existing.name = imapFolder.name
                existing.folderType = folderType.rawValue
                existing.totalCount = Int(imapFolder.messageCount)
                folder = existing
                try await emailRepository.saveFolder(existing)
            } else {
                let newFolder = Folder(
                    name: imapFolder.name,
                    imapPath: imapFolder.imapPath,
                    totalCount: Int(imapFolder.messageCount),
                    folderType: folderType.rawValue,
                    uidValidity: Int(imapFolder.uidValidity)
                )
                newFolder.account = account
                try await emailRepository.saveFolder(newFolder)
                folder = newFolder
            }

            // Only add to syncable list if we should actually sync emails from it
            if shouldSync {
                syncableFolders.append(folder)
            }
        }

        return syncableFolders
    }

    // MARK: - Per-Folder Email Sync

    /// Syncs emails for a single folder. Returns the newly created Email objects.
    ///
    /// - Parameter headersOnly: When `true`, skips body fetch (plain text, HTML, attachments).
    ///   Used for non-inbox folders during initial sync to minimize IMAP round trips.
    ///   Bodies are fetched lazily when the user opens an email.
    @discardableResult
    private func syncFolderEmails(
        client: any IMAPClientProtocol,
        account: Account,
        folder: Folder,
        emailLookup: [String: Email],
        canonicalLookup: [String: Email],
        headersOnly: Bool = false,
        direction: SyncDirection = .full,
        maxUIDs: Int? = nil
    ) async throws -> [Email] {
        // SELECT folder
        let (serverUidValidity, messageCount) = try await client.selectFolder(folder.imapPath)

        // Handle UIDVALIDITY change — all local UIDs are stale
        if folder.uidValidity != 0 && folder.uidValidity != Int(serverUidValidity) {
            try await emailRepository.removeEmailFolderAssociations(folderId: folder.id)
            folder.lastSyncDate = nil
            folder.forwardCursorUID = nil
            folder.backfillCursorUID = nil
            folder.initialFastCompleted = false
            folder.catchUpStatus = SyncCatchUpStatus.idle.rawValue
        }
        folder.uidValidity = Int(serverUidValidity)

        // Search for UIDs.
        // On first sync (lastSyncDate == nil), fetch ALL UIDs so folders like
        // Sent/Drafts show their complete contents regardless of age.
        // On subsequent syncs, use incremental date-based search.
        let allUIDs: [UInt32]
        switch direction {
        case .full:
            if let lastSync = folder.lastSyncDate {
                allUIDs = try await client.searchUIDs(since: lastSync)
            } else {
                NSLog("[Sync] First sync for '\(folder.imapPath)' — fetching all UIDs")
                allUIDs = try await client.searchAllUIDs()
            }
        case .forward, .backward:
            allUIDs = try await client.searchAllUIDs()
        }
        guard !allUIDs.isEmpty else {
            folder.totalCount = Int(messageCount)
            folder.lastSyncDate = Date()
            try await emailRepository.saveFolder(folder)
            return []
        }

        let sortedUIDs = allUIDs.sorted()

        // Filter out already-synced UIDs
        let existingEmailFolders = try await emailRepository.getEmails(folderId: folder.id)
        let knownUIDs = Set(
            existingEmailFolders.flatMap { email in
                email.emailFolders
                    .filter { $0.folder?.id == folder.id }
                    .map { $0.imapUID }
            }
        )
        let minAllUID = sortedUIDs.first.map(Int.init)
        let totalUIDCount = sortedUIDs.count
        let knownUIDCount = knownUIDs.count

        if direction == .backward,
           let cursor = folder.backfillCursorUID,
           let minAllUID,
           cursor <= minAllUID,
           knownUIDCount < totalUIDCount {
            if let repaired = knownUIDs.min() {
                folder.backfillCursorUID = repaired
            } else {
                folder.backfillCursorUID = nil
            }
        }

        let candidateUIDs: [UInt32]
        switch direction {
        case .full:
            candidateUIDs = sortedUIDs
        case .forward:
            if let cursor = folder.forwardCursorUID {
                candidateUIDs = sortedUIDs.filter { Int($0) > cursor }
            } else {
                candidateUIDs = sortedUIDs
            }
        case .backward:
            if let cursor = folder.backfillCursorUID {
                candidateUIDs = sortedUIDs.filter { Int($0) < cursor }
            } else {
                candidateUIDs = sortedUIDs
            }
        }
        var newUIDs = candidateUIDs.filter { !knownUIDs.contains(Int($0)) }
        if let maxUIDs, newUIDs.count > maxUIDs {
            newUIDs = Array(newUIDs.suffix(maxUIDs))
        }

        guard !newUIDs.isEmpty else {
            // Keep cursors populated even when there are no newly persisted rows.
            // This allows migration code to rely on cursor state immediately.
            if let maxUID = allUIDs.max() {
                let current = folder.forwardCursorUID ?? 0
                folder.forwardCursorUID = max(current, Int(maxUID))
            }
            if direction == .backward {
                if knownUIDCount >= totalUIDCount, let minUID = allUIDs.min() {
                    if let existing = folder.backfillCursorUID {
                        folder.backfillCursorUID = min(existing, Int(minUID))
                    } else {
                        folder.backfillCursorUID = Int(minUID)
                    }
                } else if let knownMin = knownUIDs.min() {
                    folder.backfillCursorUID = knownMin
                }
            } else if let minUID = allUIDs.min() {
                if let existing = folder.backfillCursorUID {
                    folder.backfillCursorUID = min(existing, Int(minUID))
                } else {
                    folder.backfillCursorUID = Int(minUID)
                }
            }
            folder.totalCount = Int(messageCount)
            folder.lastSyncDate = Date()
            try await emailRepository.saveFolder(folder)
            return []
        }

        // Fetch in batches
        var allNewEmails: [Email] = []
        var mutableLookup = emailLookup
        var mutableCanonicalLookup = canonicalLookup

        for batchStart in stride(from: 0, to: newUIDs.count, by: fetchBatchSize) {
            if direction == .backward && folder.catchUpStatus == SyncCatchUpStatus.paused.rawValue {
                break
            }
            let batchEnd = min(batchStart + fetchBatchSize, newUIDs.count)
            let batch = Array(newUIDs[batchStart..<batchEnd])

            let headers = try await client.fetchHeaders(uids: batch)
            let bodies: [IMAPEmailBody]
            if headersOnly {
                bodies = []
            } else {
                bodies = try await client.fetchBodies(uids: batch)
            }
            let bodyMap = Dictionary(uniqueKeysWithValues: bodies.map { ($0.uid, $0) })

            for header in headers {
                let body = bodyMap[header.uid]

                // Resolve thread
                let threadId = resolveThreadId(
                    for: header,
                    accountId: account.id,
                    emailLookup: mutableLookup
                )

                let identity = resolveIdentity(
                    for: header,
                    accountId: account.id,
                    emailLookup: mutableLookup,
                    canonicalLookup: mutableCanonicalLookup
                )

                // Map to Email model
                let mappedEmail = mapToEmail(
                    header: header,
                    body: body,
                    accountId: account.id,
                    threadId: threadId,
                    identityKey: identity.identityKey,
                    resolvedMessageId: identity.messageId
                )
                // Use the managed object returned by saveEmail (may be an
                // existing record when the email was already synced via
                // another folder). Using the unmanaged local object would
                // cause "Illegal attempt to relate PersistentIdentifier…
                // to a model in another store" when setting email.thread.
                let email = try await emailRepository.saveEmail(mappedEmail)

                // Create EmailFolder join
                let ef = EmailFolder(imapUID: Int(header.uid))
                ef.email = email
                ef.folder = folder
                try await emailRepository.saveEmailFolder(ef)

                // Create Attachments
                if let body {
                    for info in body.attachments {
                        let attachment = mapToAttachment(from: info)
                        attachment.email = email
                        try await emailRepository.saveAttachment(attachment)
                    }
                }

                // Populate contact cache from email headers (From, To, CC)
                let contacts = extractContacts(from: header, accountId: account.id)
                for contact in contacts {
                    try await emailRepository.upsertContact(contact)
                }

                mutableLookup[email.messageId] = email
                mutableCanonicalLookup[identity.canonicalKey] = email
                allNewEmails.append(email)
            }

            // Flush all inserts for this batch in a single save
            try await emailRepository.flushChanges()

            // Persist cursor progression after each committed batch.
            if let maxUID = headers.map(\.uid).max() {
                let current = folder.forwardCursorUID ?? 0
                folder.forwardCursorUID = max(current, Int(maxUID))
            }
            if let minUID = headers.map(\.uid).min() {
                if let existing = folder.backfillCursorUID {
                    folder.backfillCursorUID = min(existing, Int(minUID))
                } else {
                    folder.backfillCursorUID = Int(minUID)
                }
            }
            try await emailRepository.saveFolder(folder)
        }

        // Update thread aggregates for all affected threads
        let affectedThreadIds = Set(allNewEmails.map(\.threadId))
        for threadId in affectedThreadIds {
            try await updateThread(
                threadId: threadId,
                accountId: account.id,
                emailLookup: mutableLookup
            )
        }

        // Flush thread inserts/updates in a single save
        try await emailRepository.flushChanges()

        // Update folder metadata
        let allFolderEmails = try await emailRepository.getEmails(folderId: folder.id)
        folder.totalCount = Int(messageCount)
        folder.unreadCount = allFolderEmails.filter { !$0.isRead }.count
        folder.lastSyncDate = Date()
        folder.catchUpStatus = SyncCatchUpStatus.idle.rawValue
        try await emailRepository.saveFolder(folder)

        return allNewEmails
    }

    private func withFolderSyncLock<T>(
        accountId: String,
        folderId: String,
        operation: () async throws -> T
    ) async throws -> T {
        await folderSyncCoordinator.acquire(accountId: accountId, folderId: folderId)
        do {
            let result = try await operation()
            await folderSyncCoordinator.release(accountId: accountId, folderId: folderId)
            return result
        } catch {
            await folderSyncCoordinator.release(accountId: accountId, folderId: folderId)
            throw error
        }
    }

    private func buildStageCAllocations(
        syncableFolders: [Folder],
        inboxFolder: Folder?
    ) -> [StageCAllocation] {
        let totalCap = 500
        let inboxShare = Int(Double(totalCap) * 0.60) // 300
        let sentShare = Int(Double(totalCap) * 0.20) // 100
        let othersShare = totalCap - inboxShare - sentShare // 100
        let minFloor = 20

        var allocations: [StageCAllocation] = []

        if let inbox = inboxFolder {
            let remainingInboxBudget = max(inboxShare - 30, 0)
            if remainingInboxBudget > 0 {
                allocations.append(
                    StageCAllocation(
                        folder: inbox,
                        direction: .backward,
                        maxHeaders: remainingInboxBudget
                    )
                )
            }
        }

        let sentFolder = syncableFolders.first { $0.folderType == FolderType.sent.rawValue }
        if let sentFolder, sentShare > 0 {
            allocations.append(
                StageCAllocation(
                    folder: sentFolder,
                    direction: .forward,
                    maxHeaders: sentShare
                )
            )
        }

        let excluded = Set([inboxFolder?.id, sentFolder?.id].compactMap { $0 })
        let otherFolders = syncableFolders.filter { !excluded.contains($0.id) }
        guard !otherFolders.isEmpty else { return allocations }

        var remainingBudget = othersShare
        var perFolder = [String: Int]()
        if remainingBudget >= otherFolders.count * minFloor {
            for folder in otherFolders {
                perFolder[folder.id] = minFloor
                remainingBudget -= minFloor
            }
        } else {
            let even = max(1, remainingBudget / otherFolders.count)
            for folder in otherFolders {
                perFolder[folder.id] = even
                remainingBudget -= even
            }
        }

        var index = 0
        while remainingBudget > 0 {
            let folder = otherFolders[index % otherFolders.count]
            perFolder[folder.id, default: 0] += 1
            remainingBudget -= 1
            index += 1
        }

        for folder in otherFolders {
            let allocation = perFolder[folder.id, default: 0]
            guard allocation > 0 else { continue }
            allocations.append(
                StageCAllocation(
                    folder: folder,
                    direction: .forward,
                    maxHeaders: allocation
                )
            )
        }

        return allocations
    }

    private func prioritizedFolderOrder(from folders: [Folder]) -> [Folder] {
        let inbox = folders.filter { $0.folderType == FolderType.inbox.rawValue }
        let sent = folders.filter { $0.folderType == FolderType.sent.rawValue }
        let others = folders.filter {
            $0.folderType != FolderType.inbox.rawValue && $0.folderType != FolderType.sent.rawValue
        }
        return inbox + sent + others
    }

    private func startBackgroundCatchUpIfNeeded(accountId: String, folderIds: [String]) {
        guard !folderIds.isEmpty else { return }
        if let existing = catchUpTasks[accountId], !existing.isCancelled {
            return
        }

        catchUpTasks[accountId] = Task { [weak self] in
            guard let self else { return }
            await self.runBackgroundCatchUp(accountId: accountId, folderIds: folderIds)
            self.catchUpTasks[accountId] = nil
        }
    }

    private func runBackgroundCatchUp(accountId: String, folderIds: [String]) async {
        var madeProgress = true
        while !Task.isCancelled && madeProgress {
            madeProgress = false
            for folderId in folderIds {
                guard !Task.isCancelled else { return }
                do {
                    let newEmails = try await syncFolderWithOptions(
                        accountId: accountId,
                        folderId: folderId,
                        options: .catchUp
                    )
                    if !newEmails.isEmpty {
                        madeProgress = true
                    }
                } catch {
                    continue
                }
            }
        }
    }

    // MARK: - Threading

    /// Build a messageId → Email lookup for fast thread resolution.
    private func buildMessageIdLookup(from emails: [Email]) -> [String: Email] {
        var lookup: [String: Email] = [:]
        for email in emails {
            lookup[email.messageId] = email
        }
        return lookup
    }

    private func buildCanonicalLookup(from emails: [Email]) -> [String: Email] {
        var lookup: [String: Email] = [:]
        for email in emails {
            let key = canonicalDedupKey(
                subject: email.subject,
                fromAddress: email.fromAddress,
                date: email.dateReceived,
                sizeBytes: email.sizeBytes
            )
            lookup[key] = email
        }
        return lookup
    }

    private struct ResolvedIdentity {
        let messageId: String
        let identityKey: String
        let canonicalKey: String
    }

    private func resolveIdentity(
        for header: IMAPEmailHeader,
        accountId: String,
        emailLookup: [String: Email],
        canonicalLookup: [String: Email]
    ) -> ResolvedIdentity {
        let rawMessageId = normalizedMessageId(header.messageId)
        let canonical = canonicalDedupKey(
            subject: header.subject ?? "",
            fromAddress: parseFromField(header.from).0,
            date: header.date,
            sizeBytes: Int(header.size)
        )

        if let rawMessageId,
           let existing = emailLookup[rawMessageId] {
            if looksLikeSameLogicalMessage(existing: existing, incomingHeader: header) {
                return ResolvedIdentity(messageId: existing.messageId, identityKey: existing.messageId, canonicalKey: canonical)
            }
            // Duplicate Message-ID with conflicting content: fall back to canonical identity.
            let composite = "\(rawMessageId)|\(canonical)"
            return ResolvedIdentity(messageId: rawMessageId, identityKey: composite, canonicalKey: canonical)
        }

        if let existing = canonicalLookup[canonical] {
            return ResolvedIdentity(messageId: existing.messageId, identityKey: existing.messageId, canonicalKey: canonical)
        }

        if let rawMessageId {
            return ResolvedIdentity(messageId: rawMessageId, identityKey: rawMessageId, canonicalKey: canonical)
        }

        let synthetic = "<canon-\(canonical)@\(accountId)>"
        return ResolvedIdentity(messageId: synthetic, identityKey: "canon:\(canonical)", canonicalKey: canonical)
    }

    private func normalizedMessageId(_ messageId: String?) -> String? {
        guard let messageId else { return nil }
        let trimmed = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeSameLogicalMessage(existing: Email, incomingHeader: IMAPEmailHeader) -> Bool {
        let normalizedExistingSubject = normalizeSubject(existing.subject).lowercased()
        let normalizedIncomingSubject = normalizeSubject(incomingHeader.subject ?? "").lowercased()
        let incomingFrom = parseFromField(incomingHeader.from).0.lowercased()

        guard normalizedExistingSubject == normalizedIncomingSubject else { return false }
        guard existing.fromAddress.lowercased() == incomingFrom else { return false }

        guard let existingDate = existing.dateReceived, let incomingDate = incomingHeader.date else {
            return true
        }
        return abs(existingDate.timeIntervalSince(incomingDate)) <= (3 * 24 * 60 * 60)
    }

    private func canonicalDedupKey(
        subject: String,
        fromAddress: String,
        date: Date?,
        sizeBytes: Int
    ) -> String {
        let normalizedSubject = normalizeSubject(subject).lowercased()
        let normalizedFrom = fromAddress.lowercased()
        let dayBucket: Int
        if let date {
            dayBucket = Int(date.timeIntervalSince1970 / 86_400)
        } else {
            dayBucket = 0
        }
        return "\(normalizedFrom)|\(normalizedSubject)|\(dayBucket)|\(sizeBytes)"
    }

    /// Resolve which thread an email belongs to.
    private func resolveThreadId(
        for header: IMAPEmailHeader,
        accountId: String,
        emailLookup: [String: Email]
    ) -> String {
        // 1. Check inReplyTo
        if let inReplyTo = header.inReplyTo, !inReplyTo.isEmpty,
           let parent = emailLookup[inReplyTo] {
            return parent.threadId
        }

        // 2. Check references (reverse order — newest first)
        if let references = header.references, !references.isEmpty {
            let refs = references.split(separator: " ").map(String.init).reversed()
            for ref in refs {
                if let parent = emailLookup[ref] {
                    return parent.threadId
                }
            }
        }

        // 3. Subject-based fallback
        let normalizedSubject = normalizeSubject(header.subject ?? "")
        if !normalizedSubject.isEmpty {
            let emailDate = header.date ?? Date()
            let thirtyDaysAgo = emailDate.addingTimeInterval(-30 * 86400)

            for (_, existingEmail) in emailLookup {
                guard existingEmail.accountId == accountId else { continue }
                let existingNormalized = normalizeSubject(existingEmail.subject)
                if existingNormalized == normalizedSubject,
                   let existingDate = existingEmail.dateReceived,
                   existingDate >= thirtyDaysAgo {
                    return existingEmail.threadId
                }
            }
        }

        // 4. New thread
        return UUID().uuidString
    }

    /// Strip Re:/Fwd:/RE:/FW: prefixes from a subject for thread matching.
    private func normalizeSubject(_ subject: String) -> String {
        var result = subject.trimmingCharacters(in: .whitespaces)
        let prefixes = ["re:", "fwd:", "fw:"]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes {
                if result.lowercased().hasPrefix(prefix) {
                    result = String(result.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        return result
    }

    /// Create or update a Thread aggregate from its constituent emails.
    private func updateThread(
        threadId: String,
        accountId: String,
        emailLookup: [String: Email]
    ) async throws {
        let threadEmails = emailLookup.values
            .filter { $0.threadId == threadId && $0.accountId == accountId }
            .sorted { ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast) }

        guard let oldest = threadEmails.first, let newest = threadEmails.last else { return }

        let existingThread = try await emailRepository.getThread(id: threadId)

        let thread: VaultMailFeature.Thread
        let isNewThread: Bool
        if let existing = existingThread {
            thread = existing
            isNewThread = false
        } else {
            thread = VaultMailFeature.Thread(
                id: threadId,
                accountId: accountId,
                subject: oldest.subject
            )
            isNewThread = true
        }

        thread.subject = oldest.subject
        thread.latestDate = newest.dateReceived
        thread.messageCount = threadEmails.count
        thread.unreadCount = threadEmails.filter { !$0.isRead }.count
        thread.isStarred = threadEmails.contains { $0.isStarred }
        thread.snippet = newest.snippet

        // Only set uncategorized for brand-new threads.
        // Existing threads preserve their AI-assigned or manual category.
        if isNewThread {
            thread.aiCategory = AICategory.uncategorized.rawValue
        }

        // Build participants from unique from/to addresses
        var participantSet: [String: Participant] = [:]
        for email in threadEmails {
            let fromName = email.fromName
            let fromAddr = email.fromAddress
            if !fromAddr.isEmpty {
                participantSet[fromAddr] = Participant(name: fromName, email: fromAddr)
            }
        }
        thread.participants = Participant.encode(Array(participantSet.values))

        // Set email relationships
        for email in threadEmails {
            email.thread = thread
        }

        try await emailRepository.saveThread(thread)
    }

    // MARK: - DTO Mapping

    /// Map an IMAP header + body to an Email model.
    private func mapToEmail(
        header: IMAPEmailHeader,
        body: IMAPEmailBody?,
        accountId: String,
        threadId: String,
        identityKey: String,
        resolvedMessageId: String
    ) -> Email {
        let messageId = resolvedMessageId
        // Deterministic ID for dedup across folders/fallback identity.
        let emailId = stableId(accountId: accountId, messageId: identityKey)

        // Parse from name from "Name <email>" format
        let (fromAddress, fromName) = parseFromField(header.from)

        // JSON-encode address arrays
        let toJSON = encodeAddresses(header.to)
        let ccJSON = header.cc.isEmpty ? nil : encodeAddresses(header.cc)
        let bccJSON = header.bcc.isEmpty ? nil : encodeAddresses(header.bcc)

        // Snippet from plain text body
        let snippet: String?
        if let plainText = body?.plainText, !plainText.isEmpty {
            let cleaned = plainText
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            snippet = String(cleaned.prefix(150))
        } else {
            snippet = nil
        }

        return Email(
            id: emailId,
            accountId: accountId,
            threadId: threadId,
            messageId: messageId,
            inReplyTo: header.inReplyTo,
            references: header.references,
            fromAddress: fromAddress,
            fromName: fromName,
            toAddresses: toJSON,
            ccAddresses: ccJSON,
            bccAddresses: bccJSON,
            subject: header.subject ?? "(No Subject)",
            bodyPlain: body?.plainText,
            bodyHTML: body?.htmlText,
            snippet: snippet,
            dateReceived: header.date,
            dateSent: header.date,
            isRead: header.flags.contains("\\Seen"),
            isStarred: header.flags.contains("\\Flagged"),
            isDraft: header.flags.contains("\\Draft"),
            isDeleted: header.flags.contains("\\Deleted"),
            aiCategory: AICategory.uncategorized.rawValue,
            authenticationResults: header.authenticationResults,
            sizeBytes: Int(header.size)
        )
    }

    /// Map IMAP attachment info to an Attachment model.
    ///
    /// Stores `bodySection` (MIME part ID) so ``DownloadAttachmentUseCase``
    /// can lazily fetch this part via `BODY.PEEK[<section>]` (FR-SYNC-08).
    private func mapToAttachment(from info: IMAPAttachmentInfo) -> Attachment {
        let filename = resolvedAttachmentFilename(from: info)
        return Attachment(
            filename: filename,
            mimeType: info.mimeType ?? "application/octet-stream",
            sizeBytes: Int(info.sizeBytes ?? 0),
            isDownloaded: false,
            bodySection: info.partId,
            transferEncoding: info.transferEncoding,
            contentId: info.contentId
        )
    }

    private func resolvedAttachmentFilename(from info: IMAPAttachmentInfo) -> String {
        AttachmentFileUtilities.resolvedFilename(
            info.filename ?? "",
            mimeType: info.mimeType
        )
    }

    // MARK: - Contact Extraction

    /// Extract contacts from email header fields (From, To, CC) for the contact cache.
    ///
    /// Reuses `parseFromField()` to handle both "Name <email>" and bare email formats.
    /// Deduplicates by lowercased email address within a single header.
    private func extractContacts(from header: IMAPEmailHeader, accountId: String) -> [ContactCacheEntry] {
        var contacts: [ContactCacheEntry] = []
        var seen = Set<String>()

        // From
        let (fromEmail, fromName) = parseFromField(header.from)
        if !fromEmail.isEmpty {
            let lower = fromEmail.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                contacts.append(ContactCacheEntry(
                    accountId: accountId,
                    emailAddress: fromEmail,
                    displayName: fromName,
                    lastSeenDate: header.date ?? Date()
                ))
            }
        }

        // To + CC
        for addr in header.to + header.cc {
            let (email, name) = parseFromField(addr)
            guard !email.isEmpty else { continue }
            let lower = email.lowercased()
            guard !seen.contains(lower) else { continue }
            seen.insert(lower)
            contacts.append(ContactCacheEntry(
                accountId: accountId,
                emailAddress: email,
                displayName: name,
                lastSeenDate: header.date ?? Date()
            ))
        }

        return contacts
    }

    // MARK: - Helpers

    /// Generate a deterministic ID from accountId + messageId for cross-folder dedup.
    /// Uses SHA256 to ensure uniqueness regardless of input length.
    private func stableId(accountId: String, messageId: String) -> String {
        let input = "\(accountId)_\(messageId)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Parse "Display Name <email@example.com>" into (email, name).
    private func parseFromField(_ from: String?) -> (String, String?) {
        guard let from, !from.isEmpty else { return ("", nil) }

        // Pattern: "Name <email>"
        if let angleStart = from.lastIndex(of: "<"),
           let angleEnd = from.lastIndex(of: ">") {
            let email = String(from[from.index(after: angleStart)..<angleEnd])
                .trimmingCharacters(in: .whitespaces)
            let name = String(from[from.startIndex..<angleStart])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (email, name.isEmpty ? nil : name)
        }

        // Just an email address
        return (from.trimmingCharacters(in: .whitespaces), nil)
    }

    /// JSON-encode an array of email address strings.
    private func encodeAddresses(_ addresses: [String]) -> String {
        guard let data = try? JSONEncoder().encode(addresses),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
