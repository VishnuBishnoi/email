import Foundation
import CryptoKit

/// Domain use case for syncing emails from IMAP to SwiftData.
///
/// On-demand sync triggered by view load and pull-to-refresh.
/// Orchestrates: OAuth token refresh → IMAP connection → fetch → persist.
///
/// Spec ref: Email Sync spec FR-SYNC-01, FR-SYNC-09
@MainActor
public protocol SyncEmailsUseCaseProtocol {
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

/// Abstraction for obtaining IMAP connections. ConnectionPool conforms
/// in production; tests inject a mock that returns MockIMAPClient.
public protocol ConnectionProviding: Sendable {
    func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        email: String,
        accessToken: String
    ) async throws -> any IMAPClientProtocol

    func checkinConnection(_ client: any IMAPClientProtocol, accountId: String) async
}

/// Make ConnectionPool conform to ConnectionProviding.
extension ConnectionPool: ConnectionProviding {
    public func checkoutConnection(
        accountId: String,
        host: String,
        port: Int,
        email: String,
        accessToken: String
    ) async throws -> any IMAPClientProtocol {
        try await self.checkout(
            accountId: accountId,
            host: host,
            port: port,
            email: email,
            accessToken: accessToken
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

    private let accountRepository: AccountRepositoryProtocol
    private let emailRepository: EmailRepositoryProtocol
    private let keychainManager: KeychainManagerProtocol
    private let connectionProvider: ConnectionProviding

    /// Batch size for IMAP FETCH commands to avoid oversized responses.
    private let fetchBatchSize = 50

    public init(
        accountRepository: AccountRepositoryProtocol,
        emailRepository: EmailRepositoryProtocol,
        keychainManager: KeychainManagerProtocol,
        connectionPool: ConnectionProviding
    ) {
        self.accountRepository = accountRepository
        self.emailRepository = emailRepository
        self.keychainManager = keychainManager
        self.connectionProvider = connectionPool
    }

    // MARK: - Public API

    @discardableResult
    public func syncAccount(accountId: String) async throws -> [Email] {
        NSLog("[Sync] syncAccount started for \(accountId)")
        let account = try await findAccount(id: accountId)
        NSLog("[Sync] Found account: \(account.email), host: \(account.imapHost):\(account.imapPort)")

        NSLog("[Sync] Getting access token...")
        let token = try await getAccessToken(for: account)
        NSLog("[Sync] Got access token (length: \(token.count))")

        NSLog("[Sync] Checking out IMAP connection...")
        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            email: account.email,
            accessToken: token
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
            var allSyncedEmails: [Email] = []
            NSLog("[Sync] Existing emails in DB: \(existingEmails.count)")

            for folder in syncableFolders {
                NSLog("[Sync] Syncing folder: \(folder.name) (\(folder.imapPath))")
                let newEmails = try await syncFolderEmails(
                    client: client,
                    account: account,
                    folder: folder,
                    emailLookup: emailLookup
                )
                NSLog("[Sync] Synced \(newEmails.count) new emails from \(folder.name)")
                for email in newEmails {
                    emailLookup[email.messageId] = email
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
        let token = try await getAccessToken(for: account)

        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            email: account.email,
            accessToken: token
        )
        NSLog("[Sync] IMAP connection established")

        do {
            // 1. Sync folder list (single LIST command — fast)
            let imapFolders = try await client.listFolders()
            let syncableFolders = try await syncFolders(
                imapFolders: imapFolders,
                account: account
            )
            NSLog("[Sync] \(syncableFolders.count) syncable folders discovered")

            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            var emailLookup = buildMessageIdLookup(from: existingEmails)
            var allSyncedEmails: [Email] = []

            // 2. Sync INBOX first for fast initial load
            let inboxType = FolderType.inbox.rawValue
            let inboxFolder = syncableFolders.first { $0.folderType == inboxType }

            if let inbox = inboxFolder {
                NSLog("[Sync] Priority: syncing Inbox first (\(inbox.imapPath))")
                let inboxEmails = try await syncFolderEmails(
                    client: client,
                    account: account,
                    folder: inbox,
                    emailLookup: emailLookup
                )
                NSLog("[Sync] Inbox synced: \(inboxEmails.count) new emails")
                for email in inboxEmails {
                    emailLookup[email.messageId] = email
                }
                allSyncedEmails.append(contentsOf: inboxEmails)

                // Notify UI immediately — inbox is ready to display
                await onInboxSynced(inboxEmails)
            }

            // 3. Sync remaining folders
            guard !Task.isCancelled else {
                await connectionProvider.checkinConnection(client, accountId: account.id)
                return allSyncedEmails
            }

            let remainingFolders = syncableFolders.filter { $0.folderType != inboxType }
            for folder in remainingFolders {
                guard !Task.isCancelled else { break }
                NSLog("[Sync] Syncing folder: \(folder.name) (\(folder.imapPath)) [headers-only]")
                let newEmails = try await syncFolderEmails(
                    client: client,
                    account: account,
                    folder: folder,
                    emailLookup: emailLookup,
                    headersOnly: true
                )
                NSLog("[Sync] Synced \(newEmails.count) new emails from \(folder.name)")
                for email in newEmails {
                    emailLookup[email.messageId] = email
                }
                allSyncedEmails.append(contentsOf: newEmails)
            }

            // 4. Update account sync date
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
        let account = try await findAccount(id: accountId)
        let token = try await getAccessToken(for: account)

        let folders = try await emailRepository.getFolders(accountId: account.id)
        guard let folder = folders.first(where: { $0.id == folderId }) else {
            throw SyncError.folderNotFound(folderId)
        }

        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            email: account.email,
            accessToken: token
        )

        do {
            let existingEmails = try await emailRepository.getEmailsByAccount(accountId: account.id)
            let emailLookup = buildMessageIdLookup(from: existingEmails)

            let newEmails = try await syncFolderEmails(
                client: client,
                account: account,
                folder: folder,
                emailLookup: emailLookup
            )

            await connectionProvider.checkinConnection(client, accountId: account.id)
            return newEmails
        } catch {
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

    private func getAccessToken(for account: Account) async throws -> String {
        // Try to refresh the token (handles expiry checks internally)
        do {
            NSLog("[Sync] Refreshing token for account \(account.id)...")
            let token = try await accountRepository.refreshToken(for: account.id)
            NSLog("[Sync] Token refreshed successfully, expires: \(token.expiresAt)")
            return token.accessToken
        } catch {
            NSLog("[Sync] Token refresh failed: \(error), trying existing token...")
            // If refresh fails, try using existing token from keychain
            if let existing = try await keychainManager.retrieve(for: account.id) {
                NSLog("[Sync] Found existing token, expired: \(existing.isExpired), expires: \(existing.expiresAt)")
                if !existing.isExpired {
                    return existing.accessToken
                }
            } else {
                NSLog("[Sync] No token found in keychain")
            }
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

        for imapFolder in imapFolders {
            guard GmailFolderMapper.shouldSync(
                imapPath: imapFolder.imapPath,
                attributes: imapFolder.attributes
            ) else { continue }

            let folderType = GmailFolderMapper.folderType(
                imapPath: imapFolder.imapPath,
                attributes: imapFolder.attributes
            )

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

            syncableFolders.append(folder)
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
        headersOnly: Bool = false
    ) async throws -> [Email] {
        // SELECT folder
        let (serverUidValidity, messageCount) = try await client.selectFolder(folder.imapPath)

        // Handle UIDVALIDITY change — all local UIDs are stale
        if folder.uidValidity != 0 && folder.uidValidity != Int(serverUidValidity) {
            // Delete all EmailFolder entries for this folder to force re-sync
            let existingEmails = try await emailRepository.getEmails(folderId: folder.id)
            for email in existingEmails {
                for ef in email.emailFolders where ef.folder?.id == folder.id {
                    // Remove the stale join entry
                    // We can't delete via repo directly, so we'll just reset the sync date
                }
            }
            folder.lastSyncDate = nil
        }
        folder.uidValidity = Int(serverUidValidity)

        // Compute search date
        let searchDate: Date
        if let lastSync = folder.lastSyncDate {
            searchDate = lastSync
        } else {
            searchDate = Date().addingTimeInterval(
                -TimeInterval(account.syncWindowDays * 86400)
            )
        }

        // Search for UIDs since last sync
        let allUIDs = try await client.searchUIDs(since: searchDate)
        guard !allUIDs.isEmpty else {
            folder.totalCount = Int(messageCount)
            folder.lastSyncDate = Date()
            try await emailRepository.saveFolder(folder)
            return []
        }

        // Filter out already-synced UIDs
        let existingEmailFolders = try await emailRepository.getEmails(folderId: folder.id)
        let knownUIDs = Set(
            existingEmailFolders.flatMap { email in
                email.emailFolders
                    .filter { $0.folder?.id == folder.id }
                    .map { $0.imapUID }
            }
        )
        let newUIDs = allUIDs.filter { !knownUIDs.contains(Int($0)) }

        guard !newUIDs.isEmpty else {
            folder.totalCount = Int(messageCount)
            folder.lastSyncDate = Date()
            try await emailRepository.saveFolder(folder)
            return []
        }

        // Fetch in batches
        var allNewEmails: [Email] = []
        var mutableLookup = emailLookup

        for batchStart in stride(from: 0, to: newUIDs.count, by: fetchBatchSize) {
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

                // Map to Email model
                let mappedEmail = mapToEmail(
                    header: header,
                    body: body,
                    accountId: account.id,
                    threadId: threadId
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
                allNewEmails.append(email)
            }

            // Flush all inserts for this batch in a single save
            try await emailRepository.flushChanges()
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
        try await emailRepository.saveFolder(folder)

        return allNewEmails
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
        threadId: String
    ) -> Email {
        let messageId = header.messageId ?? "<uid-\(header.uid)@\(accountId)>"
        // Deterministic ID for dedup across folders
        let emailId = stableId(accountId: accountId, messageId: messageId)

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
        Attachment(
            filename: info.filename ?? "attachment",
            mimeType: info.mimeType ?? "application/octet-stream",
            sizeBytes: Int(info.sizeBytes ?? 0),
            isDownloaded: false,
            bodySection: info.partId,
            contentId: info.contentId
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
